import domain/event.{type BookingDetail}
import domain/room.{type RoomId}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/otp/actor
import gleam/string

pub type RoomResult {
  RoomResult(room: String, distance: Int)
}

pub type RoomAvailability {
  RoomAvailability(
    room: String,
    is_free: Bool,
    busy_during: List(BookingDetail),
  )
}

pub type CacheStatus {
  CacheStatus(total_rooms: Int, last_updated_unix: Int)
}

pub type State {
  State(schedules: Dict(String, List(BookingDetail)), last_updated_unix: Int)
}

pub type Message {
  /// Queries available rooms during [start_unix, end_unix], optionally sorted by distance to `near`
  FindFreeRooms(
    near: Option(RoomId),
    start_unix: Int,
    end_unix: Int,
    limit: Int,
    reply_to: Subject(List(RoomResult)),
  )
  /// Checks if a specific room is free during [start_unix, end_unix]
  CheckRoom(
    room_name: String,
    start_unix: Int,
    end_unix: Int,
    reply_to: Subject(RoomAvailability),
  )
  /// Gets all blockings for a room during [start_unix, end_unix]
  GetRoomBlockings(
    room_name: String,
    start_unix: Int,
    end_unix: Int,
    reply_to: Subject(List(BookingDetail)),
  )
  /// Atomically updates the entire schedule snapshot in memory
  UpdateSchedules(
    schedules: Dict(String, List(BookingDetail)),
    updated_at_unix: Int,
    reply_to: Subject(Nil),
  )
  /// Queries cache status
  GetStatus(reply_to: Subject(CacheStatus))
}

pub fn new_state() -> State {
  State(schedules: dict.new(), last_updated_unix: 0)
}

pub fn start() -> Result(Subject(Message), actor.StartError) {
  case
    actor.new(new_state())
    |> actor.on_message(handle_message)
    |> actor.start
  {
    Ok(started) -> Ok(started.data)
    Error(err) -> Error(err)
  }
}

fn handle_message(state: State, msg: Message) -> actor.Next(State, Message) {
  case msg {
    FindFreeRooms(near, start_unix, end_unix, limit, reply_to) -> {
      let results =
        find_free_rooms(state.schedules, near, start_unix, end_unix, limit)
      process.send(reply_to, results)
      actor.continue(state)
    }

    CheckRoom(room_name, start_unix, end_unix, reply_to) -> {
      let availability =
        check_room_availability(
          state.schedules,
          room_name,
          start_unix,
          end_unix,
        )
      process.send(reply_to, availability)
      actor.continue(state)
    }

    GetRoomBlockings(room_name, start_unix, end_unix, reply_to) -> {
      let blockings =
        get_room_blockings(state.schedules, room_name, start_unix, end_unix)
      process.send(reply_to, blockings)
      actor.continue(state)
    }

    UpdateSchedules(new_schedules, updated_at_unix, reply_to) -> {
      process.send(reply_to, Nil)
      actor.continue(State(
        schedules: new_schedules,
        last_updated_unix: updated_at_unix,
      ))
    }

    GetStatus(reply_to) -> {
      process.send(
        reply_to,
        CacheStatus(
          total_rooms: dict.size(state.schedules),
          last_updated_unix: state.last_updated_unix,
        ),
      )
      actor.continue(state)
    }
  }
}

/// Pure helper: returns all blockings overlapping [start_unix, end_unix] for a room,
/// sorted chronologically by start timestamp.
pub fn get_room_blockings(
  schedules: Dict(String, List(BookingDetail)),
  room_name: String,
  start_unix: Int,
  end_unix: Int,
) -> List(BookingDetail) {
  let bookings = case dict.get(schedules, room_name) {
    Ok(s) -> s
    Error(Nil) -> []
  }

  bookings
  |> list.filter(fn(b) { event.booking_overlaps(b, start_unix, end_unix) })
  |> list.sort(fn(a, b) { int.compare(a.start, b.start) })
}

/// Pure helper: checks availability and conflicting blockings for a specific room.
pub fn check_room_availability(
  schedules: Dict(String, List(BookingDetail)),
  room_name: String,
  start_unix: Int,
  end_unix: Int,
) -> RoomAvailability {
  let conflicts = get_room_blockings(schedules, room_name, start_unix, end_unix)

  RoomAvailability(
    room: room_name,
    is_free: conflicts == [],
    busy_during: conflicts,
  )
}

/// Pure helper: filters free rooms from the schedule dict.
/// If `near` is provided, sorts by distance ascending.
/// If `near` is None, sorts alphabetically by room name.
pub fn find_free_rooms(
  schedules: Dict(String, List(BookingDetail)),
  near: Option(RoomId),
  start_unix: Int,
  end_unix: Int,
  limit: Int,
) -> List(RoomResult) {
  dict.to_list(schedules)
  |> list.filter_map(fn(entry) {
    let #(room_name, bookings) = entry
    case event.is_booking_free(bookings, start_unix, end_unix) {
      True -> {
        case near {
          Some(origin) -> {
            case room.parse(room_name) {
              Ok(target_id) -> {
                let dist = room.distance(origin, target_id)
                Ok(RoomResult(room: room_name, distance: dist))
              }
              Error(Nil) -> Ok(RoomResult(room: room_name, distance: 999_999))
            }
          }
          None -> Ok(RoomResult(room: room_name, distance: 0))
        }
      }
      False -> Error(Nil)
    }
  })
  |> list.sort(fn(a, b) {
    case near {
      Some(_) ->
        case int.compare(a.distance, b.distance) {
          order.Eq -> string.compare(a.room, b.room)
          diff -> diff
        }
      None -> string.compare(a.room, b.room)
    }
  })
  |> list.take(limit)
}
