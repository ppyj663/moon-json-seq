# moon-json-seq

A MoonBit toolkit for [RFC 7464 JSON Text Sequences](https://www.rfc-editor.org/rfc/rfc7464.html). A canonical record is `RS (0x1E) + UTF-8 JSON + LF (0x0A)`; the media type is `application/json-seq`. The library works on caller-supplied byte chunks and has no file I/O dependency.

## Why use it?

JSON Lines uses a newline to delimit values. RFC 7464 uses a record separator, so pretty-printed JSON can span lines and a reader can resynchronize after a damaged record. This package provides framing, validation, conversion, search, repair, and record-level processing around MoonBit's standard JSON parser for log processors, data importers, and command-line tools.

## Capabilities

| Need | API |
| --- | --- |
| Encode or decode records | `encode`, `encode_many`, `Decoder`, `SequenceWriter` |
| Inspect framing and validity | `FrameScanner`, `inspect_frame`, `SequenceValidator` |
| Recover useful records | `SequenceRepairer` with preserve or canonicalize mode |
| Convert JSON Lines | `JsonLinesToSequence`, `SequenceToJsonLines` |
| Locate values inside JSON | `JsonPointer` with RFC 6901 string and URI fragment forms |
| Edit parsed JSON immutably | `JsonPointer::replace`, `JsonPointer::remove` |
| Filter and project records | `QueryPredicate`, `SequenceQuery` |
| Find positions and inspect structure | `SequenceIndex`, `analyze_json`, `SequenceShapeAnalyzer` |
| Extract, sample, deduplicate, or partition | `SequenceSlicer`, `SequenceSampler`, `SequenceDeduplicator`, `SequenceSegmenter` |

`feed(Bytes)` returns results for complete records encountered so far; `finish()` closes a final record without a later RS. Unless a type's documentation says otherwise, byte offsets are zero-based and `start` is the first byte after RS; `end` is exclusive. An invalid record does not stop parsing of later records. Empty frames are ignored. Feeding after `finish()`, or finishing twice, returns `Err`.

The scanner retains at most the configured record body size; oversized input is discarded until the next RS. Returned event arrays grow with the number of completed records in a call. Some operations deliberately retain more state: `SequenceIndex` keeps one entry per frame, and global deduplication keeps distinct serialized values. `SequenceWriter` materializes one encoded record before checking its configured limit. The parser uses MoonBit's standard JSON depth behavior. Byte offsets use 32-bit `Int` and can wrap for extremely long streams.

## Run locally

From this directory with MoonBit installed:

```sh
moon fmt --check
moon check --target wasm-gc --deny-warn
moon test --target wasm-gc --deny-warn
moon build --target wasm-gc
moon run cmd/main --target wasm-gc
moon check --target native --deny-warn
moon test --target native --deny-warn
moon build --target native
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
// Process each @seq.Value(value, offset) or @seq.Error(kind, offset).
let final_events = decoder.finish().unwrap()
let wire_bytes = @seq.encode(value)

let pointer = @seq.JsonPointer::parse("/user/id").unwrap()
let query = @seq.SequenceQuery::new(
  1024 * 1024,
  @seq.QueryPredicate::has(pointer),
  Some(pointer),
).unwrap()
let selected = query.feed(input_chunk).unwrap()
let final_selected = query.finish().unwrap()
```

`input_chunk` is a `Bytes` value and `value` is `Json`. Handle `Result` values instead of using `unwrap()` for untrusted application inputs. A consumer must pass every chunk to the same stateful instance and call `finish()` exactly once. The snippet shows separate operations; use fresh input streams for each instance.

For JSON Lines input, create `JsonLinesToSequence::new(max_line_bytes)`, pass each chunk to `feed`, consume each batch's `records` and `issues`, and call `finish`. For repair, `SequenceRepairer::new(max_record_bytes, RepairMode::canonicalize())` emits complete valid records and reports dropped spans. For output chunking, `SequenceWriter::new(max_chunk_bytes, max_record_bytes)` returns bounded chunks from `push`, with the last partial chunk from `finish`.

JSON Pointer follows [RFC 6901](https://www.rfc-editor.org/rfc/rfc6901.html) for string tokens, `~0`/`~1` escapes, array indices, and URI fragments. Its `remove` method is a project utility, not a JSON Patch implementation. MoonBit's JSON parser has already materialized objects before pointer evaluation; duplicate object keys cannot be distinguished there. Global deduplication compares compact serializer output, so differently ordered object keys may remain distinct.

## Scope and provenance

The code uses the MoonBit standard UTF-8 and JSON packages. It does not implement its own JSON grammar or file I/O. See [sources](docs/SOURCES.md) for the specifications and originality notes.

## License

Apache-2.0. See [LICENSE](LICENSE).
