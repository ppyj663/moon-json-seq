///|
/// Preserve original valid frames, or rewrite them in canonical compact form.
pub(all) enum RepairMode {
  PreserveValid
  CanonicalizeValid
}

///|
pub fn RepairMode::preserve() -> RepairMode {
  PreserveValid
}

///|
pub fn RepairMode::canonicalize() -> RepairMode {
  CanonicalizeValid
}

///|
/// A notice for input that cannot be included in a repaired stream.
pub(all) struct RepairDrop {
  kind : DiagnosticKind
  start : Int
  end : Int
  record_number : Int
}

///|
/// One call's output. Each item in `records` is a complete RFC 7464 record.
pub(all) struct RepairBatch {
  records : Array[Bytes]
  dropped : Array[RepairDrop]
}

///|
pub(all) struct RepairSummary {
  input_bytes : Int
  output_bytes : Int
  frames_seen : Int
  records_written : Int
  records_dropped : Int
  preamble_bytes_dropped : Int
}

///|
/// Resynchronize at record separators, drop malformed frames, and emit valid
/// frames. Each call returns its output, so the repairer does not retain it.
pub struct SequenceRepairer {
  scanner : FrameScanner
  mode : RepairMode
  mut frames_seen : Int
  mut records_written : Int
  mut records_dropped : Int
  mut preamble_bytes_dropped : Int
  mut output_bytes : Int
}

///|
pub fn SequenceRepairer::new(
  max_record_bytes : Int,
  mode : RepairMode,
) -> Result[SequenceRepairer, String] {
  match FrameScanner::new(max_record_bytes) {
    Ok(scanner) =>
      Ok({
        scanner,
        mode,
        frames_seen: 0,
        records_written: 0,
        records_dropped: 0,
        preamble_bytes_dropped: 0,
        output_bytes: 0,
      })
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceRepairer::summary(self : SequenceRepairer) -> RepairSummary {
  {
    input_bytes: self.scanner.offset(),
    output_bytes: self.output_bytes,
    frames_seen: self.frames_seen,
    records_written: self.records_written,
    records_dropped: self.records_dropped,
    preamble_bytes_dropped: self.preamble_bytes_dropped,
  }
}

///|
fn preserve_frame(frame : FrameRecord) -> Bytes {
  let bytes : Array[Byte] = [0x1e]
  for i = 0; i < frame.bytes.length(); i = i + 1 {
    bytes.push(frame.bytes[i])
  }
  Bytes::from_array(bytes)
}

///|
fn SequenceRepairer::consume(
  self : SequenceRepairer,
  events : Array[FrameEvent],
) -> RepairBatch {
  let records : Array[Bytes] = []
  let dropped : Array[RepairDrop] = []
  for event in events {
    match event {
      DataFrame(frame) => {
        self.frames_seen = self.frames_seen + 1
        match inspect_frame(frame).outcome {
          Ok(value) => {
            let record = match self.mode {
              PreserveValid => preserve_frame(frame)
              CanonicalizeValid => encode(value)
            }
            records.push(record)
            self.records_written = self.records_written + 1
            self.output_bytes = self.output_bytes + record.length()
          }
          Err(kind) => {
            self.records_dropped = self.records_dropped + 1
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
        self.records_dropped = self.records_dropped + 1
        dropped.push({
          kind: RecordTooLarge,
          start,
          end,
          record_number: self.frames_seen,
        })
      }
      PreambleBytes(start, end) => {
        self.preamble_bytes_dropped = self.preamble_bytes_dropped + end - start
        dropped.push({ kind: BytesBeforeFirstRs, start, end, record_number: 0, })
      }
    }
  }
  { records, dropped, }
}

///|
pub fn SequenceRepairer::feed(
  self : SequenceRepairer,
  chunk : Bytes,
) -> Result[RepairBatch, String] {
  match self.scanner.feed(chunk) {
    Ok(events) => Ok(self.consume(events))
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceRepairer::finish(
  self : SequenceRepairer,
) -> Result[RepairBatch, String] {
  match self.scanner.finish() {
    Ok(events) => Ok(self.consume(events))
    Err(message) => Err(message)
  }
}
