///|
test "index records positions and extracts raw frames" {
  let source = b"xx\x1e{}\n\x1e{bad}\x1e[1]"
  let index = @json_seq.SequenceIndex::new(100).unwrap()
  let first = index.feed(source).unwrap()
  assert_eq(first.preamble_spans.length(), 1)
  assert_eq(first.entries.length(), 2)
  let last = index.finish().unwrap()
  assert_eq(last.entries.length(), 1)
  assert_eq(index.length(), 3)
  assert_eq(index.record(1).unwrap().start, 3)
  assert_eq(
    @utf8.decode(index.record(1).unwrap().extract(source).unwrap()),
    "\u001e{}\n",
  )
  assert_true(index.record(2).unwrap().diagnostic is Some(_))
  assert_eq(
    @utf8.decode(index.record(3).unwrap().extract(source).unwrap()),
    "\u001e[1]",
  )
  assert_true(index.record(3).unwrap().kind is Some(_))
  assert_true(index.record(0) is None)
  assert_true(index.record(4) is None)
}

///|
test "index locates offsets and range intersections" {
  let index = @json_seq.SequenceIndex::new(100).unwrap()
  let _ = index.feed(b"xx\x1e{}\n\x1e[1]").unwrap()
  let _ = index.finish().unwrap()
  assert_true(index.at_byte(0) is None)
  assert_eq(index.at_byte(2).unwrap().record_number, 1)
  assert_eq(index.at_byte(5).unwrap().record_number, 1)
  assert_eq(index.at_byte(6).unwrap().record_number, 2)
  assert_true(index.at_byte(10) is None)
  assert_eq(index.intersecting(4, 7).length(), 2)
  assert_eq(index.intersecting(0, 2).length(), 0)
  assert_eq(index.intersecting(-1, 2).length(), 0)
}

///|
test "index tracks oversized frames and validates extraction source" {
  let index = @json_seq.SequenceIndex::new(3).unwrap()
  let batch = index.feed(b"\x1e1234\x1e{}\n").unwrap()
  assert_eq(batch.entries.length(), 1)
  assert_true(batch.entries[0].diagnostic is Some(_))
  let _ = index.finish().unwrap()
  let summary = index.summary()
  assert_eq(summary.records, 2)
  assert_eq(summary.valid, 1)
  assert_eq(summary.invalid, 1)
  assert_eq(summary.indexed_bytes, 9)
  assert_true(index.record(1).unwrap().extract(b"x") is Err(_))
  assert_true(index.record(2).unwrap().extract(b"xxxxxx{}\n") is Err(_))
  assert_true(index.finish() is Err(_))
}

///|
test "index requires positive frame bound" {
  assert_true(@json_seq.SequenceIndex::new(0) is Err(_))
}
