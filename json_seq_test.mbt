///|
test "encode RFC 7464 record" {
  let value = @json.parse("{\"city\":\"北京\"}")
  let bytes = @json_seq.encode(value)
  assert_eq(bytes[0], 0x1e)
  assert_eq(bytes[bytes.length() - 1], 0x0a)
  assert_eq(@utf8.decode(bytes), "\u001e{\"city\":\"北京\"}\n")
}

///|
test "incremental decode across byte boundaries" {
  let decoder = @json_seq.Decoder::new(1024).unwrap()
  let a = decoder.feed(b"\x1e{\"a\":").unwrap()
  assert_eq(a.length(), 0)
  let b = decoder.feed(b"1}\n\x1e[2]").unwrap()
  assert_eq(b.length(), 1)
  match b[0] {
    Value(value, 1) => assert_eq(value.stringify(), "{\"a\":1}")
    _ => fail("expected first value")
  }
  let c = decoder.finish().unwrap()
  assert_eq(c.length(), 1)
  match c[0] {
    Value(value, 10) => assert_eq(value.stringify(), "[2]")
    _ => fail("expected second value")
  }
}

///|
test "recover after malformed JSON and consecutive RS" {
  let decoder = @json_seq.Decoder::new(100).unwrap()
  let events = decoder.feed(b"\x1e\x1e{bad}\n\x1e{}\n").unwrap()
  assert_eq(events.length(), 1)
  match events[0] {
    Error(InvalidJson, 2) => ()
    _ => fail("expected JSON error")
  }
  let final_events = decoder.finish().unwrap()
  match final_events[0] {
    Value(value, 9) => assert_eq(value.stringify(), "{}")
    _ => fail("expected recovered value")
  }
}

///|
test "truncated scalar and valid scalar" {
  let decoder = @json_seq.Decoder::new(100).unwrap()
  let events = decoder.feed(b"\x1e123\x1etrue\n").unwrap()
  match events[0] {
    Error(TruncatedScalar, 1) => ()
    _ => fail("expected truncation diagnostic")
  }
  let final_events = decoder.finish().unwrap()
  match final_events[0] {
    Value(value, 5) => assert_eq(value.stringify(), "true")
    _ => fail("expected scalar")
  }
}

///|
test "invalid UTF8 recovers" {
  let decoder = @json_seq.Decoder::new(100).unwrap()
  let events = decoder.feed(b"\x1e\xff\x1e{}\n").unwrap()
  match events[0] {
    Error(InvalidUtf8, 1) => ()
    _ => fail("expected UTF-8 diagnostic")
  }
  assert_eq(decoder.finish().unwrap().length(), 1)
}

///|
test "oversize record discards until separator" {
  let decoder = @json_seq.Decoder::new(3).unwrap()
  let events = decoder.feed(b"\x1e1234\x1e{}\n").unwrap()
  match events[0] {
    Error(RecordTooLarge, 1) => ()
    _ => fail("expected size diagnostic")
  }
  match decoder.finish().unwrap()[0] {
    Value(value, 6) => assert_eq(value.stringify(), "{}")
    _ => fail("expected value after oversize")
  }
}

///|
test "preamble and lifecycle errors" {
  assert_true(@json_seq.Decoder::new(0) is Err(_))
  let decoder = @json_seq.Decoder::new(100).unwrap()
  let events = decoder.feed(b"oops\x1e{}\n").unwrap()
  match events[0] {
    Error(BytesBeforeFirstRs, 0) => ()
    _ => fail("expected preamble diagnostic")
  }
  assert_eq(decoder.finish().unwrap().length(), 1)
  assert_true(decoder.finish() is Err(_))
  assert_true(decoder.feed(b"x") is Err(_))
}

///|
test "Unicode split between UTF-8 bytes" {
  let decoder = @json_seq.Decoder::new(100).unwrap()
  let _ = decoder.feed(b"\x1e\"\xe4").unwrap()
  let _ = decoder.feed(b"\xb8").unwrap()
  let _ = decoder.feed(b"\xad\"\n").unwrap()
  match decoder.finish().unwrap()[0] {
    Value(value, 1) => assert_eq(value.stringify(), "\"中\"")
    _ => fail("expected Unicode value")
  }
}

///|
test "array without LF is a valid final record" {
  let decoder = @json_seq.Decoder::new(100).unwrap()
  let _ = decoder.feed(b"\x1e[1,2]").unwrap()
  match decoder.finish().unwrap()[0] {
    Value(value, 1) => assert_eq(value.stringify(), "[1,2]")
    _ => fail("expected array")
  }
}

///|
test "empty input and empty frames produce no records" {
  let decoder = @json_seq.Decoder::new(100).unwrap()
  assert_eq(decoder.feed(b"\x1e\x1e").unwrap().length(), 0)
  assert_eq(decoder.finish().unwrap().length(), 0)
}

///|
test "one-byte chunks preserve event order" {
  let input = b"\x1e{}\n\x1e{bad}\n\x1e[1]\n"
  let decoder = @json_seq.Decoder::new(100).unwrap()
  let events : Array[@json_seq.Event] = []
  for i = 0; i < input.length(); i = i + 1 {
    for event in decoder.feed(Bytes::from_array([input[i]])).unwrap() {
      events.push(event)
    }
  }
  for event in decoder.finish().unwrap() {
    events.push(event)
  }
  assert_eq(events.length(), 3)
  match events[0] {
    Value(value, 1) => assert_eq(value.stringify(), "{}")
    _ => fail("expected first value")
  }
  match events[1] {
    Error(InvalidJson, 5) => ()
    _ => fail("expected middle error")
  }
  match events[2] {
    Value(value, 12) => assert_eq(value.stringify(), "[1]")
    _ => fail("expected last value")
  }
}

///|
test "pretty-printed JSON may contain newlines" {
  let decoder = @json_seq.Decoder::new(100).unwrap()
  let _ = decoder.feed(b"\x1e{\n  \"x\": 1\n}\n").unwrap()
  match decoder.finish().unwrap()[0] {
    Value(value, 1) => assert_eq(value.stringify(), "{\"x\":1}")
    _ => fail("expected pretty-printed object")
  }
}

///|
test "encoder output decodes to the same scalar" {
  let original = @json.parse("123")
  let decoder = @json_seq.Decoder::new(100).unwrap()
  let _ = decoder.feed(@json_seq.encode(original)).unwrap()
  match decoder.finish().unwrap()[0] {
    Value(value, 1) => assert_eq(value, original)
    _ => fail("expected round-trip scalar")
  }
}
