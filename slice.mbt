///|
/// A half-open range of nonempty frame ordinals, starting at one.
pub(all) struct RecordRange {
  start : Int
  end : Int
}

///|
pub fn RecordRange::new(start : Int, end : Int) -> Result[RecordRange, String] {
  if start <= 0 || end <= start {
    Err("record range must have 1 <= start < end")
  } else {
    Ok({ start, end, })
  }
}

///|
pub fn RecordRange::contains(self : RecordRange, record_number : Int) -> Bool {
  record_number >= self.start && record_number < self.end
}

///|
pub fn RecordRange::length(self : RecordRange) -> Int {
  self.end - self.start
}

///|
pub fn RecordRange::overlaps(self : RecordRange, other : RecordRange) -> Bool {
  self.start < other.end && other.start < self.end
}

///|
pub fn RecordRange::is_before(self : RecordRange, other : RecordRange) -> Bool {
  self.end <= other.start
}

///|
/// Merge overlapping or adjacent ranges; disjoint ranges stay separate.
pub fn RecordRange::merge_touching(
  self : RecordRange,
  other : RecordRange,
) -> RecordRange? {
  if self.end < other.start || other.end < self.start {
    return None
  }
  let start = if self.start < other.start { self.start } else { other.start }
  let end = if self.end > other.end { self.end } else { other.end }
  Some({ start, end, })
}

///|
/// Find the shared ordinals of two ranges, if any.
pub fn RecordRange::intersection(
  self : RecordRange,
  other : RecordRange,
) -> RecordRange? {
  let start = if self.start > other.start { self.start } else { other.start }
  let end = if self.end < other.end { self.end } else { other.end }
  if end <= start {
    None
  } else {
    Some({ start, end, })
  }
}

///|
/// Divide a range into ordered, nonempty ranges of at most max_records.
/// This is useful for assigning record windows to separate workers.
pub fn RecordRange::split(
  self : RecordRange,
  max_records : Int,
) -> Result[Array[RecordRange], String] {
  if max_records <= 0 {
    return Err("max_records must be positive")
  }
  let parts : Array[RecordRange] = []
  let mut next = self.start
  while next < self.end {
    let remaining = self.end - next
    let size = if remaining < max_records { remaining } else { max_records }
    let end = next + size
    parts.push({ start: next, end, })
    next = end
  }
  Ok(parts)
}

///|
pub(all) struct SliceRecord {
  record_number : Int
  source_start : Int
  source_end : Int
  bytes : Bytes
}

///|
pub(all) struct SliceBatch {
  records : Array[SliceRecord]
  issues : Array[ValidationIssue]
}

///|
pub(all) struct SliceSummary {
  input_bytes : Int
  frames_seen : Int
  selected : Int
  outside_range : Int
  invalid_in_range : Int
  output_bytes : Int
}

///|
/// Extract valid frames by their original ordinal. The slicer scans the
/// entire stream to maintain byte and ordinal positions; it validates only
/// frames inside the selected range and reports preamble bytes.
pub struct SequenceSlicer {
  scanner : FrameScanner
  range : RecordRange
  mode : RepairMode
  mut frames_seen : Int
  mut selected : Int
  mut outside_range : Int
  mut invalid_in_range : Int
  mut output_bytes : Int
}

///|
pub fn SequenceSlicer::new(
  max_record_bytes : Int,
  range : RecordRange,
  mode : RepairMode,
) -> Result[SequenceSlicer, String] {
  match FrameScanner::new(max_record_bytes) {
    Ok(scanner) =>
      Ok({
        scanner,
        range,
        mode,
        frames_seen: 0,
        selected: 0,
        outside_range: 0,
        invalid_in_range: 0,
        output_bytes: 0,
      })
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceSlicer::summary(self : SequenceSlicer) -> SliceSummary {
  {
    input_bytes: self.scanner.offset(),
    frames_seen: self.frames_seen,
    selected: self.selected,
    outside_range: self.outside_range,
    invalid_in_range: self.invalid_in_range,
    output_bytes: self.output_bytes,
  }
}

///|
fn SequenceSlicer::accept_frame(
  self : SequenceSlicer,
  frame : FrameRecord,
  records : Array[SliceRecord],
  issues : Array[ValidationIssue],
) -> Unit {
  self.frames_seen = self.frames_seen + 1
  if !self.range.contains(self.frames_seen) {
    self.outside_range = self.outside_range + 1
    return
  }
  match inspect_frame(frame).outcome {
    Ok(value) => {
      let bytes = match self.mode {
        PreserveValid => preserve_frame(frame)
        CanonicalizeValid => encode(value)
      }
      records.push({
        record_number: self.frames_seen,
        source_start: frame.start,
        source_end: frame.end,
        bytes,
      })
      self.selected = self.selected + 1
      self.output_bytes = self.output_bytes + bytes.length()
    }
    Err(kind) => {
      self.invalid_in_range = self.invalid_in_range + 1
      issues.push({
        kind,
        start: frame.start,
        end: frame.end,
        record_number: self.frames_seen,
      })
    }
  }
}

///|
fn SequenceSlicer::consume(
  self : SequenceSlicer,
  raw : Array[FrameEvent],
) -> SliceBatch {
  let records : Array[SliceRecord] = []
  let issues : Array[ValidationIssue] = []
  for event in raw {
    match event {
      DataFrame(frame) => self.accept_frame(frame, records, issues)
      OversizedFrame(start, end) => {
        self.frames_seen = self.frames_seen + 1
        if self.range.contains(self.frames_seen) {
          self.invalid_in_range = self.invalid_in_range + 1
          issues.push({
            kind: RecordTooLarge,
            start,
            end,
            record_number: self.frames_seen,
          })
        } else {
          self.outside_range = self.outside_range + 1
        }
      }
      PreambleBytes(start, end) =>
        issues.push({ kind: BytesBeforeFirstRs, start, end, record_number: 0, })
    }
  }
  { records, issues, }
}

///|
pub fn SequenceSlicer::feed(
  self : SequenceSlicer,
  chunk : Bytes,
) -> Result[SliceBatch, String] {
  match self.scanner.feed(chunk) {
    Ok(raw) => Ok(self.consume(raw))
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceSlicer::finish(
  self : SequenceSlicer,
) -> Result[SliceBatch, String] {
  match self.scanner.finish() {
    Ok(raw) => Ok(self.consume(raw))
    Err(message) => Err(message)
  }
}
