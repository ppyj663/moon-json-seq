///|
test "chunked writer reconstructs canonical stream" {
  let values = [@json.parse("{}"), @json.parse("[1,2]"), @json.parse("\"中\"")]
  let writer = @json_seq.SequenceWriter::new(4, 100).unwrap()
  let chunks : Array[Bytes] = []
  for value in values {
    for chunk in writer.push(value).unwrap() {
      assert_true(chunk.length() <= 4)
      chunks.push(chunk)
    }
  }
  match writer.finish().unwrap() {
    Some(chunk) => {
      assert_true(chunk.length() <= 4)
      chunks.push(chunk)
    }
    None => ()
  }
  let assembled : Array[Byte] = []
  for chunk in chunks {
    for i = 0; i < chunk.length(); i = i + 1 {
      assembled.push(chunk[i])
    }
  }
  assert_eq(Bytes::from_array(assembled), @json_seq.encode_many(values))
  assert_eq(writer.values_written(), 3)
  assert_eq(writer.bytes_written(), @json_seq.encode_many(values).length())
  assert_eq(writer.chunks_emitted(), chunks.length())
  assert_eq(writer.pending_bytes(), 0)
  assert_true(writer.is_finished())
}

///|
test "writer rejects oversize without changing state" {
  let writer = @json_seq.SequenceWriter::new(3, 3).unwrap()
  assert_true(writer.push(@json.parse("1234")) is Err(_))
  assert_eq(writer.values_written(), 0)
  assert_eq(writer.bytes_written(), 0)
  assert_eq(writer.pending_bytes(), 0)
  let emitted = writer.push(@json.parse("{}")).unwrap()
  assert_eq(emitted.length(), 1)
  assert_eq(writer.values_written(), 1)
  assert_eq(writer.bytes_written(), 4)
}

///|
test "writer flush and finish lifecycle" {
  let writer = @json_seq.SequenceWriter::new(100, 100).unwrap()
  assert_true(writer.flush().unwrap() is None)
  assert_true(writer.finish().unwrap() is None)
  assert_true(writer.push(@json.parse("null")) is Err(_))
  assert_true(writer.flush() is Err(_))
  assert_true(writer.finish() is Err(_))
}

///|
test "writer flush returns partial chunk and remains open" {
  let writer = @json_seq.SequenceWriter::new(20, 20).unwrap()
  assert_eq(writer.push(@json.parse("true")).unwrap().length(), 0)
  match writer.flush().unwrap() {
    Some(bytes) => assert_eq(bytes, @json_seq.encode(@json.parse("true")))
    None => fail("expected flushed bytes")
  }
  assert_eq(writer.pending_bytes(), 0)
  assert_eq(writer.chunks_emitted(), 1)
  assert_eq(writer.push(@json.parse("false")).unwrap().length(), 0)
  match writer.finish().unwrap() {
    Some(bytes) => assert_eq(bytes, @json_seq.encode(@json.parse("false")))
    None => fail("expected trailing bytes")
  }
}

///|
test "writer accepts exact record limit and rejects invalid limits" {
  assert_true(@json_seq.SequenceWriter::new(0, 1) is Err(_))
  assert_true(@json_seq.SequenceWriter::new(1, 0) is Err(_))
  let exact = @json_seq.encode_with_limit(@json.parse("null"), 5).unwrap()
  assert_eq(exact, @json_seq.encode(@json.parse("null")))
  assert_true(@json_seq.encode_with_limit(@json.parse("null"), 4) is Err(_))
  assert_true(@json_seq.encode_with_limit(@json.parse("null"), 0) is Err(_))
}
