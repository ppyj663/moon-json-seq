///|
/// A raw RFC 7464 frame after its record separator. `start` is the first
/// byte after RS and `end` is the exclusive offset of the frame body.
pub(all) struct FrameRecord {
  start : Int
  end : Int
  bytes : Bytes
}

///|
/// Framing events preserve byte locations even when a JSON record is invalid.
/// Empty frames between consecutive RS bytes do not produce an event.
pub enum FrameEvent {
  DataFrame(FrameRecord)
  PreambleBytes(Int, Int)
  OversizedFrame(Int, Int)
}

///|
/// A bounded byte scanner for RFC 7464 record separators. It does not parse
/// JSON, making it useful when callers need raw bytes or custom diagnostics.
pub struct FrameScanner {
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
/// Create a scanner with a positive limit on bytes after each RS.
pub fn FrameScanner::new(
  max_record_bytes : Int,
) -> Result[FrameScanner, String] {
  if max_record_bytes <= 0 {
    return Err("max_record_bytes must be positive")
  }
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

///|
/// Number of bytes already consumed from the stream.
pub fn FrameScanner::offset(self : FrameScanner) -> Int {
  self.offset
}

///|
/// Maximum retained bytes in a single frame, including a trailing LF.
pub fn FrameScanner::max_record_bytes(self : FrameScanner) -> Int {
  self.max_record_bytes
}

///|
/// True after `finish` has been called successfully.
pub fn FrameScanner::is_finished(self : FrameScanner) -> Bool {
  self.finished
}

///|
/// Number of bytes currently retained from an unfinished frame.
pub fn FrameScanner::pending_bytes(self : FrameScanner) -> Int {
  self.buffer.length()
}

///|
fn FrameScanner::close_frame(
  self : FrameScanner,
  events : Array[FrameEvent],
) -> Unit {
  if self.overflowed {
    events.push(OversizedFrame(self.start, self.offset))
  } else if !self.buffer.is_empty() {
    events.push(
      DataFrame({
        start: self.start,
        end: self.offset,
        bytes: Bytes::from_array(self.buffer),
      }),
    )
  }
}

///|
fn FrameScanner::open_frame(self : FrameScanner) -> Unit {
  self.in_record = true
  self.buffer = []
  self.overflowed = false
  self.start = self.offset + 1
}

///|
fn FrameScanner::take_byte(self : FrameScanner, byte : Byte) -> Unit {
  if self.overflowed {
    return
  }
  if self.buffer.length() == self.max_record_bytes {
    self.overflowed = true
    self.buffer = []
  } else {
    self.buffer.push(byte)
  }
}

///|
/// Consume arbitrary byte chunks. A frame is emitted on the following RS;
/// call `finish` to receive the last frame in a finite stream.
pub fn FrameScanner::feed(
  self : FrameScanner,
  chunk : Bytes,
) -> Result[Array[FrameEvent], String] {
  if self.finished {
    return Err("scanner already finished")
  }
  let events : Array[FrameEvent] = []
  for i = 0; i < chunk.length(); i = i + 1 {
    let byte = chunk[i]
    if byte == 0x1e {
      if self.in_record {
        self.close_frame(events)
      } else if self.preamble_seen {
        events.push(PreambleBytes(self.preamble_start, self.offset))
      }
      self.open_frame()
    } else if self.in_record {
      self.take_byte(byte)
    } else if !self.preamble_seen {
      self.preamble_start = self.offset
      self.preamble_seen = true
    }
    self.offset = self.offset + 1
  }
  Ok(events)
}

///|
/// Close a finite stream. Repeated calls and subsequent feeds return `Err`.
pub fn FrameScanner::finish(
  self : FrameScanner,
) -> Result[Array[FrameEvent], String] {
  if self.finished {
    return Err("scanner already finished")
  }
  self.finished = true
  let events : Array[FrameEvent] = []
  if self.in_record {
    self.close_frame(events)
  } else if self.preamble_seen {
    events.push(PreambleBytes(self.preamble_start, self.offset))
  }
  Ok(events)
}
