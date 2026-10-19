///|
test "repairer preserves valid frame bytes and reports discarded spans" {
  let repairer = @json_seq.SequenceRepairer::new(100, PreserveValid).unwrap()
  let first = repairer.feed(b"noise\x1e{\n \"a\": 1\n}\n\x1e{bad}").unwrap()
  assert_eq(first.records.length(), 1)
  assert_eq(@utf8.decode(first.records[0]), "\u001e{\n \"a\": 1\n}\n")
  assert_eq(first.dropped.length(), 1)
  assert_true(first.dropped[0].kind is BytesBeforeFirstRs)
  let last = repairer.feed(b"\x1e[2]").unwrap()
  assert_eq(last.dropped.length(), 1)
  assert_true(last.dropped[0].kind is InvalidJson)
  assert_eq(last.dropped[0].record_number, 2)
  assert_eq(@utf8.decode(repairer.finish().unwrap().records[0]), "\u001e[2]")
  let summary = repairer.summary()
  assert_eq(summary.frames_seen, 3)
  assert_eq(summary.records_written, 2)
  assert_eq(summary.records_dropped, 1)
  assert_eq(summary.preamble_bytes_dropped, 5)
  assert_eq(summary.output_bytes, first.records[0].length() + 4)
}

///|
test "repairer canonicalizes and skips oversize frames" {
  let repairer = @json_seq.SequenceRepairer::new(8, CanonicalizeValid).unwrap()
  let batch = repairer.feed(b"\x1e123456789\x1e { } \n").unwrap()
  assert_eq(batch.dropped.length(), 1)
  assert_true(batch.dropped[0].kind is RecordTooLarge)
  let tail = repairer.finish().unwrap()
  assert_eq(@utf8.decode(tail.records[0]), "\u001e{}\n")
  assert_eq(repairer.summary().records_written, 1)
  assert_true(repairer.finish() is Err(_))
  assert_true(repairer.feed(b"x") is Err(_))
}

///|
test "repairer requires positive record limit" {
  assert_true(@json_seq.SequenceRepairer::new(0, PreserveValid) is Err(_))
}
