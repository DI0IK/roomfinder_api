# DHBW Roomfinder API

A fast, lightweight, and concurrent room-finding API for DHBW Karlsruhe written in pure **Gleam** running on the **Erlang BEAM** virtual machine.

---

## Features

- **In-Memory Queries (<1ms)**: All room bookings are parsed and indexed in an in-memory OTP actor. No disk reads or regex execution on incoming HTTP queries.
- **Sequential Background Sync**: Downloads schedules sequentially with a polite delay (150ms) to avoid overloading the upstream university server.
- **Accurate Europe/Berlin Timezone Handling**: Handles Daylight Saving Time transitions (CET = UTC+1, CEST = UTC+2) seamlessly.
- **Flexible Endpoints**:
  1. Find available rooms by date and time (optionally sorted by proximity to a reference room)
  2. Check individual room availability for a specific time window (returns conflicting bookings if occupied)
- **Codeberg CI & Container Registry**: Automated test pipeline and Docker image builds on push.

---

## API Endpoints

### 1. Find Available Rooms

Query available rooms by date and time:

```http
GET /api/v1/rooms/free?date=2026-10-01&time=09:00&limit=10
```

Or using Unix timestamps and nearest reference room:
```http
GET /api/v1/rooms/free?near=A171&from=1790838000&to=1790845200&limit=10
```

#### Query Parameters:
- `date` *(optional)*: `YYYY-MM-DD` (e.g. `2026-10-01`)
- `time` *(optional)*: `HH:MM` (e.g. `09:00`, defaults to `08:00` if only `date` is given)
- `end_time` *(optional)*: `HH:MM` (defaults to `time + 2 hours`)
- `from` *(optional)*: Unix epoch seconds (defaults to current time if neither `date` nor `from` is specified)
- `to` *(optional)*: Unix epoch seconds (defaults to `from + 2 hours`)
- `near` *(optional)*: Reference room to calculate distance from (e.g. `A171`). If omitted, rooms are sorted alphabetically.
- `limit` *(optional)*: Maximum number of rooms to return (default: `10`).

#### Response (`200 OK`):
```json
{
  "from_unix": 1790838000,
  "to_unix": 1790845200,
  "rooms": [
    { "room": "A172", "distance": 1 },
    { "room": "A173", "distance": 2 },
    { "room": "B240", "distance": 1131 }
  ]
}
```

---

### 2. Check Specific Room Availability

Check whether a room is free or occupied during a given time:

```http
GET /api/v1/rooms/A171/check?date=2026-10-01&time=09:00
```

Or using Unix timestamps:
```http
GET /api/v1/rooms/A171/check?from=1790838000&to=1790845200
```

#### Response (`200 OK` - Room is Available):
```json
{
  "room": "A171",
  "is_free": true,
  "from_unix": 1790838000,
  "to_unix": 1790845200,
  "busy_during": []
}
```

#### Response (`200 OK` - Room is Occupied):
```json
{
  "room": "A171",
  "is_free": false,
  "from_unix": 1790838000,
  "to_unix": 1790845200,
  "busy_during": [
    {
      "start": 1790838000,
      "end": 1790841600
    }
  ]
}
```

---

### 3. Service Health & Status

- `GET /health` -> `{"status":"ok"}`
- `GET /api/v1/status` -> `{"total_rooms": 142, "last_updated_unix": 1790835000}`

---

## Development & Testing

```bash
# Run all tests
gleam test

# Check code formatting (linter)
gleam format --check src test

# Auto-format code
gleam format src test

# Run type checker
gleam check

# Start development server
gleam run
```

---

## Docker & Container Registry

The repository automatically builds and publishes container images to Codeberg Packages via `.forgejo/workflows/ci.yml`.

### Running Locally with Docker:

```bash
# Build the image
docker build -t roomfinder-api .

# Run the container
docker run -p 8000:8000 roomfinder-api
```
