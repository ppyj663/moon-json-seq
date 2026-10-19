///|
test "JSON shape measures nested values and UTF-8 bytes" {
  let shape = @json_seq.analyze_json(
    @json.parse("{\"中\":[1,true,null,{\"s\":\"é\"}]}"),
  )
  assert_eq(shape.nodes, 7)
  assert_eq(shape.max_depth, 3)
  assert_eq(shape.objects, 2)
  assert_eq(shape.object_members, 2)
  assert_eq(shape.arrays, 1)
  assert_eq(shape.array_items, 4)
  assert_eq(shape.strings, 1)
  assert_eq(shape.string_utf8_bytes, 6)
  assert_eq(shape.numbers, 1)
  assert_eq(shape.booleans, 1)
  assert_eq(shape.nulls, 1)
}

///|
test "sequence shape accumulates valid records and issues" {
  let analyzer = @json_seq.SequenceShapeAnalyzer::new(100).unwrap()
  let first = analyzer.feed(b"xx\x1e[1,2]\n\x1e{bad}").unwrap()
  assert_eq(first.issues.length(), 1)
  assert_eq(first.records.length(), 1)
  assert_eq(first.records[0].record_number, 1)
  let second = analyzer.feed(b"\x1e{\"a\":true}\n").unwrap()
  assert_eq(second.issues.length(), 1)
  let last = analyzer.finish().unwrap()
  assert_eq(last.records.length(), 1)
  assert_eq(last.records[0].record_number, 3)
  assert_eq(analyzer.records_analyzed(), 2)
  assert_eq(analyzer.shape().nodes, 5)
  assert_eq(analyzer.validation().invalid_records(), 1)
  assert_true(analyzer.feed(b"x") is Err(_))
}

///|
test "shape analyzer rejects invalid limit" {
  assert_true(@json_seq.SequenceShapeAnalyzer::new(0) is Err(_))
}
