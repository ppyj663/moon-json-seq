///|
/// A nonempty frame's original byte location. `start` is the first byte after
/// RS, and `end` is exclusive. The RS byte is at `start - 1`.
pub(all) struct IndexEntry {
  record_number : Int
  start : Int
  end : Int
  kind : JsonValueKind?
  diagnostic : DiagnosticKind?
  has_final_lf : Bool
}

///|
pub fn IndexEntry::byte_length(self : IndexEntry) -> Int {
  self.end - self.start
}

///|
pub fn IndexEntry::is_valid(self : IndexEntry) -> Bool {
  self.diagnostic is None
}

///|
pub fn IndexEntry::contains(self : IndexEntry, byte_offset : Int) -> Bool {
  byte_offset >= self.start - 1 && byte_offset < self.end
}

///|
/// Extract an indexed frame from the same complete input buffer. The returned
/// slice includes RS. This checks the bounds and separator before copying.
pub fn IndexEntry::extract(
  self : IndexEntry,
  source : Bytes,
) -> Result[Bytes, String] {
  if self.start <= 0 || self.end < self.start || self.end > source.length() {
    return Err("index span is outside source bytes")
  }
  if source[self.start - 1] != 0x1e {
    return Err("indexed record separator is missing")
  }
  let out : Array[Byte] = []
  for i = self.start - 1; i < self.end; i = i + 1 {
    out.push(source[i])
  }
  Ok(Bytes::from_array(out))
}

///|
pub(all) struct IndexBatch {
  entries : Array[IndexEntry]
  preamble_spans : Array[(Int, Int)]
}

///|
pub(all) struct IndexSummary {
  input_bytes : Int
  records : Int
  valid : Int
  invalid : Int
  preamble_regions : Int
  indexed_bytes : Int
}

///|
/// An in-memory positional index. It retains one entry per nonempty frame;
/// callers building an index of very large streams must budget for that.
pub struct SequenceIndex {
  scanner : FrameScanner
  entries : Array[IndexEntry]
  mut valid : Int
  mut invalid : Int
  mut preamble_regions : Int
  mut indexed_bytes : Int
}

///|
pub fn SequenceIndex::new(
  max_record_bytes : Int,
) -> Result[SequenceIndex, String] {
  match FrameScanner::new(max_record_bytes) {
    Ok(scanner) =>
      Ok({
        scanner,
        entries: [],
        valid: 0,
        invalid: 0,
        preamble_regions: 0,
        indexed_bytes: 0,
      })
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceIndex::summary(self : SequenceIndex) -> IndexSummary {
  {
    input_bytes: self.scanner.offset(),
    records: self.entries.length(),
    valid: self.valid,
    invalid: self.invalid,
    preamble_regions: self.preamble_regions,
    indexed_bytes: self.indexed_bytes,
  }
}

///|
pub fn SequenceIndex::length(self : SequenceIndex) -> Int {
  self.entries.length()
}

///|
/// Record numbers start at one. A missing number returns `None`.
pub fn SequenceIndex::record(self : SequenceIndex, number : Int) -> IndexEntry? {
  if number <= 0 {
    None
  } else {
    self.entries.get(number - 1)
  }
}

///|
/// Find the frame containing an absolute byte offset, including its RS byte.
/// Offsets in the preamble or between records have no match.
pub fn SequenceIndex::at_byte(
  self : SequenceIndex,
  byte_offset : Int,
) -> IndexEntry? {
  if byte_offset < 0 {
    return None
  }
  let mut low = 0
  let mut high = self.entries.length()
  while low < high {
    let middle = low + (high - low) / 2
    if self.entries[middle].start - 1 <= byte_offset {
      low = middle + 1
    } else {
      high = middle
    }
  }
  if low == 0 {
    return None
  }
  let candidate = self.entries[low - 1]
  if candidate.contains(byte_offset) {
    Some(candidate)
  } else {
    None
  }
}

///|
/// Return copies of entries whose original frames intersect a byte range.
pub fn SequenceIndex::intersecting(
  self : SequenceIndex,
  start : Int,
  end : Int,
) -> Array[IndexEntry] {
  let matches : Array[IndexEntry] = []
  if start < 0 || end <= start {
    return matches
  }
  for entry in self.entries {
    if entry.start - 1 < end && entry.end > start {
      matches.push(entry)
    }
    if entry.start - 1 >= end {
      break
    }
  }
  matches
}

///|
/// Snapshot the entries in record order. The returned array can be retained
/// while further chunks are indexed.
pub fn SequenceIndex::entries(self : SequenceIndex) -> Array[IndexEntry] {
  let copy : Array[IndexEntry] = []
  for entry in self.entries {
    copy.push(entry)
  }
  copy
}

///|
fn SequenceIndex::consume(
  self : SequenceIndex,
  events : Array[FrameEvent],
) -> IndexBatch {
  let entries : Array[IndexEntry] = []
  let preamble_spans : Array[(Int, Int)] = []
  for event in events {
    match event {
      DataFrame(frame) => {
        let inspection = inspect_frame(frame)
        let entry = {
          record_number: self.entries.length() + 1,
          start: frame.start,
          end: frame.end,
          kind: inspection.json_kind(),
          diagnostic: inspection.diagnostic(),
          has_final_lf: inspection.has_final_lf,
        }
        self.entries.push(entry)
        entries.push(entry)
        self.indexed_bytes = self.indexed_bytes + frame.bytes.length() + 1
        if entry.is_valid() {
          self.valid = self.valid + 1
        } else {
          self.invalid = self.invalid + 1
        }
      }
      OversizedFrame(start, end) => {
        let entry = {
          record_number: self.entries.length() + 1,
          start,
          end,
          kind: None,
          diagnostic: Some(RecordTooLarge),
          has_final_lf: false,
        }
        self.entries.push(entry)
        entries.push(entry)
        self.invalid = self.invalid + 1
        self.indexed_bytes = self.indexed_bytes + end - start + 1
      }
      PreambleBytes(start, end) => {
        self.preamble_regions = self.preamble_regions + 1
        preamble_spans.push((start, end))
      }
    }
  }
  { entries, preamble_spans, }
}

///|
pub fn SequenceIndex::feed(
  self : SequenceIndex,
  chunk : Bytes,
) -> Result[IndexBatch, String] {
  match self.scanner.feed(chunk) {
    Ok(events) => Ok(self.consume(events))
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceIndex::finish(
  self : SequenceIndex,
) -> Result[IndexBatch, String] {
  match self.scanner.finish() {
    Ok(events) => Ok(self.consume(events))
    Err(message) => Err(message)
  }
}
