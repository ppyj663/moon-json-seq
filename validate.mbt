///|
/// One validation failure with its byte span and record ordinal. Ordinals
/// count nonempty frames and start at one; bytes before the first RS use zero.
pub(all) struct ValidationIssue {
  kind : DiagnosticKind
  start : Int
  end : Int
  record_number : Int
}

///|
pub fn ValidationIssue::message(self : ValidationIssue) -> String {
  self.kind.message()
}

///|
/// Events returned for every completed frame or malformed input region.
pub enum ValidationNotice {
  ValidRecord(RecordInspection)
  BadRecord(ValidationIssue)
}

///|
/// A summary of an incrementally validated sequence. Values are snapshots,
/// so callers may retain them while feeding additional chunks.
pub struct ValidationSummary {
  mut total_bytes : Int
  mut frames : Int
  mut valid_records : Int
  mut invalid_records : Int
  mut preamble_regions : Int
  mut preamble_bytes : Int
  mut oversized_records : Int
  mut invalid_utf8 : Int
  mut invalid_json : Int
  mut truncated_scalars : Int
  mut objects : Int
  mut arrays : Int
  mut strings : Int
  mut numbers : Int
  mut booleans : Int
  mut nulls : Int
  mut json_body_bytes : Int
  mut line_breaks : Int
  mut largest_frame_bytes : Int
  mut issues_seen : Int
  mut issues_retained : Int
}

///|
fn empty_validation_summary() -> ValidationSummary {
  {
    total_bytes: 0,
    frames: 0,
    valid_records: 0,
    invalid_records: 0,
    preamble_regions: 0,
    preamble_bytes: 0,
    oversized_records: 0,
    invalid_utf8: 0,
    invalid_json: 0,
    truncated_scalars: 0,
    objects: 0,
    arrays: 0,
    strings: 0,
    numbers: 0,
    booleans: 0,
    nulls: 0,
    json_body_bytes: 0,
    line_breaks: 0,
    largest_frame_bytes: 0,
    issues_seen: 0,
    issues_retained: 0,
  }
}

///|
pub fn ValidationSummary::total_bytes(self : ValidationSummary) -> Int {
  self.total_bytes
}

///|
pub fn ValidationSummary::frames(self : ValidationSummary) -> Int {
  self.frames
}

///|
pub fn ValidationSummary::valid_records(self : ValidationSummary) -> Int {
  self.valid_records
}

///|
pub fn ValidationSummary::invalid_records(self : ValidationSummary) -> Int {
  self.invalid_records
}

///|
pub fn ValidationSummary::preamble_regions(self : ValidationSummary) -> Int {
  self.preamble_regions
}

///|
pub fn ValidationSummary::preamble_bytes(self : ValidationSummary) -> Int {
  self.preamble_bytes
}

///|
pub fn ValidationSummary::oversized_records(self : ValidationSummary) -> Int {
  self.oversized_records
}

///|
pub fn ValidationSummary::invalid_utf8(self : ValidationSummary) -> Int {
  self.invalid_utf8
}

///|
pub fn ValidationSummary::invalid_json(self : ValidationSummary) -> Int {
  self.invalid_json
}

///|
pub fn ValidationSummary::truncated_scalars(self : ValidationSummary) -> Int {
  self.truncated_scalars
}

///|
pub fn ValidationSummary::objects(self : ValidationSummary) -> Int {
  self.objects
}

///|
pub fn ValidationSummary::arrays(self : ValidationSummary) -> Int {
  self.arrays
}

///|
pub fn ValidationSummary::strings(self : ValidationSummary) -> Int {
  self.strings
}

///|
pub fn ValidationSummary::numbers(self : ValidationSummary) -> Int {
  self.numbers
}

///|
pub fn ValidationSummary::booleans(self : ValidationSummary) -> Int {
  self.booleans
}

///|
pub fn ValidationSummary::nulls(self : ValidationSummary) -> Int {
  self.nulls
}

///|
pub fn ValidationSummary::json_body_bytes(self : ValidationSummary) -> Int {
  self.json_body_bytes
}

///|
pub fn ValidationSummary::line_breaks(self : ValidationSummary) -> Int {
  self.line_breaks
}

///|
pub fn ValidationSummary::largest_frame_bytes(self : ValidationSummary) -> Int {
  self.largest_frame_bytes
}

///|
pub fn ValidationSummary::issues_seen(self : ValidationSummary) -> Int {
  self.issues_seen
}

///|
pub fn ValidationSummary::issues_retained(self : ValidationSummary) -> Int {
  self.issues_retained
}

///|
pub fn ValidationSummary::is_clean(self : ValidationSummary) -> Bool {
  self.issues_seen == 0
}

///|
/// Validate a stream while retaining at most `issue_limit` representative
/// issues. `feed` still returns all notices for that call.
pub struct SequenceValidator {
  scanner : FrameScanner
  issue_limit : Int
  issues : Array[ValidationIssue]
  summary : ValidationSummary
}

///|
pub fn SequenceValidator::new(
  max_record_bytes : Int,
  issue_limit : Int,
) -> Result[SequenceValidator, String] {
  if issue_limit < 0 {
    return Err("issue_limit must be nonnegative")
  }
  match FrameScanner::new(max_record_bytes) {
    Ok(scanner) =>
      Ok({
        scanner,
        issue_limit,
        issues: [],
        summary: empty_validation_summary(),
      })
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceValidator::summary(
  self : SequenceValidator,
) -> ValidationSummary {
  let current = self.summary
  {
    total_bytes: current.total_bytes,
    frames: current.frames,
    valid_records: current.valid_records,
    invalid_records: current.invalid_records,
    preamble_regions: current.preamble_regions,
    preamble_bytes: current.preamble_bytes,
    oversized_records: current.oversized_records,
    invalid_utf8: current.invalid_utf8,
    invalid_json: current.invalid_json,
    truncated_scalars: current.truncated_scalars,
    objects: current.objects,
    arrays: current.arrays,
    strings: current.strings,
    numbers: current.numbers,
    booleans: current.booleans,
    nulls: current.nulls,
    json_body_bytes: current.json_body_bytes,
    line_breaks: current.line_breaks,
    largest_frame_bytes: current.largest_frame_bytes,
    issues_seen: current.issues_seen,
    issues_retained: current.issues_retained,
  }
}

///|
pub fn SequenceValidator::issues(
  self : SequenceValidator,
) -> Array[ValidationIssue] {
  let copy : Array[ValidationIssue] = []
  for issue in self.issues {
    copy.push(issue)
  }
  copy
}

///|
fn SequenceValidator::add_issue(
  self : SequenceValidator,
  issue : ValidationIssue,
  notices : Array[ValidationNotice],
) -> Unit {
  self.summary.issues_seen = self.summary.issues_seen + 1
  if self.issues.length() < self.issue_limit {
    self.issues.push(issue)
    self.summary.issues_retained = self.summary.issues_retained + 1
  }
  notices.push(BadRecord(issue))
}

///|
fn SequenceValidator::count_kind(
  self : SequenceValidator,
  kind : JsonValueKind,
) -> Unit {
  match kind {
    NullValue => self.summary.nulls = self.summary.nulls + 1
    BooleanValue => self.summary.booleans = self.summary.booleans + 1
    NumberValue => self.summary.numbers = self.summary.numbers + 1
    StringValue => self.summary.strings = self.summary.strings + 1
    ArrayValue => self.summary.arrays = self.summary.arrays + 1
    ObjectValue => self.summary.objects = self.summary.objects + 1
  }
}

///|
fn SequenceValidator::count_diagnostic(
  self : SequenceValidator,
  kind : DiagnosticKind,
) -> Unit {
  match kind {
    BytesBeforeFirstRs =>
      self.summary.preamble_regions = self.summary.preamble_regions + 1
    InvalidUtf8 => self.summary.invalid_utf8 = self.summary.invalid_utf8 + 1
    InvalidJson => self.summary.invalid_json = self.summary.invalid_json + 1
    TruncatedScalar =>
      self.summary.truncated_scalars = self.summary.truncated_scalars + 1
    RecordTooLarge =>
      self.summary.oversized_records = self.summary.oversized_records + 1
  }
}

///|
fn SequenceValidator::count_frame(self : SequenceValidator, size : Int) -> Unit {
  self.summary.frames = self.summary.frames + 1
  if size > self.summary.largest_frame_bytes {
    self.summary.largest_frame_bytes = size
  }
}

///|
fn SequenceValidator::consume_raw(
  self : SequenceValidator,
  raw : Array[FrameEvent],
) -> Array[ValidationNotice] {
  let notices : Array[ValidationNotice] = []
  for event in raw {
    match event {
      DataFrame(frame) => {
        self.count_frame(frame.bytes.length())
        self.summary.json_body_bytes = self.summary.json_body_bytes +
          frame.bytes.length()
        let inspection = inspect_frame(frame)
        self.summary.line_breaks = self.summary.line_breaks +
          inspection.line_breaks
        match inspection.outcome {
          Ok(_) => {
            self.summary.valid_records = self.summary.valid_records + 1
            match inspection.json_kind() {
              Some(kind) => self.count_kind(kind)
              None => ()
            }
            notices.push(ValidRecord(inspection))
          }
          Err(kind) => {
            self.summary.invalid_records = self.summary.invalid_records + 1
            self.count_diagnostic(kind)
            self.add_issue(
              {
                kind,
                start: frame.start,
                end: frame.end,
                record_number: self.summary.frames,
              },
              notices,
            )
          }
        }
      }
      OversizedFrame(start, end) => {
        self.count_frame(end - start)
        self.summary.invalid_records = self.summary.invalid_records + 1
        self.count_diagnostic(RecordTooLarge)
        self.add_issue(
          {
            kind: RecordTooLarge,
            start,
            end,
            record_number: self.summary.frames,
          },
          notices,
        )
      }
      PreambleBytes(start, end) => {
        self.summary.preamble_bytes = self.summary.preamble_bytes + end - start
        self.count_diagnostic(BytesBeforeFirstRs)
        self.add_issue(
          { kind: BytesBeforeFirstRs, start, end, record_number: 0, },
          notices,
        )
      }
    }
  }
  self.summary.total_bytes = self.scanner.offset()
  notices
}

///|
pub fn SequenceValidator::feed(
  self : SequenceValidator,
  chunk : Bytes,
) -> Result[Array[ValidationNotice], String] {
  match self.scanner.feed(chunk) {
    Ok(raw) => {
      self.summary.total_bytes = self.scanner.offset()
      Ok(self.consume_raw(raw))
    }
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceValidator::finish(
  self : SequenceValidator,
) -> Result[Array[ValidationNotice], String] {
  match self.scanner.finish() {
    Ok(raw) => Ok(self.consume_raw(raw))
    Err(message) => Err(message)
  }
}
