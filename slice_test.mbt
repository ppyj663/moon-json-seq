///|
test "slicer extracts a half-open record range" {
  let range = @json_seq.RecordRange::new(2, 4).unwrap()
  assert_true(range.contains(2))
  assert_true(!range.contains(4))
  let slicer = @json_seq.SequenceSlicer::new(100, range, PreserveValid).unwrap()
  let a = slicer.feed(b"\x1e1\n\x1e{\n \"a\":2\n}\n\x1e{bad}\x1e[4]").unwrap()
  assert_eq(a.records.length(), 1)
  assert_eq(a.issues.length(), 1)
  assert_eq(a.issues[0].record_number, 3)
  assert_eq(a.records[0].record_number, 2)
  assert_eq(@utf8.decode(a.records[0].bytes), "\u001e{\n \"a\":2\n}\n")
  let b = slicer.finish().unwrap()
  assert_eq(b.issues.length(), 0)
  let summary = slicer.summary()
  assert_eq(summary.frames_seen, 4)
  assert_eq(summary.selected, 1)
  assert_eq(summary.invalid_in_range, 1)
  assert_eq(summary.outside_range, 2)
}

///|
test "slicer canonicalizes selected records" {
  let range = @json_seq.RecordRange::new(1, 2).unwrap()
  let slicer = @json_seq.SequenceSlicer::new(100, range, CanonicalizeValid).unwrap()
  let _ = slicer.feed(b"\x1e { \"a\" : 1 } \n").unwrap()
  let batch = slicer.finish().unwrap()
  assert_eq(@utf8.decode(batch.records[0].bytes), "\u001e{\"a\":1}\n")
  assert_true(slicer.finish() is Err(_))
}

///|
test "slicer validates its bounds" {
  assert_true(@json_seq.RecordRange::new(0, 2) is Err(_))
  assert_true(@json_seq.RecordRange::new(2, 2) is Err(_))
  let range = @json_seq.RecordRange::new(1, 2).unwrap()
  assert_true(@json_seq.SequenceSlicer::new(0, range, PreserveValid) is Err(_))
}

///|
test "record ranges split intersect and merge" {
  let range = @json_seq.RecordRange::new(2, 9).unwrap()
  let parts = range.split(3).unwrap()
  assert_eq(parts.length(), 3)
  assert_eq(parts[0].length(), 3)
  assert_eq(parts[2].length(), 1)
  let other = @json_seq.RecordRange::new(8, 12).unwrap()
  assert_true(range.overlaps(other))
  assert_eq(range.intersection(other).unwrap().start, 8)
  assert_eq(range.merge_touching(other).unwrap().end, 12)
  let later = @json_seq.RecordRange::new(12, 15).unwrap()
  assert_true(range.is_before(later))
  assert_true(range.intersection(later) is None)
  assert_true(range.merge_touching(later) is None)
  assert_true(range.split(0) is Err(_))
}
