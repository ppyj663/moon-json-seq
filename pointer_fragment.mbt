///|
fn fragment_hex_value(byte : Byte) -> Int? {
  if byte >= 0x30 && byte <= 0x39 {
    Some(byte.to_int() - 0x30)
  } else if byte >= 0x41 && byte <= 0x46 {
    Some(byte.to_int() - 0x41 + 10)
  } else if byte >= 0x61 && byte <= 0x66 {
    Some(byte.to_int() - 0x61 + 10)
  } else {
    None
  }
}

///|
fn fragment_hex_digit(value : Int) -> Byte {
  if value < 10 {
    (value + 0x30).to_byte()
  } else {
    (value - 10 + 0x41).to_byte()
  }
}

///|
fn fragment_safe_byte(byte : Byte) -> Bool {
  (byte >= 0x41 && byte <= 0x5a) ||
  (byte >= 0x61 && byte <= 0x7a) ||
  (byte >= 0x30 && byte <= 0x39) ||
  byte == 0x2d ||
  byte == 0x2e ||
  byte == 0x5f ||
  byte == 0x7e ||
  byte == 0x2f
}

///|
/// Parse the RFC 6901 URI fragment representation, including percent-encoded
/// UTF-8. `#` alone selects the root.
pub fn JsonPointer::parse_fragment(
  fragment : String,
) -> Result[JsonPointer, String] {
  let bytes = @utf8.encode(fragment)
  if bytes.is_empty() || bytes[0] != 0x23 {
    return Err("JSON Pointer fragment must begin with '#'")
  }
  let decoded : Array[Byte] = []
  let mut i = 1
  while i < bytes.length() {
    if bytes[i] == 0x25 {
      if i + 2 >= bytes.length() {
        return Err("incomplete percent escape in JSON Pointer fragment")
      }
      let high = fragment_hex_value(bytes[i + 1])
      let low = fragment_hex_value(bytes[i + 2])
      match (high, low) {
        (Some(a), Some(b)) => decoded.push((a * 16 + b).to_byte())
        _ => return Err("invalid percent escape in JSON Pointer fragment")
      }
      i = i + 3
    } else {
      decoded.push(bytes[i])
      i = i + 1
    }
  }
  let text = @utf8.decode(Bytes::from_array(decoded)) catch {
    _ => return Err("invalid UTF-8 in JSON Pointer fragment")
  }
  JsonPointer::parse(text)
}

///|
/// Serialize a pointer as a URI fragment. Bytes outside a conservative
/// unreserved set (plus '/') are percent encoded using uppercase hex.
pub fn JsonPointer::to_fragment(self : JsonPointer) -> String {
  let text = @utf8.encode(self.to_text())
  let out : Array[Byte] = [0x23]
  for i = 0; i < text.length(); i = i + 1 {
    let byte = text[i]
    if fragment_safe_byte(byte) {
      out.push(byte)
    } else {
      let value = byte.to_int()
      out.push(0x25)
      out.push(fragment_hex_digit(value / 16))
      out.push(fragment_hex_digit(value % 16))
    }
  }
  @utf8.decode(Bytes::from_array(out)) catch {
    _ => abort("JSON Pointer fragment bytes were ASCII")
  }
}
