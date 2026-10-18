# moon-json-seq

A small MoonBit codec for [RFC 7464 JSON Text Sequences](https://www.rfc-editor.org/rfc/rfc7464.html). The wire format is `RS (0x1E) + UTF-8 JSON + LF (0x0A)` per value, with media type `application/json-seq`.

## Why use it?

JSON Lines uses a newline to delimit values. RFC 7464 uses a record separator, so pretty-printed JSON can span lines and a reader can resynchronize after a damaged record. This package provides byte framing around MoonBit's standard JSON parser for log processors, data importers, and command-line tools.

## What works

- `encode(Json) -> Bytes` writes one compact JSON record with RS and LF.
- `Decoder::new(max_record_bytes)` creates a bounded incremental decoder. The limit must be positive and counts bytes after RS, including LF.
- `feed(Bytes)` returns ordered `Value(Json, offset)` or `Error(message, offset)` events for records closed by a later RS. `finish()` closes the final record. Offsets are zero-based byte positions of the first byte after RS; a preamble error points to the first preamble byte.
- Invalid UTF-8, invalid JSON, incomplete top-level numbers/`true`/`false`/`null` without trailing JSON whitespace, and oversized records produce diagnostics. Parsing resumes at the next RS. Empty frames are ignored. A second `finish()` or `feed()` after `finish()` returns `Err`.

The decoder's retained framing state holds at most one configured record plus fixed state; a returned event array grows with the number and size of decoded values in that call. It does not read files itself; callers supply byte chunks from their own I/O layer. Diagnostics currently use stable short messages rather than a dedicated error enum. The parser uses MoonBit's standard JSON depth behavior. On a target with 32-bit `Int`, byte offsets can wrap for extremely long streams.

## Run locally

From this directory with MoonBit installed:

```sh
moon fmt --check
moon check --target wasm-gc --deny-warn
moon test --target wasm-gc
moon build --target wasm-gc
moon run cmd/main --target wasm-gc
```

The demo splits a valid object across two chunks, reports one malformed middle record, then recovers an array. Its expected output is:

```text
value at byte 1: {"ok":true}
error at byte 14: invalid JSON
value at byte 21: [1,2]
encoded byte length: 15
```

## Library use

Add `"ppyj663/json_seq" @seq` to your package imports after publication. Until then, this local module can be used through a MoonBit workspace or inspected directly. The API shape is:

```moonbit
let decoder = @seq.Decoder::new(1024 * 1024).unwrap()
let events = decoder.feed(input_chunk).unwrap()
// Process each @seq.Value(value, offset) or @seq.Error(message, offset).
let final_events = decoder.finish().unwrap()
let wire_bytes = @seq.encode(value)
```

`input_chunk` is a `Bytes` value and `value` is `Json`. Handle `Result` values instead of using `unwrap()` for untrusted application inputs.

## Scope and provenance

The code uses the MoonBit standard UTF-8 and JSON packages. It does not implement its own JSON grammar. See [sources](docs/SOURCES.md) for the specification and originality notes.

## License

Apache-2.0. See [LICENSE](LICENSE).
