///|
/// A sampled record with original ordinal and byte span.
pub(all) struct SampleRecord {
  record_number : Int
  start : Int
  end : Int
  bytes : Bytes
}

///|
pub(all) struct SampleBatch {
  records : Array[SampleRecord]
  issues : Array[ValidationIssue]
}

///|
pub(all) struct SampleSummary {
  input_bytes : Int
  frames_seen : Int
  candidates : Int
  samples_written : Int
  invalid_candidates : Int
  skipped_by_limit : Int
  output_bytes : Int
}

///|
/// Sample records at a fixed stride, beginning with ordinal `phase + 1`.
/// For example, stride 3 and phase 1 examines ordinals 2, 5, 8, ... .
/// Only valid candidate frames count against max_samples. The scanner still
/// consumes the rest of the input and tracks its full byte position.
pub struct SequenceSampler {
  scanner : FrameScanner
  stride : Int
  phase : Int
  max_samples : Int
  mode : RepairMode
  mut frames_seen : Int
  mut candidates : Int
  mut samples_written : Int
  mut invalid_candidates : Int
  mut skipped_by_limit : Int
  mut output_bytes : Int
}

///|
pub fn SequenceSampler::new(
  max_record_bytes : Int,
  stride : Int,
  phase : Int,
  max_samples : Int,
  mode : RepairMode,
) -> Result[SequenceSampler, String] {
  if stride <= 0 {
    return Err("stride must be positive")
  }
  if phase < 0 || phase >= stride {
    return Err("phase must be in [0, stride)")
  }
  if max_samples <= 0 {
    return Err("max_samples must be positive")
  }
  match FrameScanner::new(max_record_bytes) {
    Ok(scanner) =>
      Ok({
        scanner,
        stride,
        phase,
        max_samples,
        mode,
        frames_seen: 0,
        candidates: 0,
        samples_written: 0,
        invalid_candidates: 0,
        skipped_by_limit: 0,
        output_bytes: 0,
      })
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceSampler::summary(self : SequenceSampler) -> SampleSummary {
  {
    input_bytes: self.scanner.offset(),
    frames_seen: self.frames_seen,
    candidates: self.candidates,
    samples_written: self.samples_written,
    invalid_candidates: self.invalid_candidates,
    skipped_by_limit: self.skipped_by_limit,
    output_bytes: self.output_bytes,
  }
}

///|
fn SequenceSampler::is_candidate(self : SequenceSampler) -> Bool {
  (self.frames_seen - 1) % self.stride == self.phase
}

///|
fn SequenceSampler::accept_frame(
  self : SequenceSampler,
  frame : FrameRecord,
  records : Array[SampleRecord],
  issues : Array[ValidationIssue],
) -> Unit {
  self.frames_seen = self.frames_seen + 1
  if !self.is_candidate() {
    return
  }
  self.candidates = self.candidates + 1
  if self.samples_written >= self.max_samples {
    self.skipped_by_limit = self.skipped_by_limit + 1
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
        start: frame.start,
        end: frame.end,
        bytes,
      })
      self.samples_written = self.samples_written + 1
      self.output_bytes = self.output_bytes + bytes.length()
    }
    Err(kind) => {
      self.invalid_candidates = self.invalid_candidates + 1
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
fn SequenceSampler::consume(
  self : SequenceSampler,
  raw : Array[FrameEvent],
) -> SampleBatch {
  let records : Array[SampleRecord] = []
  let issues : Array[ValidationIssue] = []
  for event in raw {
    match event {
      DataFrame(frame) => self.accept_frame(frame, records, issues)
      OversizedFrame(start, end) => {
        self.frames_seen = self.frames_seen + 1
        if self.is_candidate() {
          self.candidates = self.candidates + 1
          if self.samples_written >= self.max_samples {
            self.skipped_by_limit = self.skipped_by_limit + 1
          } else {
            self.invalid_candidates = self.invalid_candidates + 1
            issues.push({
              kind: RecordTooLarge,
              start,
              end,
              record_number: self.frames_seen,
            })
          }
        }
      }
      PreambleBytes(start, end) =>
        issues.push({ kind: BytesBeforeFirstRs, start, end, record_number: 0, })
    }
  }
  { records, issues, }
}

///|
pub fn SequenceSampler::feed(
  self : SequenceSampler,
  chunk : Bytes,
) -> Result[SampleBatch, String] {
  match self.scanner.feed(chunk) {
    Ok(raw) => Ok(self.consume(raw))
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceSampler::finish(
  self : SequenceSampler,
) -> Result[SampleBatch, String] {
  match self.scanner.finish() {
    Ok(raw) => Ok(self.consume(raw))
    Err(message) => Err(message)
  }
}
