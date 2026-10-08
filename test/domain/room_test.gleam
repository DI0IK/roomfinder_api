import domain/room.{RoomId}
import gleeunit/should

pub fn parse_standard_room_test() {
  room.parse("A171")
  |> should.equal(Ok(RoomId("A", 1, 71)))

  room.parse("B240")
  |> should.equal(Ok(RoomId("B", 2, 40)))

  room.parse("C012")
  |> should.equal(Ok(RoomId("C", 0, 12)))
}

pub fn parse_lowercase_room_test() {
  room.parse("a171")
  |> should.equal(Ok(RoomId("A", 1, 71)))

  room.parse("g082")
  |> should.equal(Ok(RoomId("G", 0, 82)))
}

pub fn parse_multi_digit_room_test() {
  room.parse("B3025")
  |> should.equal(Ok(RoomId("B", 3, 25)))

  room.parse("D4100")
  |> should.equal(Ok(RoomId("D", 4, 100)))
}

pub fn parse_zero_floor_room_test() {
  room.parse("E005")
  |> should.equal(Ok(RoomId("E", 0, 5)))

  room.parse("A056")
  |> should.equal(Ok(RoomId("A", 0, 56)))
}

pub fn parse_invalid_short_string_test() {
  room.parse("")
  |> should.equal(Error(Nil))

  room.parse("A")
  |> should.equal(Error(Nil))

  room.parse("A1")
  |> should.equal(Error(Nil))
}

pub fn parse_invalid_non_letter_block_test() {
  room.parse("123")
  |> should.equal(Error(Nil))

  room.parse("-171")
  |> should.equal(Error(Nil))

  room.parse("@171")
  |> should.equal(Error(Nil))
}

pub fn parse_invalid_non_numeric_floor_or_number_test() {
  room.parse("AXY")
  |> should.equal(Error(Nil))

  room.parse("A1BC")
  |> should.equal(Error(Nil))

  room.parse("Audimax")
  |> should.equal(Error(Nil))

  room.parse("Moodle")
  |> should.equal(Error(Nil))
}

pub fn to_string_formatting_test() {
  room.to_string(RoomId("A", 1, 71))
  |> should.equal("A171")

  room.to_string(RoomId("G", 0, 82))
  |> should.equal("G082")

  room.to_string(RoomId("B", 3, 25))
  |> should.equal("B325")
}

pub fn distance_identity_test() {
  let r = RoomId("C", 2, 40)
  room.distance(r, r)
  |> should.equal(0)
}

pub fn distance_symmetry_test() {
  let r1 = RoomId("A", 1, 71)
  let r2 = RoomId("D", 3, 20)
  room.distance(r1, r2)
  |> should.equal(room.distance(r2, r1))
}

pub fn distance_same_block_different_rooms_test() {
  let r1 = RoomId("A", 1, 71)
  let r2 = RoomId("A", 1, 72)
  room.distance(r1, r2)
  |> should.equal(1)

  let r3 = RoomId("A", 1, 80)
  room.distance(r1, r3)
  |> should.equal(9)
}

pub fn distance_same_block_different_floors_test() {
  let r1 = RoomId("A", 1, 71)
  let r2 = RoomId("A", 3, 71)
  // Floor diff = 2 * 100 = 200
  room.distance(r1, r2)
  |> should.equal(200)
}

pub fn distance_different_blocks_test() {
  let r1 = RoomId("A", 1, 71)
  let r2 = RoomId("B", 1, 71)
  // Block diff = 1 * 1000 = 1000
  room.distance(r1, r2)
  |> should.equal(1000)

  let r3 = RoomId("C", 1, 71)
  // Block diff = 2 * 1000 = 2000
  room.distance(r1, r3)
  |> should.equal(2000)
}

pub fn distance_combined_difference_test() {
  // A171 to B272:
  // |B - A| * 1000 = 1000
  // |2 - 1| * 100 = 100
  // |72 - 71| = 1
  // Total = 1101
  let r1 = RoomId("A", 1, 71)
  let r2 = RoomId("B", 2, 72)
  room.distance(r1, r2)
  |> should.equal(1101)
}
