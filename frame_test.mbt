///|
test "raw scanner tracks exact exclusive offsets" {
  let scanner = @json_seq.FrameScanner::new(32).unwrap()
  let first = scanner.feed(b"\x1e{\"a\":").unwrap()
  assert_eq(first.length(), 0)
  let next = scanner.feed(b"1}\n\x1e[2]").unwrap()
  assert_eq(next.length(), 1)
  match next[0] {
    DataFrame(frame) => {
      assert_eq(frame.start, 1)
      assert_eq(frame.end, 9)
      assert_eq(@utf8.decode(frame.bytes), "{\"a\":1}\n")
    }
    _ => fail("expected raw frame")
  }
  let final_events = scanner.finish().unwrap()
  match final_events[0] {
    DataFrame(frame) => {
      assert_eq(frame.start, 10)
      assert_eq(frame.end, 13)
      assert_eq(@utf8.decode(frame.bytes), "[2]")
    }
    _ => fail("expected final frame")
  }
}

///|
test "raw scanner records preamble span" {
  let scanner = @json_seq.FrameScanner::new(16).unwrap()
  let events = scanner.feed(b"xx\x1e{}\n").unwrap()
  assert_eq(events.length(), 1)
  match events[0] {
    PreambleBytes(0, 2) => ()
    _ => fail("expected preamble span")
  }
  match scanner.finish().unwrap()[0] {
    DataFrame(frame) => {
      assert_eq(frame.start, 3)
      assert_eq(frame.end, 6)
    }
    _ => fail("expected data frame")
  }
}

///|
test "raw scanner skips empty frames" {
  let scanner = @json_seq.FrameScanner::new(16).unwrap()
  let events = scanner.feed(b"\x1e\x1e\x1e{}\n\x1e").unwrap()
  assert_eq(events.length(), 1)
  match events[0] {
    DataFrame(frame) => {
      assert_eq(frame.start, 3)
      assert_eq(frame.end, 6)
    }
    _ => fail("expected one nonempty frame")
  }
  assert_eq(scanner.finish().unwrap().length(), 0)
}

///|
test "raw scanner accepts exact limit" {
  let scanner = @json_seq.FrameScanner::new(3).unwrap()
  let _ = scanner.feed(b"\x1e{}\n").unwrap()
  match scanner.finish().unwrap()[0] {
    DataFrame(frame) => assert_eq(frame.bytes.length(), 3)
    _ => fail("expected frame at exact limit")
  }
}

///|
test "raw scanner reports overflow and recovers" {
  let scanner = @json_seq.FrameScanner::new(3).unwrap()
  let events = scanner.feed(b"\x1e1234\x1e[]\n").unwrap()
  match events[0] {
    OversizedFrame(1, 5) => ()
    _ => fail("expected oversized span")
  }
  match scanner.finish().unwrap()[0] {
    DataFrame(frame) => {
      assert_eq(frame.start, 6)
      assert_eq(frame.end, 9)
      assert_eq(@utf8.decode(frame.bytes), "[]\n")
    }
    _ => fail("expected recovery frame")
  }
}

///|
test "raw scanner reports a stream with no separator" {
  let scanner = @json_seq.FrameScanner::new(16).unwrap()
  let _ = scanner.feed(b"noise").unwrap()
  match scanner.finish().unwrap()[0] {
    PreambleBytes(0, 5) => ()
    _ => fail("expected preamble only")
  }
}

///|
test "raw scanner keeps offset across empty chunks" {
  let scanner = @json_seq.FrameScanner::new(16).unwrap()
  assert_eq(scanner.offset(), 0)
  assert_eq(scanner.feed(b"").unwrap().length(), 0)
  assert_eq(scanner.offset(), 0)
  let _ = scanner.feed(b"\x1e{").unwrap()
  assert_eq(scanner.offset(), 2)
  assert_eq(scanner.pending_bytes(), 1)
  let _ = scanner.feed(b"}\n").unwrap()
  assert_eq(scanner.offset(), 4)
  assert_eq(scanner.pending_bytes(), 3)
  assert_eq(scanner.max_record_bytes(), 16)
}

///|
test "raw scanner rejects invalid limit and reuse" {
  assert_true(@json_seq.FrameScanner::new(0) is Err(_))
  assert_true(@json_seq.FrameScanner::new(-1) is Err(_))
  let scanner = @json_seq.FrameScanner::new(1).unwrap()
  let _ = scanner.finish().unwrap()
  assert_true(scanner.is_finished())
  assert_true(scanner.finish() is Err(_))
  assert_true(scanner.feed(b"x") is Err(_))
}
