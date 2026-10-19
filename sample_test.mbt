///|
test "sampler selects deterministic ordinals across chunks" {
  let sampler = @json_seq.SequenceSampler::new(100, 3, 1, 2, PreserveValid).unwrap()
  let a = sampler.feed(b"\x1e0\n\x1e1\n\x1e2\n\x1e3\n\x1e4\n").unwrap()
  assert_eq(a.records.length(), 1)
  assert_eq(a.records[0].record_number, 2)
  let b = sampler.feed(b"\x1e5\n\x1e6\n\x1e7\n").unwrap()
  assert_eq(b.records.length(), 1)
  assert_eq(b.records[0].record_number, 5)
  let c = sampler.finish().unwrap()
  assert_eq(c.records.length(), 0)
  let summary = sampler.summary()
  assert_eq(summary.frames_seen, 8)
  assert_eq(summary.candidates, 3)
  assert_eq(summary.samples_written, 2)
  assert_eq(summary.skipped_by_limit, 1)
}

///|
test "sampler reports invalid candidates without consuming sample quota" {
  let sampler = @json_seq.SequenceSampler::new(100, 2, 0, 1, CanonicalizeValid).unwrap()
  let a = sampler.feed(b"\x1e{bad}\x1e[]\n\x1e { } \n").unwrap()
  assert_eq(a.issues.length(), 1)
  assert_eq(a.records.length(), 0)
  let b = sampler.finish().unwrap()
  assert_eq(b.records.length(), 1)
  assert_eq(b.records[0].record_number, 3)
  assert_eq(@utf8.decode(b.records[0].bytes), "\u001e{}\n")
  assert_eq(sampler.summary().invalid_candidates, 1)
  assert_eq(sampler.summary().samples_written, 1)
  assert_true(sampler.finish() is Err(_))
}

///|
test "sampler validates configuration" {
  assert_true(
    @json_seq.SequenceSampler::new(0, 1, 0, 1, PreserveValid) is Err(_),
  )
  assert_true(
    @json_seq.SequenceSampler::new(1, 0, 0, 1, PreserveValid) is Err(_),
  )
  assert_true(
    @json_seq.SequenceSampler::new(1, 2, 2, 1, PreserveValid) is Err(_),
  )
  assert_true(
    @json_seq.SequenceSampler::new(1, 2, -1, 1, PreserveValid) is Err(_),
  )
  assert_true(
    @json_seq.SequenceSampler::new(1, 2, 0, 0, PreserveValid) is Err(_),
  )
}
