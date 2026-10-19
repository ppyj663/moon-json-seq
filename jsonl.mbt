///|
/// JSON Lines input errors. Blank lines are invalid JSON Lines records.
pub enum JsonLineErrorKind {
  BlankLine
  InvalidLineUtf8
  InvalidLineJson
  LineTooLarge
}

///|
pub fn JsonLineErrorKind::message(self : JsonLineErrorKind) -> String {
  match self {
    BlankLine => "blank JSON Lines record"
    InvalidLineUtf8 => "invalid UTF-8 in JSON Lines record"
    InvalidLineJson => "invalid JSON Lines record"
    LineTooLarge => "JSON Lines record exceeds max_line_bytes"
  }
}

///|
pub(all) struct JsonLineIssue {
  kind : JsonLineErrorKind
  start : Int
  end : Int
  line_number : Int
}

///|
/// Converted records are complete RFC 7464 frames in input order.
pub(all) struct JsonLinesBatch {
  records : Array[Bytes]
  issues : Array[JsonLineIssue]
}

///|
pub(all) struct JsonLinesSummary {
  input_bytes : Int
  lines_seen : Int
  records_written : Int
  lines_rejected : Int
  output_bytes : Int
}

///|
/// Convert LF or CRLF-delimited JSON Lines to canonical JSON Text Sequence.
/// Valid final lines without a newline are accepted on finish.
pub struct JsonLinesToSequence {
  max_line_bytes : Int
  mut line : Array[Byte]
  mut line_overflow : Bool
  mut line_start : Int
  mut offset : Int
  mut lines_seen : Int
  mut records_written : Int
  mut lines_rejected : Int
  mut output_bytes : Int
  mut finished : Bool
}

///|
pub fn JsonLinesToSequence::new(
  max_line_bytes : Int,
) -> Result[JsonLinesToSequence, String] {
  if max_line_bytes <= 0 {
    return Err("max_line_bytes must be positive")
  }
  Ok({
    max_line_bytes,
    line: [],
    line_overflow: false,
    line_start: 0,
    offset: 0,
    lines_seen: 0,
    records_written: 0,
    lines_rejected: 0,
    output_bytes: 0,
    finished: false,
  })
}

///|
pub fn JsonLinesToSequence::summary(
  self : JsonLinesToSequence,
) -> JsonLinesSummary {
  {
    input_bytes: self.offset,
    lines_seen: self.lines_seen,
    records_written: self.records_written,
    lines_rejected: self.lines_rejected,
    output_bytes: self.output_bytes,
  }
}

///|
pub fn JsonLinesToSequence::pending_bytes(self : JsonLinesToSequence) -> Int {
  self.line.length()
}

///|
fn JsonLinesToSequence::reject(
  self : JsonLinesToSequence,
  kind : JsonLineErrorKind,
  end : Int,
  issues : Array[JsonLineIssue],
) -> Unit {
  self.lines_rejected = self.lines_rejected + 1
  issues.push({
    kind,
    start: self.line_start,
    end,
    line_number: self.lines_seen,
  })
}

///|
fn JsonLinesToSequence::close_line(
  self : JsonLinesToSequence,
  end : Int,
  records : Array[Bytes],
  issues : Array[JsonLineIssue],
) -> Unit {
  self.lines_seen = self.lines_seen + 1
  if self.line_overflow {
    self.reject(LineTooLarge, end, issues)
  } else {
    let mut body_length = self.line.length()
    if body_length > 0 && self.line[body_length - 1] == 0x0d {
      body_length = body_length - 1
    }
    let body : Array[Byte] = []
    for i = 0; i < body_length; i = i + 1 {
      body.push(self.line[i])
    }
    let bytes = Bytes::from_array(body)
    let text = @utf8.decode(bytes) catch {
      _ => {
        self.reject(InvalidLineUtf8, end, issues)
        self.line = []
        self.line_overflow = false
        self.line_start = end
        return
      }
    }
    if text.trim().is_empty() {
      self.reject(BlankLine, end, issues)
    } else {
      let value = @json.parse(text) catch {
        _ => {
          self.reject(InvalidLineJson, end, issues)
          self.line = []
          self.line_overflow = false
          self.line_start = end
          return
        }
      }
      let record = encode(value)
      records.push(record)
      self.records_written = self.records_written + 1
      self.output_bytes = self.output_bytes + record.length()
    }
  }
  self.line = []
  self.line_overflow = false
  self.line_start = end
}

///|
pub fn JsonLinesToSequence::feed(
  self : JsonLinesToSequence,
  chunk : Bytes,
) -> Result[JsonLinesBatch, String] {
  if self.finished {
    return Err("converter already finished")
  }
  let records : Array[Bytes] = []
  let issues : Array[JsonLineIssue] = []
  for i = 0; i < chunk.length(); i = i + 1 {
    let byte = chunk[i]
    self.offset = self.offset + 1
    if byte == 0x0a {
      self.close_line(self.offset, records, issues)
    } else if !self.line_overflow {
      if self.line.length() == self.max_line_bytes {
        self.line_overflow = true
        self.line = []
      } else {
        self.line.push(byte)
      }
    }
  }
  Ok({ records, issues, })
}

///|
pub fn JsonLinesToSequence::finish(
  self : JsonLinesToSequence,
) -> Result[JsonLinesBatch, String] {
  if self.finished {
    return Err("converter already finished")
  }
  self.finished = true
  let records : Array[Bytes] = []
  let issues : Array[JsonLineIssue] = []
  if !self.line.is_empty() || self.line_overflow {
    self.close_line(self.offset, records, issues)
  }
  Ok({ records, issues, })
}

///|
pub(all) struct SequenceLinesBatch {
  lines : Array[Bytes]
  dropped : Array[RepairDrop]
}

///|
pub(all) struct SequenceLinesSummary {
  input_bytes : Int
  frames_seen : Int
  lines_written : Int
  frames_dropped : Int
  output_bytes : Int
}

///|
/// Convert valid RFC 7464 frames to compact JSON Lines. Invalid frames and
/// preamble bytes are reported and omitted, and output contains one LF per
/// value. It therefore loses the original JSON formatting.
pub struct SequenceToJsonLines {
  scanner : FrameScanner
  mut frames_seen : Int
  mut lines_written : Int
  mut frames_dropped : Int
  mut output_bytes : Int
}

///|
pub fn SequenceToJsonLines::new(
  max_record_bytes : Int,
) -> Result[SequenceToJsonLines, String] {
  match FrameScanner::new(max_record_bytes) {
    Ok(scanner) =>
      Ok({
        scanner,
        frames_seen: 0,
        lines_written: 0,
        frames_dropped: 0,
        output_bytes: 0,
      })
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceToJsonLines::summary(
  self : SequenceToJsonLines,
) -> SequenceLinesSummary {
  {
    input_bytes: self.scanner.offset(),
    frames_seen: self.frames_seen,
    lines_written: self.lines_written,
    frames_dropped: self.frames_dropped,
    output_bytes: self.output_bytes,
  }
}

///|
fn SequenceToJsonLines::consume(
  self : SequenceToJsonLines,
  events : Array[FrameEvent],
) -> SequenceLinesBatch {
  let lines : Array[Bytes] = []
  let dropped : Array[RepairDrop] = []
  for event in events {
    match event {
      DataFrame(frame) => {
        self.frames_seen = self.frames_seen + 1
        match inspect_frame(frame).outcome {
          Ok(value) => {
            let record = encode(value)
            let line : Array[Byte] = []
            for i = 1; i < record.length(); i = i + 1 {
              line.push(record[i])
            }
            let bytes = Bytes::from_array(line)
            lines.push(bytes)
            self.lines_written = self.lines_written + 1
            self.output_bytes = self.output_bytes + bytes.length()
          }
          Err(kind) => {
            self.frames_dropped = self.frames_dropped + 1
            dropped.push({
              kind,
              start: frame.start,
              end: frame.end,
              record_number: self.frames_seen,
            })
          }
        }
      }
      OversizedFrame(start, end) => {
        self.frames_seen = self.frames_seen + 1
        self.frames_dropped = self.frames_dropped + 1
        dropped.push({
          kind: RecordTooLarge,
          start,
          end,
          record_number: self.frames_seen,
        })
      }
      PreambleBytes(start, end) =>
        dropped.push({ kind: BytesBeforeFirstRs, start, end, record_number: 0, })
    }
  }
  { lines, dropped, }
}

///|
pub fn SequenceToJsonLines::feed(
  self : SequenceToJsonLines,
  chunk : Bytes,
) -> Result[SequenceLinesBatch, String] {
  match self.scanner.feed(chunk) {
    Ok(events) => Ok(self.consume(events))
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceToJsonLines::finish(
  self : SequenceToJsonLines,
) -> Result[SequenceLinesBatch, String] {
  match self.scanner.finish() {
    Ok(events) => Ok(self.consume(events))
    Err(message) => Err(message)
  }
}
