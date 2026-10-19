///|
test "sequence query filters and projects matching values" {
  let id = @json_seq.JsonPointer::parse("/id").unwrap()
  let status = @json_seq.JsonPointer::parse("/status").unwrap()
  let predicate = @json_seq.QueryPredicate::equals(
    status,
    @json.parse("\"ok\""),
  )
  let query = @json_seq.SequenceQuery::new(100, predicate, Some(id)).unwrap()
  let a = query
    .feed(
      b"\x1e{\"id\":1,\"status\":\"ok\"}\n\x1e{\"id\":2,\"status\":\"bad\"}\n",
    )
    .unwrap()
  assert_eq(a.matches.length(), 1)
  assert_eq(a.matches[0].record_number, 1)
  assert_eq(@utf8.decode(a.matches[0].encoded), "\u001e1\n")
  let b = query.feed(b"\x1e{\"status\":\"ok\"}\n").unwrap()
  assert_eq(b.matches.length(), 0)
  let c = query.finish().unwrap()
  assert_eq(c.issues.length(), 1)
  assert_eq(c.issues[0].failure.message(), "object member does not exist")
  let summary = query.summary()
  assert_eq(summary.frames_seen, 3)
  assert_eq(summary.matched, 1)
  assert_eq(summary.filtered, 1)
  assert_eq(summary.missing_projection, 1)
  assert_true(query.feed(b"x") is Err(_))
}

///|
test "sequence query reports malformed input and resumes" {
  let query = @json_seq.SequenceQuery::new(
    10,
    @json_seq.QueryPredicate::all(),
    None,
  ).unwrap()
  let a = query.feed(b"bad\x1e{bad}\x1e{}\n").unwrap()
  assert_eq(a.issues.length(), 2)
  assert_eq(a.issues[0].record_number, 0)
  assert_eq(a.issues[1].failure.message(), "invalid JSON")
  let b = query.finish().unwrap()
  assert_eq(b.matches.length(), 1)
  assert_eq(b.matches[0].record_number, 2)
  assert_eq(query.summary().invalid, 1)
}

///|
test "query predicate kinds and pointer existence" {
  let object = @json.parse("{\"a\":1}")
  let array = @json.parse("[1]")
  let scalar = @json.parse("1")
  assert_true(@json_seq.QueryPredicate::objects().matches(object))
  assert_true(!@json_seq.QueryPredicate::objects().matches(array))
  assert_true(@json_seq.QueryPredicate::arrays().matches(array))
  assert_true(@json_seq.QueryPredicate::scalars().matches(scalar))
  assert_true(!@json_seq.QueryPredicate::scalars().matches(object))
  let pointer = @json_seq.JsonPointer::parse("/a").unwrap()
  assert_true(@json_seq.QueryPredicate::has(pointer).matches(object))
  assert_true(!@json_seq.QueryPredicate::has(pointer).matches(array))
}

///|
test "query rejects invalid record bound" {
  assert_true(
    @json_seq.SequenceQuery::new(0, @json_seq.QueryPredicate::all(), None)
    is Err(_),
  )
}
