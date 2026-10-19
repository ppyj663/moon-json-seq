///|
test "validator counts valid kinds and recoverable errors" {
  let validator = @json_seq.SequenceValidator::new(16, 2).unwrap()
  let notices = validator.feed(b"xx\x1e{}\n\x1e\xff\x1e123\x1e[]\n").unwrap()
  assert_eq(notices.length(), 4)
  match notices[0] {
    BadRecord(issue) => {
      assert_eq(issue.start, 0)
      assert_eq(issue.end, 2)
      assert_eq(issue.record_number, 0)
      assert_eq(issue.message(), "bytes before first RS")
    }
    _ => fail("expected preamble issue")
  }
  match notices[1] {
    ValidRecord(record) => {
      assert_eq(record.start, 3)
      assert_eq(record.end, 6)
    }
    _ => fail("expected object")
  }
  match notices[2] {
    BadRecord(issue) => {
      assert_eq(issue.start, 7)
      assert_eq(issue.record_number, 2)
    }
    _ => fail("expected UTF-8 issue")
  }
  match notices[3] {
    BadRecord(issue) => {
      assert_eq(issue.start, 9)
      assert_eq(issue.record_number, 3)
    }
    _ => fail("expected scalar issue")
  }
  let before_finish = validator.summary()
  assert_eq(before_finish.frames(), 3)
  let final_notices = validator.finish().unwrap()
  assert_eq(final_notices.length(), 1)
  match final_notices[0] {
    ValidRecord(record) => assert_eq(record.start, 13)
    _ => fail("expected array")
  }
  let summary = validator.summary()
  assert_eq(before_finish.frames(), 3)
  assert_eq(summary.total_bytes(), 16)
  assert_eq(summary.frames(), 4)
  assert_eq(summary.valid_records(), 2)
  assert_eq(summary.invalid_records(), 2)
  assert_eq(summary.preamble_regions(), 1)
  assert_eq(summary.preamble_bytes(), 2)
  assert_eq(summary.invalid_utf8(), 1)
  assert_eq(summary.truncated_scalars(), 1)
  assert_eq(summary.objects(), 1)
  assert_eq(summary.arrays(), 1)
  assert_eq(summary.json_body_bytes(), 10)
  assert_eq(summary.line_breaks(), 2)
  assert_eq(summary.largest_frame_bytes(), 3)
  assert_eq(summary.issues_seen(), 3)
  assert_eq(summary.issues_retained(), 2)
  assert_true(!summary.is_clean())
  assert_eq(validator.issues().length(), 2)
}

///|
test "validator counts oversize and resumes" {
  let validator = @json_seq.SequenceValidator::new(3, 4).unwrap()
  let notices = validator.feed(b"\x1e1234\x1e{}\n").unwrap()
  match notices[0] {
    BadRecord(issue) => {
      assert_eq(issue.start, 1)
      assert_eq(issue.end, 5)
      assert_eq(issue.record_number, 1)
    }
    _ => fail("expected oversize")
  }
  assert_eq(validator.finish().unwrap().length(), 1)
  let summary = validator.summary()
  assert_eq(summary.frames(), 2)
  assert_eq(summary.valid_records(), 1)
  assert_eq(summary.invalid_records(), 1)
  assert_eq(summary.oversized_records(), 1)
  assert_eq(summary.largest_frame_bytes(), 4)
}

///|
test "validator can stream without retaining issues" {
  let validator = @json_seq.SequenceValidator::new(100, 0).unwrap()
  let notices = validator.feed(b"\x1e{bad}\n\x1e{}\n").unwrap()
  assert_eq(notices.length(), 1)
  let _ = validator.finish().unwrap()
  let summary = validator.summary()
  assert_eq(summary.invalid_json(), 1)
  assert_eq(summary.issues_seen(), 1)
  assert_eq(summary.issues_retained(), 0)
  assert_eq(validator.issues().length(), 0)
}

///|
test "validator counts all JSON value kinds" {
  let validator = @json_seq.SequenceValidator::new(100, 1).unwrap()
  let _ = validator
    .feed(b"\x1enull\n\x1etrue\n\x1e42\n\x1e\"a\"\n\x1e[]\n\x1e{}\n")
    .unwrap()
  let _ = validator.finish().unwrap()
  let summary = validator.summary()
  assert_eq(summary.frames(), 6)
  assert_eq(summary.valid_records(), 6)
  assert_eq(summary.nulls(), 1)
  assert_eq(summary.booleans(), 1)
  assert_eq(summary.numbers(), 1)
  assert_eq(summary.strings(), 1)
  assert_eq(summary.arrays(), 1)
  assert_eq(summary.objects(), 1)
  assert_true(summary.is_clean())
}

///|
test "validator validates its limits and lifecycle" {
  assert_true(@json_seq.SequenceValidator::new(0, 1) is Err(_))
  assert_true(@json_seq.SequenceValidator::new(1, -1) is Err(_))
  let validator = @json_seq.SequenceValidator::new(10, 1).unwrap()
  assert_eq(validator.feed(b"").unwrap().length(), 0)
  assert_eq(validator.finish().unwrap().length(), 0)
  assert_true(validator.feed(b"x") is Err(_))
  assert_true(validator.finish() is Err(_))
}
