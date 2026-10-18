///|
fn print_events(events : Array[@lib.Event]) -> Unit {
  for event in events {
    match event {
      @lib.Value(value, offset) =>
        println(
          "value at byte " + offset.to_string() + ": " + value.stringify(),
        )
      @lib.Error(kind, offset) =>
        println("error at byte " + offset.to_string() + ": " + kind.message())
    }
  }
}

///|
fn main raise {
  let decoder = @lib.Decoder::new(128).unwrap()
  // The first record is split across chunks; the middle record is damaged.
  let chunks = [b"\x1e{\"ok\":", b"true}\n\x1e{bad}\n\x1e[1,2]\n"]
  for chunk in chunks {
    print_events(decoder.feed(chunk).unwrap())
  }
  print_events(decoder.finish().unwrap())
  let encoded = @lib.encode(@json.parse("{\"demo\":true}"))
  println("encoded byte length: " + encoded.length().to_string())
}
