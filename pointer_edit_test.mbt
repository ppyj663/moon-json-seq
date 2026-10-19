///|
test "pointer replacement leaves original JSON untouched" {
  let original = @json.parse("{\"a\":[1,{\"b\":2}]}")
  let pointer = @json_seq.JsonPointer::parse("/a/1/b").unwrap()
  let updated = pointer.replace(original, @json.parse("3")).unwrap()
  assert_eq(updated.stringify(), "{\"a\":[1,{\"b\":3}]}")
  assert_eq(original.stringify(), "{\"a\":[1,{\"b\":2}]}")
  assert_eq(
    @json_seq.JsonPointer::root()
    .replace(original, @json.parse("null"))
    .unwrap()
    .stringify(),
    "null",
  )
}

///|
test "pointer removal handles object members and array positions" {
  let original = @json.parse("{\"a\":[1,2,3],\"b\":true}")
  let item = @json_seq.JsonPointer::parse("/a/1").unwrap()
  let removed = item.remove(original).unwrap()
  assert_eq(removed.stringify(), "{\"a\":[1,3],\"b\":true}")
  let field = @json_seq.JsonPointer::parse("/b").unwrap()
  assert_eq(field.remove(removed).unwrap().stringify(), "{\"a\":[1,3]}")
  assert_true(@json_seq.JsonPointer::root().remove(original) is Err(_))
  assert_eq(original.stringify(), "{\"a\":[1,2,3],\"b\":true}")
}

///|
test "pointer edits reject missing or invalid targets" {
  let root = @json.parse("[1]")
  assert_true(
    @json_seq.JsonPointer::parse("/-").unwrap().replace(root, @json.parse("2"))
    is Err(_),
  )
  assert_true(
    @json_seq.JsonPointer::parse("/2").unwrap().remove(root) is Err(_),
  )
  assert_true(
    @json_seq.JsonPointer::parse("/0/a").unwrap().remove(root) is Err(_),
  )
}
