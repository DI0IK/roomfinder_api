import birl
import domain/event.{type TimeSlot}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import parser/ics
import store/cache.{type Message as CacheMessage, UpdateSchedules}

pub type WorkerMessage {
  SyncNow
  ScheduledSync
}

pub type WorkerConfig {
  WorkerConfig(pause_between_downloads_ms: Int, sync_interval_ms: Int)
}

pub fn default_config() -> WorkerConfig {
  WorkerConfig(
    pause_between_downloads_ms: 150,
    sync_interval_ms: 1000 * 60 * 60,
  )
}

pub fn start(
  cache_subject: Subject(CacheMessage),
  config: WorkerConfig,
) -> Result(Subject(WorkerMessage), actor.StartError) {
  let self_subj = process.new_subject()

  case
    actor.new(Nil)
    |> actor.on_message(fn(state, msg: WorkerMessage) {
      case msg {
        SyncNow | ScheduledSync -> {
          io.println("[Sync Worker] Starting calendar sync...")
          case run_sync(cache_subject, config.pause_between_downloads_ms) {
            Ok(room_count) ->
              io.println(
                "[Sync Worker] Sync completed successfully! Rooms: "
                <> int.to_string(room_count),
              )
            Error(err) -> io.println("[Sync Worker] Sync error: " <> err)
          }

          process.send_after(self_subj, config.sync_interval_ms, ScheduledSync)
          actor.continue(state)
        }
      }
    })
    |> actor.start
  {
    Ok(started) -> {
      process.send(started.data, SyncNow)
      Ok(started.data)
    }
    Error(err) -> Error(err)
  }
}

pub fn run_sync(
  cache_subject: Subject(CacheMessage),
  delay_ms: Int,
) -> Result(Int, String) {
  use courses <- result.try(fetch_course_list())
  let re = ics.room_regex()

  let schedules =
    list.fold(courses, dict.new(), fn(acc_schedules, course_name) {
      let acc = case fetch_course_ics(course_name) {
        Ok(ics_body) -> {
          let bookings = ics.parse_ics(ics_body, re)
          merge_bookings(acc_schedules, bookings)
        }
        Error(_) -> acc_schedules
      }

      process.sleep(delay_ms)
      acc
    })

  let room_count = dict.size(schedules)
  let now_unix = birl.to_unix(birl.now())

  process.call(cache_subject, 5000, fn(reply_to) {
    UpdateSchedules(schedules, now_unix, reply_to)
  })

  Ok(room_count)
}

fn merge_bookings(
  schedules: Dict(String, List(TimeSlot)),
  bookings: List(ics.RoomBooking),
) -> Dict(String, List(TimeSlot)) {
  list.fold(bookings, schedules, fn(acc, booking) {
    dict.upsert(acc, booking.room, fn(existing) {
      case existing {
        Some(slots) -> [booking.slot, ..slots]
        None -> [booking.slot]
      }
    })
  })
}

pub fn fetch_course_list() -> Result(List(String), String) {
  let url = "https://api.dhbw.app/courses/KA/"
  case request.to(url) {
    Ok(req) -> {
      case httpc.send(req) {
        Ok(resp) if resp.status == 200 -> {
          let string_list_decoder = decode.list(decode.string)
          case json.parse(resp.body, string_list_decoder) {
            Ok(courses) -> Ok(courses)
            Error(_) -> Error("Failed to parse courses JSON")
          }
        }
        Ok(resp) ->
          Error(
            "DHBW courses API returned status: " <> int.to_string(resp.status),
          )
        Error(_) -> Error("HTTP request to DHBW courses API failed")
      }
    }
    Error(_) -> Error("Invalid course list URL")
  }
}

pub fn fetch_course_ics(course: String) -> Result(String, String) {
  let url = "https://dhbw.app/ical/" <> course
  case request.to(url) {
    Ok(req) -> {
      case httpc.send(req) {
        Ok(resp) if resp.status == 200 -> Ok(resp.body)
        Ok(resp) ->
          Error("DHBW ical returned status " <> int.to_string(resp.status))
        Error(_) -> Error("HTTP request failed for " <> course)
      }
    }
    Error(_) -> Error("Invalid ical URL")
  }
}
