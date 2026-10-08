import domain/event.{TimeSlot}
import domain/room.{RoomId}
import gleam/dict
import gleam/erlang/process
import gleam/option.{None, Some}
import gleeunit/should
import store/cache.{
  type RoomAvailability, CheckRoom, FindFreeRooms, GetStatus, RoomResult,
  UpdateSchedules, check_room_availability, find_free_rooms,
}

pub fn find_free_rooms_sorting_by_distance_test() {
  let near = Some(RoomId("A", 1, 71))

  let schedules =
    dict.from_list([
      #("A171", [TimeSlot(100, 200)]),
      #("A172", [TimeSlot(300, 400)]),
      #("A173", []),
      #("A271", []),
      #("B171", []),
      #("C171", []),
    ])

  let results = find_free_rooms(schedules, near, 100, 200, 10)

  results
  |> should.equal([
    RoomResult("A172", 1),
    RoomResult("A173", 2),
    RoomResult("A271", 100),
    RoomResult("B171", 1000),
    RoomResult("C171", 2000),
  ])
}

pub fn find_free_rooms_without_near_sorts_alphabetically_test() {
  let schedules =
    dict.from_list([
      #("B171", []),
      #("A173", []),
      #("A172", []),
    ])

  let results = find_free_rooms(schedules, None, 100, 200, 10)

  results
  |> should.equal([
    RoomResult("A172", 0),
    RoomResult("A173", 0),
    RoomResult("B171", 0),
  ])
}

pub fn find_free_rooms_limit_respected_test() {
  let near = Some(RoomId("A", 1, 71))

  let schedules =
    dict.from_list([
      #("A172", []),
      #("A173", []),
      #("A174", []),
      #("A175", []),
      #("A176", []),
    ])

  let results = find_free_rooms(schedules, near, 0, 100, 2)
  let count = case results {
    [r1, r2] -> {
      r1.room |> should.equal("A172")
      r2.room |> should.equal("A173")
      2
    }
    _ -> 0
  }
  count |> should.equal(2)
}

pub fn find_free_rooms_when_all_rooms_busy_test() {
  let near = Some(RoomId("A", 1, 71))

  let schedules =
    dict.from_list([
      #("A171", [TimeSlot(100, 200)]),
      #("A172", [TimeSlot(50, 150)]),
    ])

  let results = find_free_rooms(schedules, near, 120, 180, 10)
  results |> should.equal([])
}

pub fn find_free_rooms_empty_schedule_test() {
  let near = Some(RoomId("A", 1, 71))
  let results = find_free_rooms(dict.new(), near, 0, 100, 10)
  results |> should.equal([])
}

pub fn check_room_availability_free_test() {
  let schedules =
    dict.from_list([
      #("A171", [TimeSlot(100, 200)]),
    ])

  let avail = check_room_availability(schedules, "A171", 200, 300)
  avail.is_free |> should.be_true
  avail.busy_during |> should.equal([])

  // Non-existent room is considered completely free
  let avail_unknown = check_room_availability(schedules, "UNKNOWN", 0, 100)
  avail_unknown.is_free |> should.be_true
  avail_unknown.busy_during |> should.equal([])
}

pub fn check_room_availability_busy_test() {
  let busy_slot = TimeSlot(100, 200)
  let schedules = dict.from_list([#("A171", [busy_slot])])

  let avail = check_room_availability(schedules, "A171", 150, 250)
  avail.is_free |> should.be_false
  avail.busy_during |> should.equal([busy_slot])
}

pub fn actor_lifecycle_and_updates_test() {
  let assert Ok(cache_subj) = cache.start()

  // 1. Initial status is empty
  let status1: cache.CacheStatus =
    process.call(cache_subj, 1000, fn(reply_to) { GetStatus(reply_to) })
  status1.total_rooms |> should.equal(0)
  status1.last_updated_unix |> should.equal(0)

  // 2. Push initial schedule
  let sched1 = dict.from_list([#("A171", [TimeSlot(100, 200)])])
  process.call(cache_subj, 1000, fn(reply_to) {
    UpdateSchedules(sched1, 1_000_000, reply_to)
  })

  let status2: cache.CacheStatus =
    process.call(cache_subj, 1000, fn(reply_to) { GetStatus(reply_to) })
  status2.total_rooms |> should.equal(1)
  status2.last_updated_unix |> should.equal(1_000_000)

  // 3. Atomically replace schedule
  let sched2 =
    dict.from_list([
      #("A171", []),
      #("B201", []),
      #("C301", []),
    ])
  process.call(cache_subj, 1000, fn(reply_to) {
    UpdateSchedules(sched2, 2_000_000, reply_to)
  })

  let status3: cache.CacheStatus =
    process.call(cache_subj, 1000, fn(reply_to) { GetStatus(reply_to) })
  status3.total_rooms |> should.equal(3)
  status3.last_updated_unix |> should.equal(2_000_000)

  // 4. Query updated cache
  let results: List(cache.RoomResult) =
    process.call(cache_subj, 1000, fn(reply_to) {
      FindFreeRooms(Some(RoomId("A", 1, 71)), 100, 200, 5, reply_to)
    })

  let first_room = case results {
    [r, ..] -> r.room
    [] -> ""
  }
  first_room |> should.equal("A171")

  // 5. Query CheckRoom via actor
  let check_res: RoomAvailability =
    process.call(cache_subj, 1000, fn(reply_to) {
      CheckRoom("A171", 100, 200, reply_to)
    })
  check_res.is_free |> should.be_true
}
