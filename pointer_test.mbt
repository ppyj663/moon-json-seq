///|
test "JSON Pointer resolves RFC 6901 examples" {
  let document = @json.parse(
    "{\"foo\":[\"bar\",\"baz\"],\"\":0,\"a/b\":1,\"m~n\":8}",
  )
  assert_eq(@json_seq.resolve_pointer("", document).unwrap(), document)
  assert_eq(
    @json_seq.resolve_pointer("/foo/0", document).unwrap().stringify(),
    "\"bar\"",
  )
  assert_eq(@json_seq.resolve_pointer("/", document).unwrap().stringify(), "0")
  assert_eq(
    @json_seq.resolve_pointer("/a~1b", document).unwrap().stringify(),
    "1",
  )
  assert_eq(
    @json_seq.resolve_pointer("/m~0n", document).unwrap().stringify(),
    "8",
  )
}

///|
test "JSON Pointer parses and serializes escaped and Unicode tokens" {
  let pointer = @json_seq.JsonPointer::parse("/中/~01/").unwrap()
  assert_eq(pointer.depth(), 3)
  assert_eq(pointer.token(0), Some("中"))
  assert_eq(pointer.token(1), Some("~1"))
  assert_eq(pointer.token(2), Some(""))
  assert_eq(pointer.to_text(), "/中/~01/")
  let child = pointer.child("a/b~c")
  assert_eq(child.to_text(), "/中/~01//a~1b~0c")
  assert_eq(child.parent().unwrap().to_text(), pointer.to_text())
  assert_true(@json_seq.JsonPointer::root().parent() is None)
}

///|
test "JSON Pointer rejects malformed syntax and array indices" {
  assert_true(@json_seq.JsonPointer::parse("a") is Err(_))
  assert_true(@json_seq.JsonPointer::parse("/~") is Err(_))
  assert_true(@json_seq.JsonPointer::parse("/~2") is Err(_))
  let array = @json.parse("[0,1]")
  assert_true(@json_seq.resolve_pointer("/01", array) is Err(_))
  assert_true(@json_seq.resolve_pointer("/-", array) is Err(_))
  assert_true(@json_seq.resolve_pointer("/2147483648", array) is Err(_))
  assert_true(@json_seq.resolve_pointer("/2", array) is Err(_))
}

///|
test "JSON Pointer identifies the failed segment" {
  let pointer = @json_seq.JsonPointer::parse("/a/b").unwrap()
  let value = @json.parse("{\"a\":[]}")
  match pointer.resolve(value) {
    Err(failure) => {
      assert_eq(failure.segment(), 1)
      assert_eq(failure.message(), "invalid array index token")
    }
    Ok(_) => fail("expected resolution failure")
  }
  assert_true(@json_seq.resolve_pointer("/a", @json.parse("null")) is Err(_))
}
