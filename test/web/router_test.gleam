import domain/event.{TimeSlot}
import gleam/dict
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/string
import gleeunit/should
import store/cache.{UpdateSchedules}
import web/router.{Context}
import wisp.{type Response, Text}
import wisp/simulate

fn response_body(res: Response) -> String {
  case res.body {
    Text(body_str) -> body_str
    _ -> ""
  }
}

pub fn health_endpoint_test() {
  let assert Ok(cache_subj) = cache.start()
  let ctx = Context(cache_subject: cache_subj)

  let req = simulate.request(Get, "/health")
  let res = router.handle_request(req, ctx)

  res.status |> should.equal(200)
  response_body(res) |> should.equal("{\"status\":\"ok\"}")
}

pub fn status_endpoint_test() {
  let assert Ok(cache_subj) = cache.start()
  let ctx = Context(cache_subject: cache_subj)

  let schedules =
    dict.from_list([
      #("A171", [TimeSlot(100, 200)]),
      #("A172", []),
    ])

  process.call(cache_subj, 1000, fn(reply_to) {
    UpdateSchedules(schedules, 1_700_000_000, reply_to)
  })

  let req = simulate.request(Get, "/api/v1/status")
  let res = router.handle_request(req, ctx)

  res.status |> should.equal(200)
  response_body(res)
  |> should.equal("{\"total_rooms\":2,\"last_updated_unix\":1700000000}")
}

pub fn openapi_json_endpoint_test() {
  let assert Ok(cache_subj) = cache.start()
  let ctx = Context(cache_subject: cache_subj)

  let req = simulate.request(Get, "/openapi.json")
  let res = router.handle_request(req, ctx)

  res.status |> should.equal(200)
  string.contains(response_body(res), "\"openapi\":\"3.1.0\"")
  |> should.be_true
  string.contains(response_body(res), "\"/api/v1/rooms/free\"")
  |> should.be_true
}

pub fn swagger_docs_html_endpoint_test() {
  let assert Ok(cache_subj) = cache.start()
  let ctx = Context(cache_subject: cache_subj)

  let req = simulate.request(Get, "/docs")
  let res = router.handle_request(req, ctx)

  res.status |> should.equal(200)
  string.contains(response_body(res), "swagger-ui")
  |> should.be_true
}

pub fn find_free_rooms_with_human_date_and_time_test() {
  let assert Ok(cache_subj) = cache.start()
  let ctx = Context(cache_subject: cache_subj)

  let schedules =
    dict.from_list([
      #("A171", [TimeSlot(1_790_838_000, 1_790_841_600)]),
      #("A172", []),
      #("B101", []),
    ])

  process.call(cache_subj, 1000, fn(reply_to) {
    UpdateSchedules(schedules, 1_700_000_000, reply_to)
  })

  let req =
    simulate.request(
      Get,
      "/api/v1/rooms/free?date=2026-10-01&start_time=09:00&end_time=10:00",
    )
  let res = router.handle_request(req, ctx)

  res.status |> should.equal(200)
  let body = response_body(res)
  string.contains(body, "\"room\":\"A172\"") |> should.be_true
  string.contains(body, "\"room\":\"B101\"") |> should.be_true
  string.contains(body, "\"room\":\"A171\"") |> should.be_false
}

pub fn find_free_rooms_with_unix_timestamps_test() {
  let assert Ok(cache_subj) = cache.start()
  let ctx = Context(cache_subject: cache_subj)

  let schedules =
    dict.from_list([
      #("A171", [TimeSlot(100, 200)]),
      #("A172", []),
      #("A173", []),
    ])

  process.call(cache_subj, 1000, fn(reply_to) {
    UpdateSchedules(schedules, 1_700_000_000, reply_to)
  })

  let req =
    simulate.request(
      Get,
      "/api/v1/rooms/free?near=A171&from=100&to=200&limit=5",
    )
  let res = router.handle_request(req, ctx)

  res.status |> should.equal(200)
  let body = response_body(res)
  string.contains(body, "\"room\":\"A172\",\"distance\":1") |> should.be_true
  string.contains(body, "\"room\":\"A173\",\"distance\":2") |> should.be_true
  string.contains(body, "\"room\":\"A171\"") |> should.be_false
}

pub fn check_room_with_human_date_and_time_test() {
  let assert Ok(cache_subj) = cache.start()
  let ctx = Context(cache_subject: cache_subj)

  let busy_slot = TimeSlot(1_790_838_000, 1_790_841_600)
  let schedules = dict.from_list([#("A171", [busy_slot])])

  process.call(cache_subj, 1000, fn(reply_to) {
    UpdateSchedules(schedules, 1_700_000_000, reply_to)
  })

  let req_busy =
    simulate.request(
      Get,
      "/api/v1/rooms/A171/check?date=2026-10-01&time=09:30&end_time=10:30",
    )
  let res_busy = router.handle_request(req_busy, ctx)
  res_busy.status |> should.equal(200)
  let body_busy = response_body(res_busy)
  string.contains(body_busy, "\"is_free\":false") |> should.be_true
  string.contains(
    body_busy,
    "\"busy_during\":[{\"start\":1790838000,\"end\":1790841600}]",
  )
  |> should.be_true

  let req_free =
    simulate.request(
      Get,
      "/api/v1/rooms/A171/check?date=2026-10-01&time=12:00&end_time=13:00",
    )
  let res_free = router.handle_request(req_free, ctx)
  res_free.status |> should.equal(200)
  let body_free = response_body(res_free)
  string.contains(body_free, "\"is_free\":true") |> should.be_true
  string.contains(body_free, "\"busy_during\":[]") |> should.be_true
}

pub fn check_room_with_unix_timestamps_test() {
  let assert Ok(cache_subj) = cache.start()
  let ctx = Context(cache_subject: cache_subj)

  let busy_slot = TimeSlot(100, 200)
  let schedules = dict.from_list([#("A171", [busy_slot])])

  process.call(cache_subj, 1000, fn(reply_to) {
    UpdateSchedules(schedules, 1_700_000_000, reply_to)
  })

  let req_busy =
    simulate.request(Get, "/api/v1/rooms/A171/check?from=100&to=200")
  let res_busy = router.handle_request(req_busy, ctx)
  res_busy.status |> should.equal(200)
  string.contains(response_body(res_busy), "\"is_free\":false")
  |> should.be_true

  let req_free =
    simulate.request(Get, "/api/v1/rooms/A171/check?from=250&to=300")
  let res_free = router.handle_request(req_free, ctx)
  res_free.status |> should.equal(200)
  string.contains(response_body(res_free), "\"is_free\":true") |> should.be_true
}

pub fn find_free_rooms_invalid_near_param_test() {
  let assert Ok(cache_subj) = cache.start()
  let ctx = Context(cache_subject: cache_subj)

  let req = simulate.request(Get, "/api/v1/rooms/free?near=invalid_room")
  let res = router.handle_request(req, ctx)

  res.status |> should.equal(400)
  response_body(res)
  |> should.equal(
    "{\"error\":\"Invalid room name: invalid_room (expected format like A171)\"}",
  )
}

pub fn not_found_route_test() {
  let assert Ok(cache_subj) = cache.start()
  let ctx = Context(cache_subject: cache_subj)

  let req = simulate.request(Get, "/nonexistent/endpoint")
  let res = router.handle_request(req, ctx)

  res.status |> should.equal(404)
}

pub fn unsupported_method_test() {
  let assert Ok(cache_subj) = cache.start()
  let ctx = Context(cache_subject: cache_subj)

  let req = simulate.request(Post, "/health")
  let res = router.handle_request(req, ctx)

  res.status |> should.equal(404)
}
