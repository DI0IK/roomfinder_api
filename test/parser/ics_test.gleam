import domain/event.{TimeSlot}
import gleeunit/should
import parser/ics

const sample_ics =
  "BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//DHBW//DHBW.app//DE
BEGIN:VTIMEZONE
TZID:Europe/Berlin
END:VTIMEZONE
BEGIN:VEVENT
UID:12345
DTSTART;TZID=Europe/Berlin:20261001T090000
DTEND;TZID=Europe/Berlin:20261001T121500
SUMMARY:Lecture 1
LOCATION:A468 Hörsaal, B120
END:VEVENT
BEGIN:VEVENT
UID:67890
DTSTART;TZID=Europe/Berlin:20261001T130000
DTEND;TZID=Europe/Berlin:20261001T161500
SUMMARY:Lecture 2
LOCATION:C236 Hörsaal
END:VEVENT
END:VCALENDAR"

pub fn extract_rooms_standard_test() {
  let re = ics.room_regex()
  ics.extract_rooms("A468 Hörsaal, B120 PC-Raum", re)
  |> should.equal(["A468", "B120"])
}

pub fn extract_rooms_case_insensitive_test() {
  let re = ics.room_regex()
  ics.extract_rooms("c240 Hörsaal, d326 Labor", re)
  |> should.equal(["C240", "D326"])
}

pub fn extract_rooms_no_room_location_test() {
  let re = ics.room_regex()
  ics.extract_rooms("Online-Veranstaltung Virtueller Raum", re)
  |> should.equal([])

  ics.extract_rooms("Moodle Teams Meeting", re)
  |> should.equal([])

  ics.extract_rooms("", re)
  |> should.equal([])
}

pub fn extract_rooms_single_isolated_room_test() {
  let re = ics.room_regex()
  ics.extract_rooms("E005", re)
  |> should.equal(["E005"])

  ics.extract_rooms("Raum G082", re)
  |> should.equal(["G082"])
}

pub fn parse_ics_multiple_events_test() {
  let re = ics.room_regex()
  let bookings = ics.parse_ics(sample_ics, re)

  let count = case bookings {
    [_b1, _b2, b3] -> {
      // 2026-10-01 09:00 CEST -> 1790838000
      // 2026-10-01 12:15 CEST -> 1790849700
      b3.slot
      |> should.equal(TimeSlot(start: 1_790_838_000, end: 1_790_849_700))
      3
    }
    _ -> 0
  }

  count |> should.equal(3)
}

pub fn parse_ics_empty_string_test() {
  let re = ics.room_regex()
  ics.parse_ics("", re)
  |> should.equal([])
}

pub fn parse_ics_no_vevents_test() {
  let re = ics.room_regex()
  let content =
    "BEGIN:VCALENDAR
VERSION:2.0
PRODID:TEST
END:VCALENDAR"
  ics.parse_ics(content, re)
  |> should.equal([])
}

pub fn parse_ics_event_without_location_test() {
  let re = ics.room_regex()
  let content =
    "BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART;TZID=Europe/Berlin:20261001T090000
DTEND;TZID=Europe/Berlin:20261001T121500
SUMMARY:Independent study
END:VEVENT
END:VCALENDAR"
  ics.parse_ics(content, re)
  |> should.equal([])
}

pub fn parse_ics_event_with_utc_timestamps_test() {
  let re = ics.room_regex()
  let content =
    "BEGIN:VCALENDAR
BEGIN:VEVENT
DTSTART:20261001T090000Z
DTEND:20261001T121500Z
LOCATION:A171
END:VEVENT
END:VCALENDAR"
  let bookings = ics.parse_ics(content, re)
  let len = case bookings {
    [b] -> {
      b.room |> should.equal("A171")
      1
    }
    _ -> 0
  }
  len |> should.equal(1)
}
