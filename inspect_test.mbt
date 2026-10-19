///|
test "inspection reports raw frame geometry" {
  let record = @json_seq.inspect_frame_bytes(b"  {\n\"a\":1}\n", 41)
  assert_true(record.is_valid())
  assert_eq(record.start, 41)
  assert_eq(record.end, 52)
  assert_eq(record.byte_length, 11)
  assert_eq(record.line_breaks, 2)
  assert_eq(record.leading_whitespace, 2)
  assert_eq(record.trailing_whitespace, 1)
  assert_true(record.has_final_lf)
  match record.json_kind() {
    Some(ObjectValue) => ()
    _ => fail("expected object kind")
  }
}

///|
test "inspection canonicalizes valid object" {
  let record = @json_seq.inspect_frame_bytes(b"{ \"a\": 1 }\n", 1)
  match record.canonical_frame() {
    Some(bytes) => assert_eq(@utf8.decode(bytes), "\u001e{\"a\":1}\n")
    None => fail("expected canonical frame")
  }
}

///|
test "inspection distinguishes null from parse failure" {
  let valid = @json_seq.inspect_frame_bytes(b"null\n", 5)
  assert_true(valid.is_valid())
  match valid.value() {
    Some(Null) => ()
    _ => fail("expected JSON null")
  }
  match valid.json_kind() {
    Some(NullValue) => ()
    _ => fail("expected null kind")
  }
  assert_true(valid.diagnostic() is None)
  let invalid = @json_seq.inspect_frame_bytes(b"nul\n", 5)
  assert_true(invalid.value() is None)
  match invalid.diagnostic() {
    Some(InvalidJson) => ()
    _ => fail("expected JSON error")
  }
}

///|
test "inspection accepts whitespace-terminated scalar" {
  let record = @json_seq.inspect_frame_bytes(b"\t123 \r", 1)
  assert_true(record.is_valid())
  assert_eq(record.leading_whitespace, 1)
  assert_eq(record.trailing_whitespace, 2)
  assert_true(!record.has_final_lf)
  match record.json_kind() {
    Some(NumberValue) => ()
    _ => fail("expected number kind")
  }
}

///|
test "inspection detects scalar truncation" {
  let record = @json_seq.inspect_frame_bytes(b"true", 1)
  match record.diagnostic() {
    Some(TruncatedScalar) => ()
    _ => fail("expected scalar warning")
  }
  assert_true(record.canonical_frame() is None)
}

///|
test "inspection reports invalid UTF-8 before JSON parsing" {
  let record = @json_seq.inspect_frame_bytes(b"\xff\n", 1)
  match record.diagnostic() {
    Some(InvalidUtf8) => ()
    _ => fail("expected UTF-8 error")
  }
  assert_true(record.json_kind() is None)
}

///|
test "inspection labels all JSON kinds" {
  let inputs = [b"null\n", b"true\n", b"42\n", b"\"x\"\n", b"[]\n", b"{}\n"]
  let names = ["null", "boolean", "number", "string", "array", "object"]
  for i = 0; i < inputs.length(); i = i + 1 {
    let record = @json_seq.inspect_frame_bytes(inputs[i], 0)
    match record.json_kind() {
      Some(kind) => assert_eq(kind.label(), names[i])
      None => fail("expected valid kind")
    }
  }
}
