///|
fn replace_pointer_path(
  current : Json,
  tokens : Array[String],
  position : Int,
  replacement : Json,
) -> Result[Json, PointerFailure] {
  if position == tokens.length() {
    return Ok(replacement)
  }
  let token = tokens[position]
  match current {
    Object(members) =>
      match members.get(token) {
        None => Err(MissingMember(position))
        Some(child) =>
          match replace_pointer_path(child, tokens, position + 1, replacement) {
            Err(failure) => Err(failure)
            Ok(updated) => {
              let copy = Map::from_iter(members.iter())
              copy.set(token, updated)
              Ok(@json.to_json(copy))
            }
          }
      }
    Array(values) =>
      match pointer_array_index(token) {
        None => Err(InvalidArrayIndex(position))
        Some(index) =>
          match values.get(index) {
            None => Err(ArrayIndexOutOfBounds(position))
            Some(child) =>
              match
                replace_pointer_path(child, tokens, position + 1, replacement) {
                Err(failure) => Err(failure)
                Ok(updated) => {
                  let copy : Array[Json] = []
                  for value in values {
                    copy.push(value)
                  }
                  copy[index] = updated
                  Ok(@json.to_json(copy))
                }
              }
          }
      }
    _ => Err(ScalarHasNoChildren(position))
  }
}

///|
/// Return a new JSON tree with an existing pointer target replaced. The
/// original tree is not mutated; missing paths return a typed failure.
pub fn JsonPointer::replace(
  self : JsonPointer,
  root : Json,
  replacement : Json,
) -> Result[Json, PointerFailure] {
  replace_pointer_path(root, self.tokens, 0, replacement)
}

///|
fn remove_pointer_path(
  current : Json,
  tokens : Array[String],
  position : Int,
) -> Result[Json, PointerFailure] {
  let token = tokens[position]
  let last = position + 1 == tokens.length()
  match current {
    Object(members) =>
      match members.get(token) {
        None => Err(MissingMember(position))
        Some(child) => {
          let copy = Map::from_iter(members.iter())
          if last {
            copy.remove(token)
            Ok(@json.to_json(copy))
          } else {
            match remove_pointer_path(child, tokens, position + 1) {
              Err(failure) => Err(failure)
              Ok(updated) => {
                copy.set(token, updated)
                Ok(@json.to_json(copy))
              }
            }
          }
        }
      }
    Array(values) =>
      match pointer_array_index(token) {
        None => Err(InvalidArrayIndex(position))
        Some(index) =>
          match values.get(index) {
            None => Err(ArrayIndexOutOfBounds(position))
            Some(child) => {
              let copy : Array[Json] = []
              if last {
                for i = 0; i < values.length(); i = i + 1 {
                  if i != index {
                    copy.push(values[i])
                  }
                }
                Ok(@json.to_json(copy))
              } else {
                match remove_pointer_path(child, tokens, position + 1) {
                  Err(failure) => Err(failure)
                  Ok(updated) => {
                    for i = 0; i < values.length(); i = i + 1 {
                      if i == index {
                        copy.push(updated)
                      } else {
                        copy.push(values[i])
                      }
                    }
                    Ok(@json.to_json(copy))
                  }
                }
              }
            }
          }
      }
    _ => Err(ScalarHasNoChildren(position))
  }
}

///|
/// Return a new JSON tree without an existing object member or array item.
/// Removing the root is undefined and returns a plain input error.
pub fn JsonPointer::remove(
  self : JsonPointer,
  root : Json,
) -> Result[Json, String] {
  if self.tokens.is_empty() {
    return Err("cannot remove the root JSON value")
  }
  match remove_pointer_path(root, self.tokens, 0) {
    Ok(updated) => Ok(updated)
    Err(failure) => Err(failure.message())
  }
}
