import gleam/dict
import gleam/dynamic
import gleam/json
import spillway/connect_document
import spillway/socketio
import startest/expect
import windsock

pub fn classify_engine_ping_test() {
  socketio.classify("2") |> expect.to_equal(socketio.EnginePing)
}

pub fn classify_engine_pong_test() {
  socketio.classify("3") |> expect.to_equal(socketio.EnginePong)
}

pub fn classify_socket_connect_test() {
  socketio.classify("40") |> expect.to_equal(socketio.SocketConnect)
}

pub fn classify_fluid_event_test() {
  // case instead of let assert: startest's rescue wraps let-assert values
  // in Ok(), so non-Ok patterns never match.
  case socketio.classify("42[\"connect_document\",{\"id\":\"doc\"}]") {
    socketio.FluidEvent("connect_document", [_payload]) -> Nil
    _ -> panic as "expected FluidEvent(connect_document, [payload])"
  }
}

pub fn classify_unrecognized_test() {
  case socketio.classify("garbage") {
    socketio.Unrecognized(_reason) -> Nil
    _ -> panic as "expected Unrecognized"
  }
}

pub fn encode_open_contains_sid_and_prefix_test() {
  let packet = socketio.encode_open("abc123", 25_000, 20_000, 1_000_000)
  packet
  |> expect.to_equal(
    "0{\"sid\":\"abc123\",\"upgrades\":[],\"pingInterval\":25000,\"pingTimeout\":20000,\"maxPayload\":1000000}",
  )
}

pub fn encode_connect_ack_test() {
  socketio.encode_connect_ack("abc123")
  |> expect.to_equal("40{\"sid\":\"abc123\"}")
}

pub fn encode_pong_matches_windsock_test() {
  socketio.encode_pong() |> expect.to_equal(windsock.pong)
}

pub fn encode_op_shape_test() {
  let frame =
    socketio.encode_op(json.string("doc-1"), json.preprocessed_array([]))
  case socketio.classify(frame) {
    socketio.FluidEvent("op", [decoded_doc_id, decoded_messages]) -> {
      decoded_doc_id |> expect.to_equal(dynamic.string("doc-1"))
      decoded_messages |> expect.to_equal(dynamic.list([]))
    }
    _ -> panic as "expected FluidEvent(op, [documentId, messages])"
  }
}

pub fn connect_document_parse_request_ok_test() {
  let payload =
    dict.from_list([
      #("tenantId", dynamic.string("tenant-a")),
      #("id", dynamic.string("doc-a")),
      #("token", dynamic.string("token-a")),
    ])

  connect_document.parse_request(payload)
  |> expect.to_equal(
    Ok(connect_document.ConnectRequest("tenant-a", "doc-a", "token-a")),
  )
}

pub fn connect_document_parse_request_missing_field_test() {
  let payload =
    dict.from_list([
      #("tenantId", dynamic.string("tenant-a")),
      #("token", dynamic.string("token-a")),
    ])

  connect_document.parse_request(payload)
  |> expect.to_equal(Error(connect_document.MissingField("id")))
}

pub fn connect_document_validate_mode_scope_write_with_scope_test() {
  let payload = dict.from_list([#("mode", dynamic.string("write"))])
  connect_document.validate_mode_scope(payload, ["doc:read", "doc:write"])
  |> expect.to_equal(Ok(Nil))
}

pub fn connect_document_validate_mode_scope_write_without_scope_test() {
  let payload = dict.from_list([#("mode", dynamic.string("write"))])
  connect_document.validate_mode_scope(payload, ["doc:read"])
  |> expect.to_equal(Error(connect_document.WriteModeWithoutWriteScope))
}

pub fn connect_document_validate_mode_scope_absent_mode_test() {
  let payload = dict.new()
  connect_document.validate_mode_scope(payload, [])
  |> expect.to_equal(Ok(Nil))
}

pub fn connect_document_read_write_scope_strings_test() {
  connect_document.read_scope() |> expect.to_equal("doc:read")
  connect_document.write_scope() |> expect.to_equal("doc:write")
}
