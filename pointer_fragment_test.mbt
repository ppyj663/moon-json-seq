///|
test "JSON Pointer URI fragment round trip" {
  let pointer = @json_seq.JsonPointer::parse("/中/a~1b/% x").unwrap()
  let fragment = pointer.to_fragment()
  assert_eq(fragment, "#/%E4%B8%AD/a~1b/%25%20x")
  assert_eq(
    @json_seq.JsonPointer::parse_fragment(fragment).unwrap().to_text(),
    pointer.to_text(),
  )
  assert_eq(@json_seq.JsonPointer::parse_fragment("#").unwrap().depth(), 0)
  assert_eq(
    @json_seq.JsonPointer::parse_fragment("#/a%2Fb").unwrap().to_text(),
    "/a/b",
  )
}

///|
test "JSON Pointer URI fragment rejects bad encoding" {
  assert_true(@json_seq.JsonPointer::parse_fragment("/a") is Err(_))
  assert_true(@json_seq.JsonPointer::parse_fragment("#/%") is Err(_))
  assert_true(@json_seq.JsonPointer::parse_fragment("#/%GG") is Err(_))
  assert_true(@json_seq.JsonPointer::parse_fragment("#/%FF") is Err(_))
}
