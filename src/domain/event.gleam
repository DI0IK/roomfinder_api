import gleam/bool
import gleam/int
import gleam/result
import gleam/string

pub type TimeSlot {
  TimeSlot(start: Int, end: Int)
}

/// Checks if two time intervals overlap.
/// An event occupying [slot.start, slot.end] overlaps with [query_start, query_end]
/// if slot.start < query_end and slot.end > query_start.
pub fn overlaps(slot: TimeSlot, query_start: Int, query_end: Int) -> Bool {
  slot.start < query_end && slot.end > query_start
}

/// Checks if a list of booked time slots is free during the given query window.
pub fn is_free(
  slots: List(TimeSlot),
  query_start: Int,
  query_end: Int,
) -> Bool {
  case slots {
    [] -> True
    [slot, ..rest] ->
      case overlaps(slot, query_start, query_end) {
        True -> False
        False -> is_free(rest, query_start, query_end)
      }
  }
}

/// Parses an ICS date-time string (e.g. "20261001T090000" or with trailing 'Z')
/// into a Unix epoch timestamp in seconds.
///
/// DHBW events are in Europe/Berlin local time or UTC.
/// If `tzid` is "Europe/Berlin" or omitted for DHBW schedules, we apply Europe/Berlin
/// timezone offset (CET = UTC+1, CEST = UTC+2) to convert correctly to UTC Unix seconds.
pub fn parse_datetime_to_unix(
  dt_str: String,
  is_berlin_tz: Bool,
) -> Result(Int, Nil) {
  let clean_str = string.replace(dt_str, "Z", "")
  case string.split_once(clean_str, "T") {
    Ok(#(date_part, time_part)) -> {
      use #(year, month, day) <- result.try(parse_date(date_part))
      use #(hour, minute, second) <- result.try(parse_time(time_part))

      let utc_days = days_from_civil(year, month, day)
      let seconds_of_day = hour * 3600 + minute * 60 + second
      let naive_epoch_seconds = utc_days * 86_400 + seconds_of_day

      case is_berlin_tz {
        True -> {
          let offset_seconds = berlin_utc_offset_seconds(year, month, day, hour)
          Ok(naive_epoch_seconds - offset_seconds)
        }
        False -> Ok(naive_epoch_seconds)
      }
    }
    Error(_) -> Error(Nil)
  }
}

fn parse_date(date_str: String) -> Result(#(Int, Int, Int), Nil) {
  use <- bool.guard(when: string.length(date_str) != 8, return: Error(Nil))
  let year_str = string.slice(date_str, 0, 4)
  let month_str = string.slice(date_str, 4, 2)
  let day_str = string.slice(date_str, 6, 2)
  case int.parse(year_str), int.parse(month_str), int.parse(day_str) {
    Ok(y), Ok(m), Ok(d) if m >= 1 && m <= 12 && d >= 1 && d <= 31 ->
      Ok(#(y, m, d))
    _, _, _ -> Error(Nil)
  }
}

fn parse_time(time_str: String) -> Result(#(Int, Int, Int), Nil) {
  let clean_time = string.slice(time_str, 0, 6)
  use <- bool.guard(when: string.length(clean_time) != 6, return: Error(Nil))
  let hour_str = string.slice(clean_time, 0, 2)
  let min_str = string.slice(clean_time, 2, 2)
  let sec_str = string.slice(clean_time, 4, 2)
  case int.parse(hour_str), int.parse(min_str), int.parse(sec_str) {
    Ok(h), Ok(m), Ok(s)
      if h >= 0 && h <= 23 && m >= 0 && m <= 59 && s >= 0 && s <= 59
    -> Ok(#(h, m, s))
    _, _, _ -> Error(Nil)
  }
}

/// Computes days from Unix epoch (1970-01-01) for a given Gregorian date.
/// Howard Hinnant's algorithm.
fn days_from_civil(y: Int, m: Int, d: Int) -> Int {
  let y_adj = case m <= 2 {
    True -> y - 1
    False -> y
  }
  let era = case y_adj >= 0 {
    True -> y_adj / 400
    False -> { y_adj - 399 } / 400
  }
  let yoe = y_adj - era * 400
  let m_adj = case m > 2 {
    True -> m - 3
    False -> m + 9
  }
  let doy = { 153 * m_adj + 2 } / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146_097 + doe - 719_468
}

/// Day of week: 0 = Sunday, 1 = Monday, ..., 6 = Saturday
fn day_of_week(year: Int, month: Int, day: Int) -> Int {
  let days = days_from_civil(year, month, day)
  let dow = { days + 4 } % 7
  case dow < 0 {
    True -> dow + 7
    False -> dow
  }
}

/// Returns the day of month of the last Sunday in month `m` of `year`.
fn last_sunday_of_month(year: Int, month: Int) -> Int {
  let last_day = case month {
    3 -> 31
    10 -> 31
    _ -> 30
  }
  let dow = day_of_week(year, month, last_day)
  last_day - dow
}

/// Returns the UTC offset in seconds for Europe/Berlin at the given local date and hour.
/// CET  (winter) = UTC+1 = 3600 seconds
/// CEST (summer) = UTC+2 = 7200 seconds
///
/// Daylight Saving Time rules for Europe/Berlin:
/// - Starts last Sunday of March at 02:00 CET (clock jumps to 03:00 CEST)
/// - Ends last Sunday of October at 03:00 CEST (clock turns back to 02:00 CET)
pub fn berlin_utc_offset_seconds(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
) -> Int {
  let is_dst = case month {
    m if m > 3 && m < 10 -> True
    3 -> {
      let mar_sun = last_sunday_of_month(year, 3)
      day > mar_sun || { day == mar_sun && hour >= 2 }
    }
    10 -> {
      let oct_sun = last_sunday_of_month(year, 10)
      day < oct_sun || { day == oct_sun && hour < 3 }
    }
    _ -> False
  }

  case is_dst {
    True -> 7200
    False -> 3600
  }
}
