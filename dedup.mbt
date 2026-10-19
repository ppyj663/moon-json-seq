///|
/// Adjacent mode stores one prior value; global mode stores every distinct
/// serialized value and therefore grows with input diversity.
pub enum DedupMode {
  AdjacentValues
  GlobalValues
}

///|
pub fn DedupMode::adjacent() -> DedupMode {
  AdjacentValues
}

///|
pub fn DedupMode::global() -> DedupMode {
  GlobalValues
}

///|
pub(all) struct DuplicateRecord {
  record_number : Int
  start : Int
  end : Int
  first_record_number : Int
}

///|
pub(all) struct DedupBatch {
  records : Array[Bytes]
  duplicates : Array[DuplicateRecord]
  issues : Array[ValidationIssue]
}

///|
pub(all) struct DedupSummary {
  input_bytes : Int
  frames_seen : Int
  kept : Int
  duplicates : Int
  invalid : Int
  unique_keys : Int
  output_bytes : Int
}

///|
/// Deduplicate valid JSON values in a sequence. Equality is based on the
/// MoonBit JSON serializer's compact text, so object key order may matter.
pub struct SequenceDeduplicator {
  scanner : FrameScanner
  mode : DedupMode
  seen : Map[String, Int]
  mut previous : String?
  mut previous_number : Int
  mut frames_seen : Int
  mut kept : Int
  mut duplicates : Int
  mut invalid : Int
  mut output_bytes : Int
}

///|
pub fn SequenceDeduplicator::new(
  max_record_bytes : Int,
  mode : DedupMode,
) -> Result[SequenceDeduplicator, String] {
  match FrameScanner::new(max_record_bytes) {
    Ok(scanner) =>
      Ok({
        scanner,
        mode,
        seen: Map([]),
        previous: None,
        previous_number: 0,
        frames_seen: 0,
        kept: 0,
        duplicates: 0,
        invalid: 0,
        output_bytes: 0,
      })
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceDeduplicator::summary(
  self : SequenceDeduplicator,
) -> DedupSummary {
  {
    input_bytes: self.scanner.offset(),
    frames_seen: self.frames_seen,
    kept: self.kept,
    duplicates: self.duplicates,
    invalid: self.invalid,
    unique_keys: match self.mode {
      AdjacentValues => if self.previous is Some(_) { 1 } else { 0 }
      GlobalValues => self.seen.length()
    },
    output_bytes: self.output_bytes,
  }
}

///|
fn SequenceDeduplicator::first_occurrence(
  self : SequenceDeduplicator,
  key : String,
) -> Int? {
  match self.mode {
    AdjacentValues =>
      if self.previous == Some(key) {
        Some(self.previous_number)
      } else {
        None
      }
    GlobalValues => self.seen.get(key)
  }
}

///|
fn SequenceDeduplicator::remember(
  self : SequenceDeduplicator,
  key : String,
) -> Unit {
  match self.mode {
    AdjacentValues => {
      self.previous = Some(key)
      self.previous_number = self.frames_seen
    }
    GlobalValues => self.seen.set(key, self.frames_seen)
  }
}

///|
fn SequenceDeduplicator::accept_value(
  self : SequenceDeduplicator,
  value : Json,
  frame : FrameRecord,
  records : Array[Bytes],
  duplicates : Array[DuplicateRecord],
) -> Unit {
  let key = value.stringify()
  match self.first_occurrence(key) {
    Some(first_record_number) => {
      self.duplicates = self.duplicates + 1
      duplicates.push({
        record_number: self.frames_seen,
        start: frame.start,
        end: frame.end,
        first_record_number,
      })
    }
    None => {
      self.remember(key)
      let bytes = encode(value)
      records.push(bytes)
      self.kept = self.kept + 1
      self.output_bytes = self.output_bytes + bytes.length()
    }
  }
}

///|
fn SequenceDeduplicator::consume(
  self : SequenceDeduplicator,
  raw : Array[FrameEvent],
) -> DedupBatch {
  let records : Array[Bytes] = []
  let duplicates : Array[DuplicateRecord] = []
  let issues : Array[ValidationIssue] = []
  for event in raw {
    match event {
      DataFrame(frame) => {
        self.frames_seen = self.frames_seen + 1
        match inspect_frame(frame).outcome {
          Ok(value) => self.accept_value(value, frame, records, duplicates)
          Err(kind) => {
            self.invalid = self.invalid + 1
            issues.push({
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
        self.invalid = self.invalid + 1
        issues.push({
          kind: RecordTooLarge,
          start,
          end,
          record_number: self.frames_seen,
        })
      }
      PreambleBytes(start, end) =>
        issues.push({ kind: BytesBeforeFirstRs, start, end, record_number: 0, })
    }
  }
  { records, duplicates, issues, }
}

///|
pub fn SequenceDeduplicator::feed(
  self : SequenceDeduplicator,
  chunk : Bytes,
) -> Result[DedupBatch, String] {
  match self.scanner.feed(chunk) {
    Ok(raw) => Ok(self.consume(raw))
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceDeduplicator::finish(
  self : SequenceDeduplicator,
) -> Result[DedupBatch, String] {
  match self.scanner.finish() {
    Ok(raw) => Ok(self.consume(raw))
    Err(message) => Err(message)
  }
}
