///|
/// Errors from evaluating an RFC 6901 JSON Pointer. `segment` is zero based.
pub enum PointerFailure {
  MissingMember(Int)
  InvalidArrayIndex(Int)
  ArrayIndexOutOfBounds(Int)
  ScalarHasNoChildren(Int)
}

///|
pub fn PointerFailure::message(self : PointerFailure) -> String {
  match self {
    MissingMember(_) => "object member does not exist"
    InvalidArrayIndex(_) => "invalid array index token"
    ArrayIndexOutOfBounds(_) => "array index is out of bounds"
    ScalarHasNoChildren(_) => "scalar value has no child"
  }
}

///|
pub fn PointerFailure::segment(self : PointerFailure) -> Int {
  match self {
    MissingMember(index)
    | InvalidArrayIndex(index)
    | ArrayIndexOutOfBounds(index)
    | ScalarHasNoChildren(index) => index
  }
}

///|
/// Parsed JSON Pointer tokens. The empty pointer addresses the root value.
pub struct JsonPointer {
  tokens : Array[String]
}

///|
fn decode_pointer_token(bytes : Array[Byte]) -> Result[String, String] {
  let decoded : Array[Byte] = []
  let mut i = 0
  while i < bytes.length() {
    if bytes[i] == 0x7e {
      if i + 1 >= bytes.length() {
        return Err("trailing '~' in JSON Pointer")
      }
      match bytes[i + 1] {
        0x30 => decoded.push(0x7e)
        0x31 => decoded.push(0x2f)
        _ => return Err("invalid '~' escape in JSON Pointer")
      }
      i = i + 2
    } else {
      decoded.push(bytes[i])
      i = i + 1
    }
  }
  let token = @utf8.decode(Bytes::from_array(decoded)) catch {
    _ => return Err("invalid UTF-8 in JSON Pointer")
  }
  Ok(token)
}

///|
/// Parse the JSON string representation of RFC 6901. URI fragment pointers
/// such as `#/a` are not accepted by this constructor.
pub fn JsonPointer::parse(text : String) -> Result[JsonPointer, String] {
  if text == "" {
    return Ok({ tokens: [], })
  }
  let bytes = @utf8.encode(text)
  if bytes[0] != 0x2f {
    return Err("JSON Pointer must be empty or begin with '/'")
  }
  let tokens : Array[String] = []
  let mut part : Array[Byte] = []
  for i = 1; i < bytes.length(); i = i + 1 {
    if bytes[i] == 0x2f {
      match decode_pointer_token(part) {
        Ok(token) => tokens.push(token)
        Err(message) => return Err(message)
      }
      part = []
    } else {
      part.push(bytes[i])
    }
  }
  match decode_pointer_token(part) {
    Ok(token) => {
      tokens.push(token)
      Ok({ tokens, })
    }
    Err(message) => Err(message)
  }
}

///|
pub fn JsonPointer::root() -> JsonPointer {
  { tokens: [], }
}

///|
pub fn JsonPointer::depth(self : JsonPointer) -> Int {
  self.tokens.length()
}

///|
pub fn JsonPointer::token(self : JsonPointer, index : Int) -> String? {
  self.tokens.get(index)
}

///|
fn append_escaped_token(out : Array[Byte], token : String) -> Unit {
  let bytes = @utf8.encode(token)
  for i = 0; i < bytes.length(); i = i + 1 {
    match bytes[i] {
      0x7e => {
        out.push(0x7e)
        out.push(0x30)
      }
      0x2f => {
        out.push(0x7e)
        out.push(0x31)
      }
      byte => out.push(byte)
    }
  }
}

///|
pub fn JsonPointer::to_text(self : JsonPointer) -> String {
  let out : Array[Byte] = []
  for token in self.tokens {
    out.push(0x2f)
    append_escaped_token(out, token)
  }
  @utf8.decode(Bytes::from_array(out)) catch {
    _ => abort("JSON Pointer tokens were valid UTF-8")
  }
}

///|
pub fn JsonPointer::child(self : JsonPointer, token : String) -> JsonPointer {
  let tokens : Array[String] = []
  for item in self.tokens {
    tokens.push(item)
  }
  tokens.push(token)
  { tokens, }
}

///|
pub fn JsonPointer::parent(self : JsonPointer) -> JsonPointer? {
  if self.tokens.is_empty() {
    return None
  }
  let tokens : Array[String] = []
  for i = 0; i < self.tokens.length() - 1; i = i + 1 {
    tokens.push(self.tokens[i])
  }
  Some({ tokens, })
}

///|
fn pointer_array_index(token : String) -> Int? {
  let bytes = @utf8.encode(token)
  if bytes.is_empty() || (bytes.length() > 1 && bytes[0] == 0x30) {
    return None
  }
  let mut value = 0
  for i = 0; i < bytes.length(); i = i + 1 {
    let byte = bytes[i]
    if byte < 0x30 || byte > 0x39 {
      return None
    }
    let digit = byte.to_int() - 0x30
    if value > (2147483647 - digit) / 10 {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}

///|
/// Resolve a pointer against one parsed value. Missing members, invalid array
/// indices, and traversal through scalars are distinct failures.
pub fn JsonPointer::resolve(
  self : JsonPointer,
  root : Json,
) -> Result[Json, PointerFailure] {
  let mut current = root
  for i = 0; i < self.tokens.length(); i = i + 1 {
    let token = self.tokens[i]
    match current {
      Object(members) =>
        match members.get(token) {
          Some(value) => current = value
          None => return Err(MissingMember(i))
        }
      Array(values) =>
        match pointer_array_index(token) {
          None => return Err(InvalidArrayIndex(i))
          Some(index) =>
            match values.get(index) {
              Some(value) => current = value
              None => return Err(ArrayIndexOutOfBounds(i))
            }
        }
      _ => return Err(ScalarHasNoChildren(i))
    }
  }
  Ok(current)
}

///|
pub fn resolve_pointer(text : String, root : Json) -> Result[Json, String] {
  match JsonPointer::parse(text) {
    Err(message) => Err(message)
    Ok(pointer) =>
      match pointer.resolve(root) {
        Ok(value) => Ok(value)
        Err(failure) => Err(failure.message())
      }
  }
}
