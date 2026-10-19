///|
/// A bounded output chunker for canonical RFC 7464 records. Chunk boundaries
/// may occur inside a JSON record; concatenating chunks reconstructs the
/// exact encoded stream.
pub struct SequenceWriter {
  max_chunk_bytes : Int
  max_record_bytes : Int
  mut pending : Array[Byte]
  mut values_written : Int
  mut bytes_written : Int
  mut chunks_emitted : Int
  mut finished : Bool
}

///|
/// Both limits must be positive. `max_record_bytes` counts the JSON body and
/// its trailing LF, excluding the leading RS.
pub fn SequenceWriter::new(
  max_chunk_bytes : Int,
  max_record_bytes : Int,
) -> Result[SequenceWriter, String] {
  if max_chunk_bytes <= 0 {
    return Err("max_chunk_bytes must be positive")
  }
  if max_record_bytes <= 0 {
    return Err("max_record_bytes must be positive")
  }
  Ok({
    max_chunk_bytes,
    max_record_bytes,
    pending: [],
    values_written: 0,
    bytes_written: 0,
    chunks_emitted: 0,
    finished: false,
  })
}

///|
pub fn SequenceWriter::values_written(self : SequenceWriter) -> Int {
  self.values_written
}

///|
pub fn SequenceWriter::bytes_written(self : SequenceWriter) -> Int {
  self.bytes_written
}

///|
pub fn SequenceWriter::chunks_emitted(self : SequenceWriter) -> Int {
  self.chunks_emitted
}

///|
pub fn SequenceWriter::pending_bytes(self : SequenceWriter) -> Int {
  self.pending.length()
}

///|
pub fn SequenceWriter::is_finished(self : SequenceWriter) -> Bool {
  self.finished
}

///|
pub fn SequenceWriter::max_chunk_bytes(self : SequenceWriter) -> Int {
  self.max_chunk_bytes
}

///|
pub fn SequenceWriter::max_record_bytes(self : SequenceWriter) -> Int {
  self.max_record_bytes
}

///|
fn SequenceWriter::emit_pending(
  self : SequenceWriter,
  chunks : Array[Bytes],
) -> Unit {
  if !self.pending.is_empty() {
    chunks.push(Bytes::from_array(self.pending))
    self.pending = []
    self.chunks_emitted = self.chunks_emitted + 1
  }
}

///|
fn SequenceWriter::append_bytes(
  self : SequenceWriter,
  bytes : Bytes,
  chunks : Array[Bytes],
) -> Unit {
  for i = 0; i < bytes.length(); i = i + 1 {
    self.pending.push(bytes[i])
    self.bytes_written = self.bytes_written + 1
    if self.pending.length() == self.max_chunk_bytes {
      self.emit_pending(chunks)
    }
  }
}

///|
/// Encode one value. Failure leaves the writer unchanged. Returned chunks
/// are ready to write to any byte sink in their original order.
pub fn SequenceWriter::push(
  self : SequenceWriter,
  value : Json,
) -> Result[Array[Bytes], String] {
  if self.finished {
    return Err("writer already finished")
  }
  let bytes = encode(value)
  if bytes.length() - 1 > self.max_record_bytes {
    return Err("record exceeds max_record_bytes")
  }
  let chunks : Array[Bytes] = []
  self.append_bytes(bytes, chunks)
  self.values_written = self.values_written + 1
  Ok(chunks)
}

///|
/// Flush a partial chunk without closing the writer. Empty buffers return
/// `None`, so callers can flush safely after any number of writes.
pub fn SequenceWriter::flush(self : SequenceWriter) -> Result[Bytes?, String] {
  if self.finished {
    return Err("writer already finished")
  }
  if self.pending.is_empty() {
    return Ok(None)
  }
  let chunks : Array[Bytes] = []
  self.emit_pending(chunks)
  Ok(Some(chunks[0]))
}

///|
/// Finish the stream and return any trailing partial chunk. A writer cannot
/// accept further values or be finished twice.
pub fn SequenceWriter::finish(self : SequenceWriter) -> Result[Bytes?, String] {
  if self.finished {
    return Err("writer already finished")
  }
  let tail = self.flush()
  self.finished = true
  tail
}

///|
/// Encode a batch with no output chunking. The result grows with all input
/// values; use `SequenceWriter` when the caller needs bounded output chunks.
pub fn encode_many(values : Array[Json]) -> Bytes {
  let output : Array[Byte] = []
  for value in values {
    let record = encode(value)
    for i = 0; i < record.length(); i = i + 1 {
      output.push(record[i])
    }
  }
  Bytes::from_array(output)
}

///|
/// Encode one value while checking a bound on the body plus LF, excluding RS.
pub fn encode_with_limit(
  value : Json,
  max_record_bytes : Int,
) -> Result[Bytes, String] {
  if max_record_bytes <= 0 {
    return Err("max_record_bytes must be positive")
  }
  let record = encode(value)
  if record.length() - 1 > max_record_bytes {
    Err("record exceeds max_record_bytes")
  } else {
    Ok(record)
  }
}
