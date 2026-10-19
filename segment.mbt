///|
/// A completed output segment containing whole canonical RFC 7464 records.
pub(all) struct SequenceSegment {
  first_record_number : Int
  last_record_number : Int
  records : Int
  bytes : Bytes
}

///|
pub enum SegmentFailure {
  InvalidFrame(DiagnosticKind)
  RecordExceedsSegment
}

///|
pub fn SegmentFailure::message(self : SegmentFailure) -> String {
  match self {
    InvalidFrame(kind) => kind.message()
    RecordExceedsSegment => "canonical record exceeds max_segment_bytes"
  }
}

///|
pub(all) struct SegmentIssue {
  failure : SegmentFailure
  record_number : Int
  start : Int
  end : Int
}

///|
pub(all) struct SegmentBatch {
  segments : Array[SequenceSegment]
  issues : Array[SegmentIssue]
}

///|
pub(all) struct SegmentSummary {
  input_bytes : Int
  frames_seen : Int
  records_written : Int
  records_dropped : Int
  segments_emitted : Int
  output_bytes : Int
}

///|
/// Split a sequence into bounded byte segments without splitting a record.
/// Invalid records and canonical records larger than the segment limit are
/// diagnosed and omitted. The pending segment is bounded by max_segment_bytes.
pub struct SequenceSegmenter {
  scanner : FrameScanner
  max_segment_bytes : Int
  mut pending : Array[Byte]
  mut first_pending_number : Int
  mut last_pending_number : Int
  mut pending_records : Int
  mut frames_seen : Int
  mut records_written : Int
  mut records_dropped : Int
  mut segments_emitted : Int
  mut output_bytes : Int
}

///|
pub fn SequenceSegmenter::new(
  max_record_bytes : Int,
  max_segment_bytes : Int,
) -> Result[SequenceSegmenter, String] {
  if max_segment_bytes <= 0 {
    return Err("max_segment_bytes must be positive")
  }
  match FrameScanner::new(max_record_bytes) {
    Ok(scanner) =>
      Ok({
        scanner,
        max_segment_bytes,
        pending: [],
        first_pending_number: 0,
        last_pending_number: 0,
        pending_records: 0,
        frames_seen: 0,
        records_written: 0,
        records_dropped: 0,
        segments_emitted: 0,
        output_bytes: 0,
      })
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceSegmenter::summary(self : SequenceSegmenter) -> SegmentSummary {
  {
    input_bytes: self.scanner.offset(),
    frames_seen: self.frames_seen,
    records_written: self.records_written,
    records_dropped: self.records_dropped,
    segments_emitted: self.segments_emitted,
    output_bytes: self.output_bytes,
  }
}

///|
pub fn SequenceSegmenter::pending_bytes(self : SequenceSegmenter) -> Int {
  self.pending.length()
}

///|
fn SequenceSegmenter::emit_pending(
  self : SequenceSegmenter,
  segments : Array[SequenceSegment],
) -> Unit {
  if self.pending_records == 0 {
    return
  }
  segments.push({
    first_record_number: self.first_pending_number,
    last_record_number: self.last_pending_number,
    records: self.pending_records,
    bytes: Bytes::from_array(self.pending),
  })
  self.segments_emitted = self.segments_emitted + 1
  self.pending = []
  self.first_pending_number = 0
  self.last_pending_number = 0
  self.pending_records = 0
}

///|
fn SequenceSegmenter::append_record(
  self : SequenceSegmenter,
  record : Bytes,
  frame : FrameRecord,
  segments : Array[SequenceSegment],
  issues : Array[SegmentIssue],
) -> Unit {
  if record.length() > self.max_segment_bytes {
    self.records_dropped = self.records_dropped + 1
    issues.push({
      failure: RecordExceedsSegment,
      record_number: self.frames_seen,
      start: frame.start,
      end: frame.end,
    })
    return
  }
  if self.pending.length() + record.length() > self.max_segment_bytes {
    self.emit_pending(segments)
  }
  if self.pending_records == 0 {
    self.first_pending_number = self.frames_seen
  }
  self.last_pending_number = self.frames_seen
  self.pending_records = self.pending_records + 1
  for i = 0; i < record.length(); i = i + 1 {
    self.pending.push(record[i])
  }
  self.records_written = self.records_written + 1
  self.output_bytes = self.output_bytes + record.length()
}

///|
fn SequenceSegmenter::consume(
  self : SequenceSegmenter,
  raw : Array[FrameEvent],
) -> SegmentBatch {
  let segments : Array[SequenceSegment] = []
  let issues : Array[SegmentIssue] = []
  for event in raw {
    match event {
      DataFrame(frame) => {
        self.frames_seen = self.frames_seen + 1
        match inspect_frame(frame).outcome {
          Ok(value) =>
            self.append_record(encode(value), frame, segments, issues)
          Err(kind) => {
            self.records_dropped = self.records_dropped + 1
            issues.push({
              failure: InvalidFrame(kind),
              record_number: self.frames_seen,
              start: frame.start,
              end: frame.end,
            })
          }
        }
      }
      OversizedFrame(start, end) => {
        self.frames_seen = self.frames_seen + 1
        self.records_dropped = self.records_dropped + 1
        issues.push({
          failure: InvalidFrame(RecordTooLarge),
          record_number: self.frames_seen,
          start,
          end,
        })
      }
      PreambleBytes(start, end) =>
        issues.push({
          failure: InvalidFrame(BytesBeforeFirstRs),
          record_number: 0,
          start,
          end,
        })
    }
  }
  { segments, issues, }
}

///|
pub fn SequenceSegmenter::feed(
  self : SequenceSegmenter,
  chunk : Bytes,
) -> Result[SegmentBatch, String] {
  match self.scanner.feed(chunk) {
    Ok(raw) => Ok(self.consume(raw))
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceSegmenter::finish(
  self : SequenceSegmenter,
) -> Result[SegmentBatch, String] {
  match self.scanner.finish() {
    Ok(raw) => {
      let batch = self.consume(raw)
      self.emit_pending(batch.segments)
      Ok(batch)
    }
    Err(message) => Err(message)
  }
}
