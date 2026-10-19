///|
/// The JSON kind of a successfully parsed frame.
pub enum JsonValueKind {
  NullValue
  BooleanValue
  NumberValue
  StringValue
  ArrayValue
  ObjectValue
}

///|
pub fn JsonValueKind::label(self : JsonValueKind) -> String {
  match self {
    NullValue => "null"
    BooleanValue => "boolean"
    NumberValue => "number"
    StringValue => "string"
    ArrayValue => "array"
    ObjectValue => "object"
  }
}

///|
/// Metadata and one parse result for an individual bounded frame.
pub(all) struct RecordInspection {
  start : Int
  end : Int
  byte_length : Int
  line_breaks : Int
  leading_whitespace : Int
  trailing_whitespace : Int
  has_final_lf : Bool
  outcome : Result[Json, DiagnosticKind]
}

///|
fn inspection_with_outcome(
  frame : FrameRecord,
  line_breaks : Int,
  leading_whitespace : Int,
  trailing_whitespace : Int,
  outcome : Result[Json, DiagnosticKind],
) -> RecordInspection {
  let length = frame.bytes.length()
  {
    start: frame.start,
    end: frame.end,
    byte_length: length,
    line_breaks,
    leading_whitespace,
    trailing_whitespace,
    has_final_lf: length > 0 && frame.bytes[length - 1] == 0x0a,
    outcome,
  }
}

///|
fn frame_line_breaks(bytes : Bytes) -> Int {
  let mut count = 0
  for i = 0; i < bytes.length(); i = i + 1 {
    if bytes[i] == 0x0a {
      count = count + 1
    }
  }
  count
}

///|
fn frame_leading_whitespace(bytes : Bytes) -> Int {
  let mut i = 0
  while i < bytes.length() && is_json_space(bytes[i]) {
    i = i + 1
  }
  i
}

///|
fn frame_trailing_whitespace(bytes : Bytes) -> Int {
  let mut i = bytes.length()
  while i > 0 && is_json_space(bytes[i - 1]) {
    i = i - 1
  }
  bytes.length() - i
}

///|
fn frame_may_be_scalar(bytes : Bytes, leading : Int) -> Bool {
  if leading >= bytes.length() {
    return false
  }
  let lead = bytes[leading]
  lead == 0x2d ||
  (lead >= 0x30 && lead <= 0x39) ||
  lead == 0x74 ||
  lead == 0x66 ||
  lead == 0x6e
}

///|
/// Inspect a raw frame without changing it. Top-level numbers and the three
/// JSON keywords require trailing JSON whitespace to rule out truncation.
pub fn inspect_frame(frame : FrameRecord) -> RecordInspection {
  let bytes = frame.bytes
  let line_breaks = frame_line_breaks(bytes)
  let leading = frame_leading_whitespace(bytes)
  let trailing = frame_trailing_whitespace(bytes)
  let text = @utf8.decode(bytes) catch {
    _ =>
      return inspection_with_outcome(
        frame,
        line_breaks,
        leading,
        trailing,
        Err(InvalidUtf8),
      )
  }
  if frame_may_be_scalar(bytes, leading) && trailing == 0 {
    return inspection_with_outcome(
      frame,
      line_breaks,
      leading,
      trailing,
      Err(TruncatedScalar),
    )
  }
  let value = @json.parse(text) catch {
    _ =>
      return inspection_with_outcome(
        frame,
        line_breaks,
        leading,
        trailing,
        Err(InvalidJson),
      )
  }
  inspection_with_outcome(frame, line_breaks, leading, trailing, Ok(value))
}

///|
/// Convenience inspection when the caller already knows the body offset.
pub fn inspect_frame_bytes(bytes : Bytes, start : Int) -> RecordInspection {
  inspect_frame({ start, end: start + bytes.length(), bytes, })
}

///|
pub fn RecordInspection::is_valid(self : RecordInspection) -> Bool {
  self.outcome is Ok(_)
}

///|
pub fn RecordInspection::value(self : RecordInspection) -> Json? {
  match self.outcome {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
pub fn RecordInspection::diagnostic(self : RecordInspection) -> DiagnosticKind? {
  match self.outcome {
    Ok(_) => None
    Err(kind) => Some(kind)
  }
}

///|
pub fn RecordInspection::json_kind(self : RecordInspection) -> JsonValueKind? {
  match self.outcome {
    Err(_) => None
    Ok(value) =>
      Some(
        match value {
          Null => NullValue
          True | False => BooleanValue
          Number(_, ..) => NumberValue
          String(_) => StringValue
          Array(_) => ArrayValue
          Object(_) => ObjectValue
        },
      )
  }
}

///|
/// Return a canonical RFC 7464 frame for a valid value. Invalid frames have
/// no canonical encoding and return `None`.
pub fn RecordInspection::canonical_frame(self : RecordInspection) -> Bytes? {
  match self.outcome {
    Ok(value) => Some(encode(value))
    Err(_) => None
  }
}
