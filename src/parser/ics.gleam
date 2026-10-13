import domain/event.{type TimeSlot, TimeSlot}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Regexp, Match}
import gleam/string

pub type RoomBooking {
  RoomBooking(room: String, slot: TimeSlot, summary: String, course: String)
}

type EventAccumulator {
  EventAccumulator(
    dtstart: Option(String),
    dtend: Option(String),
    location: Option(String),
    summary: Option(String),
    in_event: Bool,
  )
}

fn empty_event_acc() -> EventAccumulator {
  EventAccumulator(
    dtstart: None,
    dtend: None,
    location: None,
    summary: None,
    in_event: False,
  )
}

/// Creates a compiled regular expression for room extraction: ([A-Ga-g]\d{3})
pub fn room_regex() -> Regexp {
  let assert Ok(re) = regexp.from_string("([a-gA-G]\\d{3})")
  re
}

/// Extracts all room IDs matching [A-Ga-g]\d{3} from a LOCATION string.
/// For example: "A171 Hörsaal, B240 Labor" -> ["A171", "B240"]
pub fn extract_rooms(location: String, re: Regexp) -> List(String) {
  let matches = regexp.scan(re, location)
  list.filter_map(matches, fn(m) {
    case m {
      Match(submatches: [Some(room)], ..) -> Ok(string.uppercase(room))
      _ -> Error(Nil)
    }
  })
}

/// Parses an entire ICS calendar file string into a list of RoomBooking records.
pub fn parse_ics(ics_content: String, re: Regexp) -> List(RoomBooking) {
  parse_ics_with_course(ics_content, "", re)
}

/// Parses an entire ICS calendar file string into a list of RoomBooking records,
/// associating each booking with the specified course name.
/// Performs zero disk I/O, pure in-memory streaming line-by-line.
pub fn parse_ics_with_course(
  ics_content: String,
  course: String,
  re: Regexp,
) -> List(RoomBooking) {
  let clean_content = string.replace(ics_content, "\r", "")
  let lines = string.split(clean_content, "\n")
  let unfolded = unfold_lines(lines, [])
  parse_lines(unfolded, empty_event_acc(), course, re, [])
}

/// RFC 5545 Section 3.1: Unfolds lines split with leading whitespace (space or tab).
fn unfold_lines(raw_lines: List(String), acc: List(String)) -> List(String) {
  case raw_lines {
    [] -> list.reverse(acc)
    [line, ..rest] -> {
      case string.starts_with(line, " ") || string.starts_with(line, "\t") {
        True -> {
          let continuation = string.drop_start(line, 1)
          case acc {
            [prev, ..prev_rest] ->
              unfold_lines(rest, [prev <> continuation, ..prev_rest])
            [] -> unfold_lines(rest, [continuation])
          }
        }
        False -> unfold_lines(rest, [line, ..acc])
      }
    }
  }
}

fn parse_lines(
  lines: List(String),
  acc: EventAccumulator,
  course: String,
  re: Regexp,
  results: List(RoomBooking),
) -> List(RoomBooking) {
  case lines {
    [] -> results
    [raw_line, ..rest] -> {
      let line = string.trim(raw_line)
      case line {
        "BEGIN:VEVENT" ->
          parse_lines(
            rest,
            EventAccumulator(..empty_event_acc(), in_event: True),
            course,
            re,
            results,
          )

        "END:VEVENT" -> {
          let updated_results = case acc.dtstart, acc.dtend, acc.location {
            Some(dtstart_str), Some(dtend_str), Some(loc_str) -> {
              let rooms = extract_rooms(loc_str, re)
              case
                event.parse_datetime_to_unix(dtstart_str, True),
                event.parse_datetime_to_unix(dtend_str, True)
              {
                Ok(start_unix), Ok(end_unix) -> {
                  let slot = TimeSlot(start: start_unix, end: end_unix)
                  let summary = option.unwrap(acc.summary, "")
                  let new_bookings =
                    list.map(rooms, fn(room) {
                      RoomBooking(
                        room: room,
                        slot: slot,
                        summary: summary,
                        course: course,
                      )
                    })
                  list.append(new_bookings, results)
                }
                _, _ -> results
              }
            }
            _, _, _ -> results
          }
          parse_lines(rest, empty_event_acc(), course, re, updated_results)
        }

        _ if acc.in_event -> {
          let new_acc = update_event_accumulator(acc, line)
          parse_lines(rest, new_acc, course, re, results)
        }

        _ -> parse_lines(rest, acc, course, re, results)
      }
    }
  }
}

fn update_event_accumulator(
  acc: EventAccumulator,
  line: String,
) -> EventAccumulator {
  case line {
    "DTSTART" <> rest -> {
      let val = extract_prop_value(rest)
      EventAccumulator(..acc, dtstart: Some(val))
    }
    "DTEND" <> rest -> {
      let val = extract_prop_value(rest)
      EventAccumulator(..acc, dtend: Some(val))
    }
    "LOCATION:" <> val -> EventAccumulator(..acc, location: Some(val))
    "LOCATION;" <> rest -> {
      let val = extract_prop_value(";" <> rest)
      EventAccumulator(..acc, location: Some(val))
    }
    "SUMMARY:" <> val -> {
      let clean_val = clean_summary(val)
      EventAccumulator(..acc, summary: Some(clean_val))
    }
    "SUMMARY;" <> rest -> {
      let val = extract_prop_value(";" <> rest)
      let clean_val = clean_summary(val)
      EventAccumulator(..acc, summary: Some(clean_val))
    }
    _ -> acc
  }
}

fn clean_summary(raw: String) -> String {
  raw
  |> string.replace("\\,", ",")
  |> string.replace("\\;", ";")
  |> string.replace("\\\\", "\\")
  |> string.replace("\\n", " ")
  |> string.replace("\\N", " ")
  |> string.trim
}

/// Handles formats like:
/// ";TZID=Europe/Berlin:20261001T090000" -> "20261001T090000"
/// ":20261001T090000" -> "20261001T090000"
fn extract_prop_value(rest: String) -> String {
  case string.split_once(rest, ":") {
    Ok(#(_param, value)) -> value
    Error(_) -> rest
  }
}
