# moon-json-seq

A MoonBit implementation of RFC 7464 JSON Text Sequences. This is a new, independent project under development.

The core will frame UTF-8 JSON values using record separator (`0x1E`) and line feed (`0x0A`), decode arbitrary input chunks, and report malformed records while continuing at the next separator.

The runnable demo and verified commands will be documented here as they are implemented.

## License

Apache-2.0. See [LICENSE](LICENSE).
