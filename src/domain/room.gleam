import gleam/bool
import gleam/int
import gleam/result
import gleam/string

pub type RoomId {
  RoomId(block: String, floor: Int, number: Int)
}

pub fn parse(str: String) -> Result(RoomId, Nil) {
  use <- bool.guard(when: string.length(str) < 3, return: Error(Nil))

  let block = string.slice(str, 0, 1) |> string.uppercase
  let floor_str = string.slice(str, 1, 1)

  // Ensure block is an ASCII letter A-Z
  let is_letter = case string.to_utf_codepoints(block) {
    [cp] -> {
      let val = string.utf_codepoint_to_int(cp)
      val >= 65 && val <= 90
    }
    _ -> False
  }
  use <- bool.guard(when: !is_letter, return: Error(Nil))

  use floor <- result.try(int.parse(floor_str))
  use number <- result.try(int.parse(string.slice(str, 2, string.length(str))))

  Ok(RoomId(block, floor, number))
}

pub fn to_string(room_id: RoomId) -> String {
  room_id.block <> int.to_string(room_id.floor) <> int.to_string(room_id.number)
}

pub fn distance(a: RoomId, b: RoomId) -> Int {
  let a_block_val = block_to_val(a.block)
  let b_block_val = block_to_val(b.block)

  let block_diff = int.absolute_value(b_block_val - a_block_val)
  let floor_diff = int.absolute_value(b.floor - a.floor)
  let number_diff = int.absolute_value(b.number - a.number)

  block_diff * 1000 + floor_diff * 100 + number_diff
}

fn block_to_val(b: String) -> Int {
  case string.to_utf_codepoints(b) {
    [cp, ..] -> string.utf_codepoint_to_int(cp)
    [] -> 0
  }
}
