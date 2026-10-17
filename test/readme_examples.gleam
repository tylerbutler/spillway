//// Keep the README and website examples executable.

import gleam/dynamic/decode
import gleam/json
import gleam/result
import spillway/rest
import spillway/sequencing
import spillway/signals
import spillway/socketio

pub fn sequence() {
  let state =
    sequencing.new()
    |> sequencing.client_join("client-7", 0)

  sequencing.assign_sequence_number(state, "client-7", 1, 0)
}

pub fn signal_json(text: String) {
  use signal <- result.try(json.parse(text, signals.decoder(decode.string)))
  Ok(signals.normalized_to_json(signal, json.string))
}

pub fn response_json() {
  rest.format_document_response("doc-1", "tenant-1", 5)
  |> json.to_string
}

pub fn signal_frame() {
  socketio.encode_signal(json.object([#("content", json.string("hello"))]))
}

pub fn run() -> Nil {
  let assert Ok(sequencing.SequenceAssignment(_, 1, 0)) = sequence()
  let assert Ok(signal) = signal_json("{\"content\":\"hello\"}")
  let assert Ok("hello") =
    json.parse(json.to_string(signal), decode.at(["content"], decode.string))
  assert response_json()
    == "{\"id\":\"doc-1\",\"tenantId\":\"tenant-1\",\"sequenceNumber\":5}"
  assert signal_frame() == "42[\"signal\",{\"content\":\"hello\"}]"
}
