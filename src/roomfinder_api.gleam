import gleam/erlang/process
import gleam/io
import gleam/string
import mist
import store/cache
import web/router.{Context}
import wisp
import wisp/wisp_mist
import worker/sync

pub fn main() {
  wisp.configure_logger()

  // 1. Start in-memory Room Cache Actor
  let assert Ok(cache_subj) = cache.start()
  io.println("[Server] Room cache actor started.")

  // 2. Start Background Sync Worker (sequential downloading, politeness pause)
  let worker_config = sync.default_config()
  let assert Ok(_worker_subj) = sync.start(cache_subj, worker_config)
  io.println("[Server] Background sync worker started.")

  // 3. Start Mist HTTP Server on port 8000, listening on all network interfaces (0.0.0.0)
  let ctx = Context(cache_subject: cache_subj)
  let secret_key_base = wisp.random_string(64)

  let handler = fn(req) { router.handle_request(req, ctx) }

  let server_result =
    wisp_mist.handler(handler, secret_key_base)
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(8000)
    |> mist.start

  case server_result {
    Ok(_) -> {
      io.println("[Server] Listening on http://0.0.0.0:8000")
      process.sleep_forever()
    }
    Error(err) -> {
      io.println(
        "[Server] Failed to start HTTP server: " <> string.inspect(err),
      )
    }
  }
}
