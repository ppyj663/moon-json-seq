///|
test "adjacent deduplicator keeps run starts" {
  let dedup = @json_seq.SequenceDeduplicator::new(
    100,
    @json_seq.DedupMode::adjacent(),
  ).unwrap()
  let a = dedup.feed(b"\x1e1\n\x1e1\n\x1e2\n\x1e1\n").unwrap()
  assert_eq(a.records.length(), 2)
  assert_eq(a.duplicates.length(), 1)
  assert_eq(a.duplicates[0].first_record_number, 1)
  let b = dedup.finish().unwrap()
  assert_eq(b.records.length(), 1)
  assert_eq(@utf8.decode(b.records[0]), "\u001e1\n")
  assert_eq(dedup.summary().kept, 3)
  assert_eq(dedup.summary().duplicates, 1)
  assert_eq(dedup.summary().unique_keys, 1)
}

///|
test "global deduplicator finds nonadjacent duplicate" {
  let dedup = @json_seq.SequenceDeduplicator::new(
    100,
    @json_seq.DedupMode::global(),
  ).unwrap()
  let a = dedup.feed(b"\x1e{}\n\x1e[]\n\x1e{}\n").unwrap()
  assert_eq(a.records.length(), 2)
  assert_eq(a.duplicates.length(), 0)
  let b = dedup.finish().unwrap()
  assert_eq(b.duplicates.length(), 1)
  assert_eq(b.duplicates[0].first_record_number, 1)
  assert_eq(dedup.summary().unique_keys, 2)
}

///|
test "deduplicator reports invalid frames and resumes" {
  let dedup = @json_seq.SequenceDeduplicator::new(
    3,
    @json_seq.DedupMode::global(),
  ).unwrap()
  let a = dedup.feed(b"bad\x1e1234\x1e{}\n").unwrap()
  assert_eq(a.issues.length(), 2)
  let b = dedup.finish().unwrap()
  assert_eq(b.records.length(), 1)
  assert_eq(dedup.summary().invalid, 1)
  assert_true(dedup.finish() is Err(_))
}

///|
test "deduplicator rejects invalid bound" {
  assert_true(
    @json_seq.SequenceDeduplicator::new(0, @json_seq.DedupMode::adjacent())
    is Err(_),
  )
}
