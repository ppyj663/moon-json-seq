# Sources and originality

- Normative format and recovery rules: [RFC 7464](https://www.rfc-editor.org/rfc/rfc7464.html). This project implements the specification; it does not copy code from it.
- JSON Pointer token, array index, and URI fragment rules: [RFC 6901](https://www.rfc-editor.org/rfc/rfc6901.html). The parser, evaluator, and immutable edit utilities in this repository were implemented for this project.
- MoonBit project layout was generated with the locally installed `moon new` tool and then adapted. The generated Apache-2.0 license text is retained.
- [moonbitlang/jsonl](https://mooncakes.io/docs/moonbitlang/jsonl@0.2.1) handles JSON Lines. JSON Text Sequences use the distinct `RS JSON LF` framing of RFC 7464.
- JSON Lines conversion follows the [JSON Lines format description](https://jsonlines.org/), including UTF-8, one JSON value per line, and LF or CRLF line endings. Blank lines are reported as invalid. The converter code is original to this project.
- Searches on 2026-10-18 for `RFC 7464`, `json text sequence`, and `json-seq` in Mooncakes and publicly indexed GitHub results did not reveal a MoonBit package dedicated to RFC 7464. Search coverage is incomplete; this is not a claim that no such package exists.
