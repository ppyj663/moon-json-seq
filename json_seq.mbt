///|
/// RFC 7464 record separator and media type.
pub let media_type : String = "application/json-seq"

///|
/// A decoded JSON value or a recoverable record error. Offsets are absolute
/// byte positions: for values and record errors, the first byte after RS.
pub enum Event {
  Value(Json, Int)
  Error(String, Int)
}

///|
/// Produce one RFC 7464 record: RS, compact UTF-8 JSON, LF.
pub fn encode(value : Json) -> Bytes {
  let body = @utf8.encode(value.stringify())
  let out : Array[Byte] = [0x1e]
  for i = 0; i < body.length(); i = i + 1 {
    out.push(body[i])
  }
  out.push(0x0a)
  Bytes::from_array(out)
}

///|
/// Incremental decoder. It retains at most max_record_bytes bytes of a
/// record. Once a record exceeds the limit, data is discarded until the next
/// RS. A decoder cannot be fed after finish.
pub struct Decoder {
  max_record_bytes : Int
  mut buffer : Array[Byte]
  mut offset : Int
  mut start : Int
  mut in_record : Bool
  mut preamble_start : Int
  mut preamble_seen : Bool
  mut overflowed : Bool
  mut finished : Bool
}

///|
/// A positive limit is required. The recommended starting value is 1 MiB.
pub fn Decoder::new(max_record_bytes : Int) -> Result[Decoder, String] {
  if max_record_bytes <= 0 {
    Err("max_record_bytes must be positive")
  } else {
    Ok({
      max_record_bytes,
      buffer: [],
      offset: 0,
      start: 0,
      in_record: false,
      preamble_start: 0,
      preamble_seen: false,
      overflowed: false,
      finished: false,
    })
  }
}

///|
fn is_json_space(byte : Byte) -> Bool {
  byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d
}

///|
fn Decoder::close_record(self : Decoder, events : Array[Event]) -> Unit {
  if self.overflowed {
    events.push(Error("record exceeds max_record_bytes", self.start))
  } else if !self.buffer.is_empty() {
    let bytes = Bytes::from_array(self.buffer)
    let text = @utf8.decode(bytes) catch {
      _ => {
        events.push(Error("invalid UTF-8", self.start))
        return
      }
    }
    let mut first = 0
    while first < self.buffer.length() && is_json_space(self.buffer[first]) {
      first = first + 1
    }
    if first < self.buffer.length() {
      let lead = self.buffer[first]
      let scalar = lead == 0x2d ||
        (lead >= 0x30 && lead <= 0x39) ||
        lead == 0x74 ||
        lead == 0x66 ||
        lead == 0x6e
      if scalar && !is_json_space(self.buffer[self.buffer.length() - 1]) {
        events.push(
          Error("top-level scalar lacks trailing whitespace", self.start),
        )
        return
      }
    }
    let value = @json.parse(text) catch {
      _ => {
        events.push(Error("invalid JSON", self.start))
        return
      }
    }
    events.push(Value(value, self.start))
  }
}

///|
/// Consume a byte chunk and return all records closed by RS in this chunk.
/// Call finish to close the final record.
pub fn Decoder::feed(
  self : Decoder,
  chunk : Bytes,
) -> Result[Array[Event], String] {
  if self.finished {
    return Err("decoder already finished")
  }
  let events : Array[Event] = []
  for i = 0; i < chunk.length(); i = i + 1 {
    let byte = chunk[i]
    if byte == 0x1e {
      if self.in_record {
        self.close_record(events)
      } else if self.preamble_seen {
        events.push(Error("bytes before first RS", self.preamble_start))
      }
      self.in_record = true
      self.buffer = []
      self.overflowed = false
      self.start = self.offset + 1
    } else if self.in_record {
      if !self.overflowed {
        if self.buffer.length() == self.max_record_bytes {
          self.overflowed = true
          self.buffer = []
        } else {
          self.buffer.push(byte)
        }
      }
    } else if !self.preamble_seen {
      self.preamble_start = self.offset
      self.preamble_seen = true
    }
    self.offset = self.offset + 1
  }
  Ok(events)
}

///|
/// Close the final record. Repeated calls return an error.
pub fn Decoder::finish(self : Decoder) -> Result[Array[Event], String] {
  if self.finished {
    return Err("decoder already finished")
  }
  self.finished = true
  let events : Array[Event] = []
  if self.in_record {
    self.close_record(events)
  } else if self.preamble_seen {
    events.push(Error("bytes before first RS", self.preamble_start))
  }
  Ok(events)
}
