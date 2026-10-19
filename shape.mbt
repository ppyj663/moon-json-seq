///|
/// Structural measurements of a parsed JSON tree. Root depth is zero.
pub(all) struct JsonShape {
  mut nodes : Int
  mut max_depth : Int
  mut objects : Int
  mut object_members : Int
  mut arrays : Int
  mut array_items : Int
  mut strings : Int
  mut string_utf8_bytes : Int
  mut numbers : Int
  mut booleans : Int
  mut nulls : Int
}

///|
fn empty_shape() -> JsonShape {
  {
    nodes: 0,
    max_depth: 0,
    objects: 0,
    object_members: 0,
    arrays: 0,
    array_items: 0,
    strings: 0,
    string_utf8_bytes: 0,
    numbers: 0,
    booleans: 0,
    nulls: 0,
  }
}

///|
/// Analyze a single JSON value, including every nested value. This uses an
/// explicit work queue rather than recursive calls.
pub fn analyze_json(value : Json) -> JsonShape {
  let shape = empty_shape()
  let queue : Array[(Json, Int)] = [(value, 0)]
  let mut next = 0
  while next < queue.length() {
    let (current, depth) = queue[next]
    next = next + 1
    shape.nodes = shape.nodes + 1
    if depth > shape.max_depth {
      shape.max_depth = depth
    }
    match current {
      Object(members) => {
        shape.objects = shape.objects + 1
        for pair in members.iter() {
          let (key, child) = pair
          shape.object_members = shape.object_members + 1
          shape.string_utf8_bytes = shape.string_utf8_bytes +
            @utf8.encode(key).length()
          queue.push((child, depth + 1))
        }
      }
      Array(items) => {
        shape.arrays = shape.arrays + 1
        shape.array_items = shape.array_items + items.length()
        for child in items {
          queue.push((child, depth + 1))
        }
      }
      String(text) => {
        shape.strings = shape.strings + 1
        shape.string_utf8_bytes = shape.string_utf8_bytes +
          @utf8.encode(text).length()
      }
      Number(_, ..) => shape.numbers = shape.numbers + 1
      True | False => shape.booleans = shape.booleans + 1
      Null => shape.nulls = shape.nulls + 1
    }
  }
  shape
}

///|
/// Add independent document shapes. The maximum depth is the deepest root
/// relative depth among the documents, not a nesting of one inside another.
pub fn JsonShape::plus(self : JsonShape, other : JsonShape) -> JsonShape {
  {
    nodes: self.nodes + other.nodes,
    max_depth: if self.max_depth > other.max_depth {
      self.max_depth
    } else {
      other.max_depth
    },
    objects: self.objects + other.objects,
    object_members: self.object_members + other.object_members,
    arrays: self.arrays + other.arrays,
    array_items: self.array_items + other.array_items,
    strings: self.strings + other.strings,
    string_utf8_bytes: self.string_utf8_bytes + other.string_utf8_bytes,
    numbers: self.numbers + other.numbers,
    booleans: self.booleans + other.booleans,
    nulls: self.nulls + other.nulls,
  }
}

///|
pub(all) struct RecordShape {
  record_number : Int
  start : Int
  end : Int
  shape : JsonShape
}

///|
pub(all) struct ShapeBatch {
  records : Array[RecordShape]
  issues : Array[ValidationIssue]
}

///|
/// Analyze nested structure across an incrementally supplied sequence.
pub struct SequenceShapeAnalyzer {
  validator : SequenceValidator
  mut aggregate : JsonShape
  mut records_analyzed : Int
  mut frames_seen : Int
}

///|
pub fn SequenceShapeAnalyzer::new(
  max_record_bytes : Int,
) -> Result[SequenceShapeAnalyzer, String] {
  match SequenceValidator::new(max_record_bytes, 0) {
    Ok(validator) =>
      Ok({
        validator,
        aggregate: empty_shape(),
        records_analyzed: 0,
        frames_seen: 0,
      })
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceShapeAnalyzer::shape(self : SequenceShapeAnalyzer) -> JsonShape {
  self.aggregate.plus(empty_shape())
}

///|
pub fn SequenceShapeAnalyzer::records_analyzed(
  self : SequenceShapeAnalyzer,
) -> Int {
  self.records_analyzed
}

///|
pub fn SequenceShapeAnalyzer::validation(
  self : SequenceShapeAnalyzer,
) -> ValidationSummary {
  self.validator.summary()
}

///|
fn SequenceShapeAnalyzer::consume(
  self : SequenceShapeAnalyzer,
  notices : Array[ValidationNotice],
) -> ShapeBatch {
  let records : Array[RecordShape] = []
  let issues : Array[ValidationIssue] = []
  for notice in notices {
    match notice {
      ValidRecord(inspection) =>
        match inspection.outcome {
          Ok(value) => {
            self.frames_seen = self.frames_seen + 1
            let shape = analyze_json(value)
            self.aggregate = self.aggregate.plus(shape)
            self.records_analyzed = self.records_analyzed + 1
            records.push({
              record_number: self.frames_seen,
              start: inspection.start,
              end: inspection.end,
              shape,
            })
          }
          Err(_) => ()
        }
      BadRecord(issue) => {
        if issue.record_number > 0 {
          self.frames_seen = self.frames_seen + 1
        }
        issues.push(issue)
      }
    }
  }
  { records, issues, }
}

///|
pub fn SequenceShapeAnalyzer::feed(
  self : SequenceShapeAnalyzer,
  chunk : Bytes,
) -> Result[ShapeBatch, String] {
  match self.validator.feed(chunk) {
    Ok(notices) => Ok(self.consume(notices))
    Err(message) => Err(message)
  }
}

///|
pub fn SequenceShapeAnalyzer::finish(
  self : SequenceShapeAnalyzer,
) -> Result[ShapeBatch, String] {
  match self.validator.finish() {
    Ok(notices) => Ok(self.consume(notices))
    Err(message) => Err(message)
  }
}
