import birl
import domain/event
import domain/room.{type RoomId}
import gleam/erlang/process.{type Subject}
import gleam/http.{Get}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import store/cache.{
  type CacheStatus, type Message as CacheMessage, type RoomAvailability,
  type RoomResult, CheckRoom, FindFreeRooms, GetStatus,
}
import web/docs
import wisp.{type Request, type Response}

pub type Context {
  Context(cache_subject: Subject(CacheMessage))
}

pub fn handle_request(req: Request, ctx: Context) -> Response {
  use req <- wisp.handle_head(req)

  case req.method, wisp.path_segments(req) {
    Get, ["health"] -> health_check()
    Get, ["api", "v1", "status"] -> status(ctx)
    Get, ["api", "v1", "rooms", "free"] -> find_free_rooms(req, ctx)
    Get, ["api", "v1", "rooms", room_name, "check"] ->
      check_room(req, ctx, room_name)
    Get, ["openapi.json"] -> docs.serve_openapi()
    Get, ["docs"] -> docs.serve_docs_html()
    _, _ -> wisp.not_found()
  }
}

fn health_check() -> Response {
  wisp.json_response(
    json.to_string(json.object([#("status", json.string("ok"))])),
    200,
  )
}

fn status(ctx: Context) -> Response {
  let cache_status: CacheStatus =
    process.call(ctx.cache_subject, 1000, fn(reply_to) { GetStatus(reply_to) })

  wisp.json_response(
    json.to_string(
      json.object([
        #("total_rooms", json.int(cache_status.total_rooms)),
        #("last_updated_unix", json.int(cache_status.last_updated_unix)),
      ]),
    ),
    200,
  )
}

/// Feature 1: Datum + Uhrzeit => Freie Räume (optionally filtered / sorted near a room)
fn find_free_rooms(req: Request, ctx: Context) -> Response {
  let query = wisp.get_query(req)

  let near_str = list.key_find(query, "near")
  let limit_str = list.key_find(query, "limit")

  let near_result: Result(Option(RoomId), String) = case near_str {
    Ok(s) ->
      case room.parse(s) {
        Ok(r) -> Ok(Some(r))
        Error(Nil) ->
          Error("Invalid room name: " <> s <> " (expected format like A171)")
      }
    Error(_) -> Ok(None)
  }

  case near_result {
    Error(err_msg) -> bad_request(err_msg)
    Ok(maybe_near) -> {
      use #(from_unix, to_unix) <- result_guard(resolve_query_time_window(query))

      let limit = case limit_str {
        Ok(val) -> int.parse(val) |> result.unwrap(10)
        Error(_) -> 10
      }

      let rooms: List(RoomResult) =
        process.call(ctx.cache_subject, 1000, fn(reply_to) {
          FindFreeRooms(maybe_near, from_unix, to_unix, limit, reply_to)
        })

      let json_body =
        json.to_string(
          json.object([
            #("from_unix", json.int(from_unix)),
            #("to_unix", json.int(to_unix)),
            #(
              "rooms",
              json.array(rooms, fn(r) {
                json.object([
                  #("room", json.string(r.room)),
                  #("distance", json.int(r.distance)),
                ])
              }),
            ),
          ]),
        )

      wisp.json_response(json_body, 200)
    }
  }
}

/// Feature 2: Raum + Uhrzeit => frei oder nicht
fn check_room(req: Request, ctx: Context, room_name: String) -> Response {
  let query = wisp.get_query(req)

  use #(from_unix, to_unix) <- result_guard(resolve_query_time_window(query))

  let clean_room = string.uppercase(room_name)

  let availability: RoomAvailability =
    process.call(ctx.cache_subject, 1000, fn(reply_to) {
      CheckRoom(clean_room, from_unix, to_unix, reply_to)
    })

  let json_body =
    json.to_string(
      json.object([
        #("room", json.string(availability.room)),
        #("is_free", json.bool(availability.is_free)),
        #("from_unix", json.int(from_unix)),
        #("to_unix", json.int(to_unix)),
        #(
          "busy_during",
          json.array(availability.busy_during, fn(slot) {
            json.object([
              #("start", json.int(slot.start)),
              #("end", json.int(slot.end)),
            ])
          }),
        ),
      ]),
    )

  wisp.json_response(json_body, 200)
}

fn result_guard(res: Result(a, String), next: fn(a) -> Response) -> Response {
  case res {
    Ok(val) -> next(val)
    Error(err) -> bad_request(err)
  }
}

/// Resolves query parameters into a [start_unix, end_unix] window.
/// Supports both:
/// 1. Direct timestamps:
///    ?from=1790838000&to=1790845200
/// 2. Human friendly date + time:
///    ?date=2026-10-01&time=09:00&end_time=11:00
///    ?date=2026-10-01&start_time=09:00&end_time=11:00
///    ?start_date=2026-10-01&start_time=09:00&end_date=2026-10-01&end_time=11:00
pub fn resolve_query_time_window(
  query: List(#(String, String)),
) -> Result(#(Int, Int), String) {
  let from_str = list.key_find(query, "from")
  let to_str = list.key_find(query, "to")

  let date_str =
    list.key_find(query, "date")
    |> result.or(list.key_find(query, "start_date"))

  let end_date_str =
    list.key_find(query, "end_date")
    |> result.or(date_str)

  let start_time_str =
    list.key_find(query, "time")
    |> result.or(list.key_find(query, "start_time"))
    |> result.or(list.key_find(query, "startTime"))

  let end_time_str =
    list.key_find(query, "end_time")
    |> result.or(list.key_find(query, "endTime"))

  case date_str {
    Ok(start_d) -> {
      let start_t = case start_time_str {
        Ok(t) -> t
        Error(_) -> "08:00"
      }
      use start_unix <- result.try(parse_human_datetime(start_d, start_t))

      let end_unix_res = case end_time_str {
        Ok(end_t) -> {
          let end_d = result.unwrap(end_date_str, start_d)
          parse_human_datetime(end_d, end_t)
        }
        Error(_) ->
          case to_str {
            Ok(to_val) ->
              int.parse(to_val)
              |> result.map_error(fn(_) { "Invalid 'to' timestamp parameter" })
            Error(_) -> Ok(start_unix + 3600 * 2)
          }
      }

      use end_unix <- result.try(end_unix_res)
      Ok(#(start_unix, end_unix))
    }

    Error(_) -> {
      let now_unix = birl.to_unix(birl.now())
      let from_unix = case from_str {
        Ok(val) ->
          int.parse(val)
          |> result.unwrap(now_unix)
        Error(_) -> now_unix
      }
      let to_unix = case to_str {
        Ok(val) ->
          int.parse(val)
          |> result.unwrap(from_unix + 3600 * 2)
        Error(_) -> from_unix + 3600 * 2
      }
      Ok(#(from_unix, to_unix))
    }
  }
}

fn parse_human_datetime(
  date_str: String,
  time_str: String,
) -> Result(Int, String) {
  let compact_dt =
    string.replace(date_str, "-", "")
    <> "T"
    <> string.replace(time_str, ":", "")
    <> "00"

  case event.parse_datetime_to_unix(compact_dt, True) {
    Ok(unix_sec) -> Ok(unix_sec)
    Error(Nil) ->
      Error(
        "Invalid date/time format for '"
        <> date_str
        <> " "
        <> time_str
        <> "'. Expected YYYY-MM-DD and HH:MM",
      )
  }
}

fn bad_request(message: String) -> Response {
  wisp.json_response(
    json.to_string(json.object([#("error", json.string(message))])),
    400,
  )
}
