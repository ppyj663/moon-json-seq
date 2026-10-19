///|
/// RFC 7464 record separator and media type.
pub let media_type : String = "application/json-seq"

///|
/// A typed recoverable record diagnostic.
pub enum DiagnosticKind {
  BytesBeforeFirstRs
  InvalidUtf8
  InvalidJson
  TruncatedScalar
  RecordTooLarge
}

///|
pub fn DiagnosticKind::message(self : DiagnosticKind) -> String {
  match self {
    BytesBeforeFirstRs => "bytes before first RS"
    InvalidUtf8 => "invalid UTF-8"
    InvalidJson => "invalid JSON"
    TruncatedScalar => "top-level scalar lacks trailing whitespace"
    RecordTooLarge => "record exceeds max_record_bytes"
  }
}

///|
/// A decoded JSON value or a recoverable record error. Offsets are absolute
/// byte positions: for values and record errors, the first byte after RS.
pub enum Event {
  Value(Json, Int)
  Error(DiagnosticKind, Int)
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
  scanner : FrameScanner
}

///|
/// A positive limit is required. The recommended starting value is 1 MiB.
pub fn Decoder::new(max_record_bytes : Int) -> Result[Decoder, String] {
  match FrameScanner::new(max_record_bytes) {
    Ok(scanner) => Ok({ scanner, })
    Err(message) => Err(message)
  }
}

///|
fn is_json_space(byte : Byte) -> Bool {
  byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d
}

///|
fn decode_frame(frame : FrameRecord, events : Array[Event]) -> Unit {
  match inspect_frame(frame).outcome {
    Ok(value) => events.push(Value(value, frame.start))
    Err(kind) => events.push(Error(kind, frame.start))
  }
}

///|
fn convert_frame_events(raw : Array[FrameEvent]) -> Array[Event] {
  let events : Array[Event] = []
  for event in raw {
    match event {
      DataFrame(frame) => decode_frame(frame, events)
      PreambleBytes(start, _) => events.push(Error(BytesBeforeFirstRs, start))
      OversizedFrame(start, _) => events.push(Error(RecordTooLarge, start))
    }
  }
  events
}

///|
/// Consume a byte chunk and return all records closed by RS in this chunk.
/// Call finish to close the final record.
pub fn Decoder::feed(
  self : Decoder,
  chunk : Bytes,
) -> Result[Array[Event], String] {
  match self.scanner.feed(chunk) {
    Ok(raw) => Ok(convert_frame_events(raw))
    Err(message) => Err(message)
  }
}

///|
/// Close the final record. Repeated calls return an error.
pub fn Decoder::finish(self : Decoder) -> Result[Array[Event], String] {
  match self.scanner.finish() {
    Ok(raw) => Ok(convert_frame_events(raw))
    Err(message) => Err(message)
  }
}
