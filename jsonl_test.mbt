///|
test "JSON Lines to sequence handles CRLF and split lines" {
  let converter = @json_seq.JsonLinesToSequence::new(100).unwrap()
  let a = converter.feed(b"{\"a\":1}\r").unwrap()
  assert_eq(a.records.length(), 0)
  let b = converter.feed(b"\n[1,2]\ntrue").unwrap()
  assert_eq(b.records.length(), 2)
  assert_eq(@utf8.decode(b.records[0]), "\u001e{\"a\":1}\n")
  assert_eq(@utf8.decode(b.records[1]), "\u001e[1,2]\n")
  let c = converter.finish().unwrap()
  assert_eq(@utf8.decode(c.records[0]), "\u001etrue\n")
  let summary = converter.summary()
  assert_eq(summary.lines_seen, 3)
  assert_eq(summary.records_written, 3)
  assert_eq(summary.lines_rejected, 0)
  assert_true(converter.feed(b"x") is Err(_))
}

///|
test "JSON Lines converter diagnoses blank invalid and oversized lines" {
  let converter = @json_seq.JsonLinesToSequence::new(5).unwrap()
  let batch = converter.feed(b"\n{bad}\n123456\n{}\n").unwrap()
  assert_eq(batch.records.length(), 1)
  assert_eq(batch.issues.length(), 3)
  assert_true(batch.issues[0].kind is BlankLine)
  assert_true(batch.issues[1].kind is InvalidLineJson)
  assert_true(batch.issues[2].kind is LineTooLarge)
  assert_eq(batch.issues[2].line_number, 3)
  assert_eq(batch.issues[2].start, 7)
  assert_eq(converter.summary().lines_rejected, 3)
}

///|
test "JSON Lines converter diagnoses invalid UTF-8 and preserves later line" {
  let converter = @json_seq.JsonLinesToSequence::new(10).unwrap()
  let batch = converter.feed(b"\xff\nnull\n").unwrap()
  assert_true(batch.issues[0].kind is InvalidLineUtf8)
  assert_eq(@utf8.decode(batch.records[0]), "\u001enull\n")
}

///|
test "JSON Lines converter accepts limit and rejects invalid limit" {
  assert_true(@json_seq.JsonLinesToSequence::new(0) is Err(_))
  let converter = @json_seq.JsonLinesToSequence::new(4).unwrap()
  let batch = converter.feed(b"null\n").unwrap()
  assert_eq(batch.records.length(), 1)
  assert_eq(converter.pending_bytes(), 0)
  assert_eq(converter.finish().unwrap().records.length(), 0)
  assert_true(converter.finish() is Err(_))
}

///|
test "JSON Lines converter rejects a byte order mark" {
  let converter = @json_seq.JsonLinesToSequence::new(20).unwrap()
  let batch = converter.feed(b"\xef\xbb\xbf{}\n").unwrap()
  assert_eq(batch.records.length(), 0)
  assert_eq(batch.issues.length(), 1)
}

///|
test "sequence to JSON Lines drops bad frames and compacts good ones" {
  let converter = @json_seq.SequenceToJsonLines::new(100).unwrap()
  let a = converter.feed(b"oops\x1e{\n \"x\": 1\n}\n\x1e{bad}\n").unwrap()
  assert_eq(a.dropped.length(), 1)
  assert_eq(a.lines.length(), 1)
  assert_eq(@utf8.decode(a.lines[0]), "{\"x\":1}\n")
  let b = converter.feed(b"\x1e[2]\n").unwrap()
  assert_eq(b.dropped.length(), 1)
  assert_true(b.dropped[0].kind is InvalidJson)
  let c = converter.finish().unwrap()
  assert_eq(@utf8.decode(c.lines[0]), "[2]\n")
  let summary = converter.summary()
  assert_eq(summary.frames_seen, 3)
  assert_eq(summary.lines_written, 2)
  assert_eq(summary.frames_dropped, 1)
  assert_true(converter.feed(b"x") is Err(_))
}

///|
test "sequence to JSON Lines reports oversized input" {
  let converter = @json_seq.SequenceToJsonLines::new(4).unwrap()
  let batch = converter.feed(b"\x1e12345\x1e{}\n").unwrap()
  assert_true(batch.dropped[0].kind is RecordTooLarge)
  assert_eq(@utf8.decode(converter.finish().unwrap().lines[0]), "{}\n")
}
