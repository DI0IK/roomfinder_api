import wisp.{type Response}

const openapi_spec_json =
  "{\"openapi\":\"3.1.0\",\"info\":{\"title\":\"DHBW Roomfinder API\",\"description\":\"High-performance API for finding available lecture rooms at DHBW Karlsruhe.\",\"version\":\"1.0.0\"},\"servers\":[{\"url\":\"http://localhost:8000\",\"description\":\"Local development server\"}],\"paths\":{\"/api/v1/rooms/free\":{\"get\":{\"summary\":\"Find available rooms\",\"description\":\"Returns rooms that have no active lecture bookings during the requested time window.\",\"operationId\":\"findFreeRooms\",\"parameters\":[{\"name\":\"date\",\"in\":\"query\",\"required\":false,\"description\":\"Date in format YYYY-MM-DD (e.g. 2026-10-08)\",\"schema\":{\"type\":\"string\",\"example\":\"2026-10-08\"}},{\"name\":\"time\",\"in\":\"query\",\"required\":false,\"description\":\"Start time in format HH:MM (e.g. 09:00, defaults to 08:00 if only date is given)\",\"schema\":{\"type\":\"string\",\"example\":\"09:00\"}},{\"name\":\"end_time\",\"in\":\"query\",\"required\":false,\"description\":\"End time in format HH:MM (defaults to start time + 2 hours)\",\"schema\":{\"type\":\"string\",\"example\":\"11:00\"}},{\"name\":\"from\",\"in\":\"query\",\"required\":false,\"description\":\"Start time as Unix epoch seconds (alternative to date/time)\",\"schema\":{\"type\":\"integer\",\"example\":1791439200}},{\"name\":\"to\",\"in\":\"query\",\"required\":false,\"description\":\"End time as Unix epoch seconds (defaults to from + 2 hours)\",\"schema\":{\"type\":\"integer\",\"example\":1791446400}},{\"name\":\"near\",\"in\":\"query\",\"required\":false,\"description\":\"Reference room to calculate distance from (e.g. A171). If omitted, sorted alphabetically.\",\"schema\":{\"type\":\"string\",\"example\":\"A171\"}},{\"name\":\"limit\",\"in\":\"query\",\"required\":false,\"description\":\"Maximum number of rooms returned (default 10)\",\"schema\":{\"type\":\"integer\",\"default\":10,\"example\":10}}],\"responses\":{\"200\":{\"description\":\"Successfully retrieved free rooms\",\"content\":{\"application/json\":{\"schema\":{\"type\":\"object\",\"required\":[\"from_unix\",\"to_unix\",\"rooms\"],\"properties\":{\"from_unix\":{\"type\":\"integer\",\"example\":1791439200},\"to_unix\":{\"type\":\"integer\",\"example\":1791446400},\"rooms\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"room\",\"distance\"],\"properties\":{\"room\":{\"type\":\"string\",\"example\":\"A172\"},\"distance\":{\"type\":\"integer\",\"example\":1}}}}}}}},\"400\":{\"description\":\"Invalid query parameters\",\"content\":{\"application/json\":{\"schema\":{\"type\":\"object\",\"required\":[\"error\"],\"properties\":{\"error\":{\"type\":\"string\",\"example\":\"Invalid room name: invalid_room (expected format like A171)\"}}}}}}}},\"/api/v1/rooms/{room_name}/check\":{\"get\":{\"summary\":\"Check specific room availability\",\"description\":\"Checks whether a specific room is free during the requested timeframe, returning conflicting time slots if occupied.\",\"operationId\":\"checkRoomAvailability\",\"parameters\":[{\"name\":\"room_name\",\"in\":\"path\",\"required\":true,\"description\":\"The room identifier (e.g. A171)\",\"schema\":{\"type\":\"string\",\"example\":\"A171\"}},{\"name\":\"date\",\"in\":\"query\",\"required\":false,\"description\":\"Date in format YYYY-MM-DD (e.g. 2026-10-08)\",\"schema\":{\"type\":\"string\",\"example\":\"2026-10-08\"}},{\"name\":\"time\",\"in\":\"query\",\"required\":false,\"description\":\"Start time in format HH:MM (e.g. 09:00)\",\"schema\":{\"type\":\"string\",\"example\":\"09:00\"}},{\"name\":\"end_time\",\"in\":\"query\",\"required\":false,\"description\":\"End time in format HH:MM\",\"schema\":{\"type\":\"string\",\"example\":\"11:00\"}},{\"name\":\"from\",\"in\":\"query\",\"required\":false,\"description\":\"Start time as Unix epoch seconds\",\"schema\":{\"type\":\"integer\",\"example\":1791439200}},{\"name\":\"to\",\"in\":\"query\",\"required\":false,\"description\":\"End time as Unix epoch seconds\",\"schema\":{\"type\":\"integer\",\"example\":1791446400}}],\"responses\":{\"200\":{\"description\":\"Room availability status\",\"content\":{\"application/json\":{\"schema\":{\"type\":\"object\",\"required\":[\"room\",\"is_free\",\"from_unix\",\"to_unix\",\"busy_during\"],\"properties\":{\"room\":{\"type\":\"string\",\"example\":\"A171\"},\"is_free\":{\"type\":\"boolean\",\"example\":true},\"from_unix\":{\"type\":\"integer\",\"example\":1791439200},\"to_unix\":{\"type\":\"integer\",\"example\":1791446400},\"busy_during\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"required\":[\"start\",\"end\"],\"properties\":{\"start\":{\"type\":\"integer\",\"example\":1791439200},\"end\":{\"type\":\"integer\",\"example\":1791442800}}}}}}}}},\"/api/v1/status\":{\"get\":{\"summary\":\"Service status\",\"description\":\"Returns cache information and last synchronization timestamp.\",\"operationId\":\"getStatus\",\"responses\":{\"200\":{\"description\":\"Status information\",\"content\":{\"application/json\":{\"schema\":{\"type\":\"object\",\"required\":[\"total_rooms\",\"last_updated_unix\"],\"properties\":{\"total_rooms\":{\"type\":\"integer\",\"example\":142},\"last_updated_unix\":{\"type\":\"integer\",\"example\":1791435000}}}}}}}},\"/health\":{\"get\":{\"summary\":\"Health check\",\"description\":\"Simple health check probe endpoint.\",\"operationId\":\"healthCheck\",\"responses\":{\"200\":{\"description\":\"Service is healthy\",\"content\":{\"application/json\":{\"schema\":{\"type\":\"object\",\"required\":[\"status\"],\"properties\":{\"status\":{\"type\":\"string\",\"example\":\"ok\"}}}}}}}}}}"

pub fn serve_openapi() -> Response {
  wisp.json_response(openapi_spec_json, 200)
}

pub fn serve_docs_html() -> Response {
  let html =
    "<!DOCTYPE html>
<html>
  <head>
    <title>DHBW Roomfinder API Docs</title>
    <meta charset=\"utf-8\"/>
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
    <link rel=\"stylesheet\" type=\"text/css\" href=\"https://unpkg.com/swagger-ui-dist@5/swagger-ui.css\" >
  </head>
  <body>
    <div id=\"swagger-ui\"></div>
    <script src=\"https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js\"></script>
    <script>
      window.onload = function() {
        SwaggerUIBundle({
          url: \"/openapi.json\",
          dom_id: '#swagger-ui',
          deepLinking: true,
          presets: [
            SwaggerUIBundle.presets.apis,
            SwaggerUIBundle.SwaggerUIStandalonePreset
          ]
        })
      }
    </script>
  </body>
</html>"

  wisp.html_response(html, 200)
}
