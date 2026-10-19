///|
/// A predicate applied to each valid JSON value in a sequence.
pub enum QueryPredicate {
  MatchAll
  ObjectsOnly
  ArraysOnly
  ScalarsOnly
  PointerExists(JsonPointer)
  PointerEquals(JsonPointer, Json)
}

///|
pub fn QueryPredicate::all() -> QueryPredicate {
  MatchAll
}

///|
pub fn QueryPredicate::objects() -> QueryPredicate {
  ObjectsOnly
}

///|
pub fn QueryPredicate::arrays() -> QueryPredicate {
  ArraysOnly
}

///|
pub fn QueryPredicate::scalars() -> QueryPredicate {
  ScalarsOnly
}

///|
pub fn QueryPredicate::has(pointer : JsonPointer) -> QueryPredicate {
  PointerExists(pointer)
}

///|
pub fn QueryPredicate::equals(
  pointer : JsonPointer,
  expected : Json,
) -> QueryPredicate {
  PointerEquals(pointer, expected)
}

///|
pub fn QueryPredicate::matches(self : QueryPredicate, value : Json) -> Bool {
  match self {
    MatchAll => true
    ObjectsOnly => value is Object(_)
    ArraysOnly => value is Array(_)
    ScalarsOnly =>
      match value {
        Object(_) | Array(_) => false
        _ => true
      }
    PointerExists(pointer) => pointer.resolve(value) is Ok(_)
    PointerEquals(pointer, expected) =>
      match pointer.resolve(value) {
        Ok(actual) => actual == expected
        Err(_) => false
      }
  }
}

///|
/// A selected value and its original record span. `encoded` is a complete
/// compact RFC 7464 frame for the selected value.
pub(all) struct QueryMatch {
  record_number : Int
  start : Int
  end : Int
  value : Json
  encoded : Bytes
}

///|
/// A parse error or unresolved projection, with its original byte span.
pub enum QueryFailure {
  InvalidInput(DiagnosticKind)
  MissingProjection(PointerFailure)
}

///|
pub fn QueryFailure::message(self : QueryFailure) -> String {
  match self {
    InvalidInput(kind) => kind.message()
    MissingProjection(failure) => failure.message()
  }
}

///|
pub(all) struct QueryIssue {
  failure : QueryFailure
  record_number : Int
  start : Int
  end : Int
}

///|
pub(all) struct QueryBatch {
  matches : Array[QueryMatch]
  issues : Array[QueryIssue]
}

///|
pub(all) struct QuerySummary {
  input_bytes : Int
  frames_seen : Int
  matched : Int
  filtered : Int
  invalid : Int
  missing_projection : Int
  output_bytes : Int
}

///|
/// Stream a sequence through a value predicate and optional JSON Pointer
/// projection. Returned batches contain complete canonical frames.
pub struct SequenceQuery {
  scanner : FrameScanner
  predicate : QueryPredicate
  projection : JsonPointer?
  mut frames_seen : Int
  mut matched : Int
  mut filtered : Int
  mut invalid : Int
  mut missing_projection : Int
  mut output_bytes : Int
}

///|
pub fn SequenceQuery::new(
  max_record_bytes : Int,
  predicate : QueryPredicate,
  projection : JsonPointer?,
) -> Result[SequenceQuery, String] {
  match FrameScanner::new(max_record_bytes) {
    Err(message) => Err(message)
    Ok(scanner) =>
      Ok({
        scanner,
        predicate,
        projection,
        frames_seen: 0,
        matched: 0,
        filtered: 0,
        invalid: 0,
        missing_projection: 0,
        output_bytes: 0,
      })
  }
}

///|
pub fn SequenceQuery::summary(self : SequenceQuery) -> QuerySummary {
  {
    input_bytes: self.scanner.offset(),
    frames_seen: self.frames_seen,
    matched: self.matched,
    filtered: self.filtered,
    invalid: self.invalid,
    missing_projection: self.missing_projection,
    output_bytes: self.output_bytes,
  }
}

///|
fn SequenceQuery::add_invalid(
  self : SequenceQuery,
  kind : DiagnosticKind,
  start : Int,
  end : Int,
  issues : Array[QueryIssue],
) -> Unit {
  self.invalid = self.invalid + 1
  issues.push({
    failure: InvalidInput(kind),
    record_number: self.frames_seen,
    start,
    end,
  })
}

///|
fn SequenceQuery::select(
  self : SequenceQuery,
  value : Json,
  frame : FrameRecord,
  matches : Array[QueryMatch],
  issues : Array[QueryIssue],
) -> Unit {
  if !self.predicate.matches(value) {
    self.filtered = self.filtered + 1
    return
  }
  let selected = match self.projection {
    None => value
    Some(pointer) =>
      match pointer.resolve(value) {
        Ok(found) => found
        Err(failure) => {
          self.missing_projection = self.missing_projection + 1
          issues.push({
            failure: MissingProjection(failure),
            record_number: self.frames_seen,
            start: frame.start,
            end: frame.end,
          })
          return
        }
      }
  }
  let encoded = encode(selected)
  matches.push({
    record_number: self.frames_seen,
    start: frame.start,
    end: frame.end,
    value: selected,
    encoded,
  })
  self.matched = self.matched + 1
  self.output_bytes = self.output_bytes + encoded.length()
}

///|
fn SequenceQuery::consume(
  self : SequenceQuery,
  raw : Array[FrameEvent],
) -> QueryBatch {
  let matches : Array[QueryMatch] = []
  let issues : Array[QueryIssue] = []
  for event in raw {
    match event {
      DataFrame(frame) => {
        self.frames_seen = self.frames_seen + 1
        match inspect_frame(frame).outcome {
          Ok(value) => self.select(value, frame, matches, issues)
          Err(kind) => self.add_invalid(kind, frame.start, frame.end, issues)
        }
      }
      OversizedFrame(start, end) => {
        self.frames_seen = self.frames_seen + 1
        self.add_invalid(RecordTooLarge, start, end, issues)
      }
      PreambleBytes(start, end) =>
        issues.push({
          failure: InvalidInput(BytesBeforeFirstRs),
          record_number: 0,
          start,
          end,
        })
    }
  }
  { matches, issues, }
}

///|
pub fn SequenceQuery::feed(
  self : SequenceQuery,
  chunk : Bytes,
) -> Result[QueryBatch, String] {
  match self.scanner.feed(chunk) {
    Ok(raw) => Ok(self.consume(raw))
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceQuery::finish(
  self : SequenceQuery,
) -> Result[QueryBatch, String] {
  match self.scanner.finish() {
    Ok(raw) => Ok(self.consume(raw))
    Err(message) => Err(message)
  }
}
