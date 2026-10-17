import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/option.{None, Some}
import signet/types as token
import spillway/connect_document
import spillway/socketio
import spillway/types
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
      decode.run(decoded_doc_id, decode.string) |> expect.to_equal(Ok("doc-1"))
      decode.run(decoded_messages, decode.list(decode.string))
      |> expect.to_equal(Ok([]))
    }
    _ -> panic as "expected FluidEvent(op, [documentId, messages])"
  }
}

pub fn connect_document_parse_request_ok_test() {
  let assert Ok(payload) =
    json.parse(
      "{\"tenantId\":\"tenant-a\",\"id\":\"doc-a\",\"token\":\"token-a\"}",
      decode.dynamic,
    )
  connect_document.parse_request(payload)
  |> expect.to_equal(
    Ok(connect_document.ConnectRequest("tenant-a", "doc-a", "token-a", None)),
  )
}

pub fn connect_document_parse_request_missing_field_test() {
  let assert Ok(payload) =
    json.parse(
      "{\"tenantId\":\"tenant-a\",\"token\":\"token-a\"}",
      decode.dynamic,
    )
  case connect_document.parse_request(payload) {
    Error(connect_document.InvalidPayload([decode.DecodeError(path: ["id"], ..)])) ->
      Nil
    _ -> panic as "expected a missing id error"
  }
}

pub fn connect_document_validate_mode_scope_write_with_scope_test() {
  connect_document.validate_mode_scope(Some(types.WriteMode), [
    token.DocRead,
    token.DocWrite,
  ])
  |> expect.to_equal(Ok(Nil))
}

pub fn connect_document_validate_mode_scope_write_without_scope_test() {
  connect_document.validate_mode_scope(Some(types.WriteMode), [token.DocRead])
  |> expect.to_equal(Error(connect_document.WriteModeWithoutWriteScope))
}

pub fn connect_document_validate_mode_scope_absent_mode_test() {
  connect_document.validate_mode_scope(None, [])
  |> expect.to_equal(Ok(Nil))
}

pub fn connect_document_invalid_payload_test() {
  let _ = connect_document.parse_request(dynamic.int(1)) |> expect.to_be_error()
  Nil
}
