///|
test "segmenter keeps complete records within byte limit" {
  let segmenter = @json_seq.SequenceSegmenter::new(100, 8).unwrap()
  let a = segmenter.feed(b"\x1e{}\n\x1e[]\n\x1e1\n").unwrap()
  assert_eq(a.segments.length(), 0)
  let b = segmenter.finish().unwrap()
  assert_eq(b.segments.length(), 2)
  assert_eq(b.segments[0].records, 2)
  assert_eq(b.segments[0].first_record_number, 1)
  assert_eq(b.segments[0].last_record_number, 2)
  assert_eq(b.segments[0].bytes.length(), 8)
  assert_eq(@utf8.decode(b.segments[1].bytes), "\u001e1\n")
  assert_eq(segmenter.summary().records_written, 3)
  assert_eq(segmenter.summary().segments_emitted, 2)
  assert_eq(segmenter.pending_bytes(), 0)
}

///|
test "segmenter skips bad and too-large canonical records" {
  let segmenter = @json_seq.SequenceSegmenter::new(100, 4).unwrap()
  let a = segmenter.feed(b"\x1e{bad}\x1e[1,2]\n\x1e{}\n").unwrap()
  assert_eq(a.issues.length(), 2)
  assert_eq(a.issues[0].failure.message(), "invalid JSON")
  assert_eq(
    a.issues[1].failure.message(),
    "canonical record exceeds max_segment_bytes",
  )
  let b = segmenter.finish().unwrap()
  assert_eq(b.segments.length(), 1)
  assert_eq(@utf8.decode(b.segments[0].bytes), "\u001e{}\n")
  assert_eq(segmenter.summary().records_dropped, 2)
  assert_true(segmenter.finish() is Err(_))
}

///|
test "segmenter validates limits" {
  assert_true(@json_seq.SequenceSegmenter::new(0, 1) is Err(_))
  assert_true(@json_seq.SequenceSegmenter::new(1, 0) is Err(_))
}
