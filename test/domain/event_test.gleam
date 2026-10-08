import domain/event.{TimeSlot}
import gleam/list
import gleeunit/should

pub fn overlaps_completely_before_test() {
  let slot = TimeSlot(start: 100, end: 200)
  event.overlaps(slot, 0, 50)
  |> should.be_false
}

pub fn overlaps_touches_start_boundary_test() {
  let slot = TimeSlot(start: 100, end: 200)
  // [50, 100] meets [100, 200] at boundary 100: not overlapping
  event.overlaps(slot, 50, 100)
  |> should.be_false
}

pub fn overlaps_straddles_start_test() {
  let slot = TimeSlot(start: 100, end: 200)
  event.overlaps(slot, 50, 150)
  |> should.be_true
}

pub fn overlaps_strictly_inside_test() {
  let slot = TimeSlot(start: 100, end: 200)
  event.overlaps(slot, 120, 180)
  |> should.be_true
}

pub fn overlaps_exact_match_test() {
  let slot = TimeSlot(start: 100, end: 200)
  event.overlaps(slot, 100, 200)
  |> should.be_true
}

pub fn overlaps_completely_enclosing_test() {
  let slot = TimeSlot(start: 100, end: 200)
  event.overlaps(slot, 50, 250)
  |> should.be_true
}

pub fn overlaps_straddles_end_test() {
  let slot = TimeSlot(start: 100, end: 200)
  event.overlaps(slot, 150, 250)
  |> should.be_true
}

pub fn overlaps_touches_end_boundary_test() {
  let slot = TimeSlot(start: 100, end: 200)
  // [200, 250] meets [100, 200] at boundary 200: not overlapping
  event.overlaps(slot, 200, 250)
  |> should.be_false
}

pub fn overlaps_completely_after_test() {
  let slot = TimeSlot(start: 100, end: 200)
  event.overlaps(slot, 250, 300)
  |> should.be_false
}

pub fn is_free_empty_slots_test() {
  event.is_free([], 100, 200)
  |> should.be_true
}

pub fn is_free_with_multiple_slots_test() {
  let slots = [
    TimeSlot(100, 200),
    TimeSlot(300, 400),
    TimeSlot(500, 600),
  ]

  // Free in gap 1 [200, 300]
  event.is_free(slots, 200, 300)
  |> should.be_true

  // Free in gap 2 [400, 500]
  event.is_free(slots, 400, 500)
  |> should.be_true

  // Occupied in first slot [150, 250]
  event.is_free(slots, 150, 250)
  |> should.be_false

  // Occupied in middle slot [350, 360]
  event.is_free(slots, 350, 360)
  |> should.be_false

  // Free before all [0, 99]
  event.is_free(slots, 0, 99)
  |> should.be_true

  // Free after all [601, 700]
  event.is_free(slots, 601, 700)
  |> should.be_true
}

pub fn berlin_timezone_winter_cet_test() {
  // January 15 (winter / CET): UTC+1 -> 3600s
  event.berlin_utc_offset_seconds(2026, 1, 15, 12)
  |> should.equal(3600)

  // February 28 -> 3600s
  event.berlin_utc_offset_seconds(2025, 2, 28, 23)
  |> should.equal(3600)

  // December 31 -> 3600s
  event.berlin_utc_offset_seconds(2026, 12, 31, 18)
  |> should.equal(3600)
}

pub fn berlin_timezone_summer_cest_test() {
  // June 21 (summer / CEST): UTC+2 -> 7200s
  event.berlin_utc_offset_seconds(2024, 6, 21, 12)
  |> should.equal(7200)

  // July 14 -> 7200s
  event.berlin_utc_offset_seconds(2025, 7, 14, 15)
  |> should.equal(7200)

  // August 1 -> 7200s
  event.berlin_utc_offset_seconds(2026, 8, 1, 9)
  |> should.equal(7200)

  // May 10 -> 7200s
  event.berlin_utc_offset_seconds(2027, 5, 10, 14)
  |> should.equal(7200)
}

pub fn berlin_timezone_spring_transition_test() {
  // 2026-03-29 (last Sunday of March):
  // At 01:00 CET -> 3600s
  event.berlin_utc_offset_seconds(2026, 3, 29, 1)
  |> should.equal(3600)

  // At 03:00 CEST -> 7200s
  event.berlin_utc_offset_seconds(2026, 3, 29, 3)
  |> should.equal(7200)

  // Day before (March 28) -> 3600s
  event.berlin_utc_offset_seconds(2026, 3, 28, 23)
  |> should.equal(3600)

  // Day after (March 30) -> 7200s
  event.berlin_utc_offset_seconds(2026, 3, 30, 8)
  |> should.equal(7200)
}

pub fn berlin_timezone_autumn_transition_test() {
  // 2026-10-25 (last Sunday of October):
  // At 01:00 CEST -> 7200s
  event.berlin_utc_offset_seconds(2026, 10, 25, 1)
  |> should.equal(7200)

  // At 04:00 CET -> 3600s
  event.berlin_utc_offset_seconds(2026, 10, 25, 4)
  |> should.equal(3600)

  // Day before (October 24) -> 7200s
  event.berlin_utc_offset_seconds(2026, 10, 24, 12)
  |> should.equal(7200)

  // Day after (October 26) -> 3600s
  event.berlin_utc_offset_seconds(2026, 10, 26, 9)
  |> should.equal(3600)
}

pub fn parse_datetime_to_unix_utc_epoch_test() {
  // 1970-01-01T00:00:00 in UTC = 0
  event.parse_datetime_to_unix("19700101T000000", False)
  |> should.equal(Ok(0))

  // 1970-01-01T01:00:00 in UTC = 3600
  event.parse_datetime_to_unix("19700101T010000", False)
  |> should.equal(Ok(3600))
}

pub fn parse_datetime_to_unix_verified_timestamps_test() {
  // These verified against standard IANA Europe/Berlin zoneinfo database:
  let test_cases = [
    #("20240101T000000", 1_704_063_600),
    #("20250228T235900", 1_740_783_540),
    #("20261231T183000", 1_798_738_200),
    #("20270115T084500", 1_799_999_100),
    #("20240621T120000", 1_718_964_000),
    #("20250714T153000", 1_752_499_800),
    #("20260801T091500", 1_785_568_500),
    #("20270510T140000", 1_809_950_400),
    #("20260329T010000", 1_774_742_400),
    #("20260329T030000", 1_774_746_000),
    #("20260328T230000", 1_774_735_200),
    #("20260330T080000", 1_774_850_400),
    #("20261024T120000", 1_792_836_000),
    #("20261025T000000", 1_792_879_200),
    #("20261025T040000", 1_792_897_200),
    #("20261026T090000", 1_793_001_600),
    #("20240229T120000", 1_709_204_400),
  ]

  list.each(test_cases, fn(tc) {
    let #(dt_str, expected_unix) = tc
    event.parse_datetime_to_unix(dt_str, True)
    |> should.equal(Ok(expected_unix))
  })
}

pub fn parse_datetime_invalid_formats_test() {
  event.parse_datetime_to_unix("", True)
  |> should.equal(Error(Nil))

  event.parse_datetime_to_unix("20261001", True)
  |> should.equal(Error(Nil))

  event.parse_datetime_to_unix("not-a-date", True)
  |> should.equal(Error(Nil))

  event.parse_datetime_to_unix("20261301T120000", True)
  |> should.equal(Error(Nil))

  event.parse_datetime_to_unix("20260001T120000", True)
  |> should.equal(Error(Nil))
}
