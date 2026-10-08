import domain/event.{type TimeSlot, TimeSlot}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/regexp.{type Regexp, Match}
import gleam/string

pub type RoomBooking {
  RoomBooking(room: String, slot: TimeSlot)
}

type EventAccumulator {
  EventAccumulator(
    dtstart: Option(String),
    dtend: Option(String),
    location: Option(String),
    in_event: Bool,
  )
}

fn empty_event_acc() -> EventAccumulator {
  EventAccumulator(dtstart: None, dtend: None, location: None, in_event: False)
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
/// Performs zero disk I/O, pure in-memory streaming line-by-line.
pub fn parse_ics(ics_content: String, re: Regexp) -> List(RoomBooking) {
  let lines = string.split(ics_content, "\n")
  parse_lines(lines, empty_event_acc(), re, [])
}

fn parse_lines(
  lines: List(String),
  acc: EventAccumulator,
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
                  let new_bookings =
                    list.map(rooms, fn(room) {
                      RoomBooking(room: room, slot: slot)
                    })
                  list.append(new_bookings, results)
                }
                _, _ -> results
              }
            }
            _, _, _ -> results
          }
          parse_lines(rest, empty_event_acc(), re, updated_results)
        }

        _ if acc.in_event -> {
          let new_acc = update_event_accumulator(acc, line)
          parse_lines(rest, new_acc, re, results)
        }

        _ -> parse_lines(rest, acc, re, results)
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
    _ -> acc
  }
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
