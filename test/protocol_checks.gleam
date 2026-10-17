//// Shared checks run by Startest on Erlang/Node and directly in a browser.
//// This module must not import a test runner or Node-only module.

import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import protocol_fixtures
import signet/claims as claim
import signet/types as token
import spillway/connect_document
import spillway/message
import spillway/nack
import spillway/rest
import spillway/schema
import spillway/sequencing
import spillway/session_logic
import spillway/signals
import spillway/socketio
import spillway/summary
import spillway/types
import spillway/validation

pub fn run() -> Nil {
  wire_contracts()
  signal_decoding()
  domain_contracts()
}

pub fn assert_json(actual: Json, expected: String) -> Nil {
  let assert Ok(expected) = json.parse(expected, decode.dynamic)
  let assert Ok(actual) = json.parse(json.to_string(actual), decode.dynamic)
  assert actual == expected
}

pub fn wire_contracts() -> Nil {
  assert socketio.encode_op(json.string("doc-1"), json.preprocessed_array([]))
    == protocol_fixtures.op_frame
  let assert socketio.FluidEvent("op", [document_id, messages]) =
    socketio.classify(protocol_fixtures.op_frame)
  assert decode.run(document_id, decode.string) == Ok("doc-1")
  assert decode.run(messages, decode.list(decode.string)) == Ok([])
  rest.format_blob_response(
    "http://localhost:4000",
    "tenant1",
    "sha1",
    11,
    "aGVsbG8gd29ybGQ=",
  )
  |> assert_json(protocol_fixtures.blob)
  session_logic.build_summary_ack("handle-1", 10, 5, 1000)
  |> assert_json(protocol_fixtures.summary_ack)
  session_logic.build_sequenced_op(session_logic.SequencedOpParams(
    client_id: "c1",
    sequence_number: 11,
    minimum_sequence_number: 5,
    client_sequence_number: 2,
    reference_sequence_number: 10,
    op_type: "op",
    contents: json.object([
      #("text", json.string("water 🌊")),
      #(
        "items",
        json.preprocessed_array([
          json.int(1),
          json.null(),
          json.bool(True),
          json.object([]),
        ]),
      ),
    ]),
    metadata: json.null(),
    timestamp: 1000,
  ))
  |> assert_json(protocol_fixtures.operation)
  let assert Ok(signal) =
    json.parse(
      protocol_fixtures.signal_v2,
      signals.decoder(decode.at(["x"], decode.int)),
    )
  signals.normalized_to_json(signal, fn(x) {
    json.object([#("x", json.int(x))])
  })
  |> assert_json(protocol_fixtures.normalized_signal)
  rest.format_tree_response("http://localhost", "t", "s", [])
  |> assert_json(
    "{\"sha\":\"s\",\"url\":\"http://localhost/repos/t/git/trees/s\",\"tree\":[]}",
  )
}

pub fn signal_decoding() -> Nil {
  let content = decode.at(["x"], decode.int)
  let assert Ok(v1) =
    json.parse(protocol_fixtures.signal_v1, signals.decoder(content))
  assert v1.content == 1
  assert v1.signal_type == Some("cursor")
  assert v1.client_connection_number == Some(7)
  let assert Ok(v2) = signals.parse_batch(protocol_fixtures.signal_v2, content)
  assert list.length(v2) == 1
  let assert Ok([_]) =
    json.parse(protocol_fixtures.signal_v2, signals.batch_decoder(content))
  let assert Ok([]) = json.parse("[]", signals.batch_decoder(content))
  let assert Error(json.UnableToDecode([
    decode.DecodeError(path: ["1", "type"], ..),
    ..
  ])) =
    json.parse(
      "[{\"content\":1},{\"content\":2,\"type\":false}]",
      signals.batch_decoder(decode.int),
    )
  let assert Ok([]) = signals.parse_batch("[]", content)
  let assert Ok([_, _]) =
    signals.parse_batch(
      "["
        <> protocol_fixtures.signal_v1
        <> ","
        <> protocol_fixtures.signal_v2
        <> "]",
      content,
    )
  let encoded_envelopes =
    json.preprocessed_array([json.string(protocol_fixtures.signal_v1)])
  let assert Ok([_]) =
    signals.parse_batch(json.to_string(encoded_envelopes), content)
  let assert Ok(raw) = json.parse(protocol_fixtures.signal_v2, decode.dynamic)
  let assert Ok(_) = signals.normalize_signal(raw, content)
  let assert Ok([_]) =
    signals.normalize_signal_batch(
      dynamic.string(protocol_fixtures.signal_v1),
      content,
    )
  let assert Ok([_]) =
    signals.normalize_signal_batch(
      dynamic.list([dynamic.string(protocol_fixtures.signal_v1)]),
      content,
    )
  let assert Ok(null_signal) =
    json.parse(
      "{\"content\":null,\"type\":null,\"targetedClients\":null}",
      signals.decoder(decode.optional(decode.string)),
    )
  assert null_signal.content == None
  assert null_signal.signal_type == None
  signals.normalized_to_json(null_signal, json.nullable(_, json.string))
  |> assert_json(
    "{\"content\":null,\"type\":null,\"clientConnectionNumber\":null,\"referenceSequenceNumber\":null,\"targetClientId\":null,\"targetedClients\":null,\"ignoredClients\":null}",
  )

  let bad_signals = [
    "{}",
    "null",
    "42",
    "{\"content\":1,\"type\":false}",
    "{\"content\":1,\"clientConnectionNumber\":\"7\"}",
    "{\"content\":1,\"referenceSequenceNumber\":[]}",
    "{\"content\":1,\"targetClientId\":3}",
    "{\"content\":1,\"targetedClients\":[7]}",
    "{\"content\":1,\"ignoredClients\":{}}",
    "{\"signal\":null}",
    "{\"signal\":{},\"content\":1}",
    "{\"address\":false,\"contents\":{\"type\":\"t\",\"content\":1},\"clientBroadcastSignalSequenceNumber\":0}",
    "{\"address\":\"\",\"contents\":{\"type\":1,\"content\":1},\"clientBroadcastSignalSequenceNumber\":0}",
  ]
  list.each(bad_signals, fn(text) {
    let assert Error(signals.InvalidSignal([_, ..])) =
      signals.parse_batch(text, decode.int)
  })
  let assert Error(signals.InvalidJson(_)) =
    signals.parse_batch("{", decode.int)
  let assert Error(signals.InvalidBatchItem(1, signals.InvalidSignal(errors))) =
    signals.parse_batch(
      "[{\"content\":1},{\"content\":2,\"type\":false}]",
      decode.int,
    )
  let assert [decode.DecodeError(path: ["type"], ..), ..] = errors
  let assert Error(signals.InvalidBatchItem(0, signals.InvalidJson(_))) =
    signals.parse_batch("[\"not json\"]", decode.int)
  Nil
}

pub fn domain_contracts() -> Nil {
  let state = sequencing.new() |> sequencing.client_join("c1", 0)
  let assert Ok(sequencing.SequenceAssignment(next, 1, 0)) =
    sequencing.assign_sequence_number(state, "c1", 1, 0)
  let #(next, reserved) = sequencing.reserve_sequence_number(next)
  assert reserved == 2
  let assert Ok(sequencing.SequenceAssignment(_, 3, 1)) =
    sequencing.assign_sequence_number(next, "c1", 2, 1)
  let assert Error(sequencing.InvalidCsn(_, 1)) =
    sequencing.assign_sequence_number(next, "c1", 1, 0)
  let assert Error(sequencing.UnknownClient("unknown")) =
    sequencing.assign_sequence_number(next, "unknown", 1, 0)
  let assert Error(sequencing.InvalidRsn(_, 3)) =
    sequencing.assign_sequence_number(next, "c1", 2, 3)

  let assert Ok(request) =
    json.parse(protocol_fixtures.connection, connect_document.decoder())
  assert request.mode == Some(types.WriteMode)
  let assert Ok(Nil) =
    connect_document.validate_mode_scope(request.mode, [token.DocWrite])
  let assert Error(connect_document.WriteModeWithoutWriteScope) =
    connect_document.validate_mode_scope(request.mode, [token.DocRead])
  let assert Ok(Nil) = connect_document.validate_mode_scope(None, [])
  let assert Error(_) =
    json.parse(
      "{\"tenantId\":\"t\",\"id\":\"d\",\"token\":\"x\",\"mode\":\"other\"}",
      connect_document.decoder(),
    )
  let assert Error(_) =
    json.parse(
      "{\"tenantId\":\"\",\"id\":\"d\",\"token\":\"x\"}",
      connect_document.decoder(),
    )
  let claims =
    token.TokenClaims(
      document_id: "d",
      scopes: [token.DocRead],
      tenant_id: "t",
      user: token.User("u", dict.new()),
      issued_at: 0,
      expiration: 10,
      version: "1.0",
      jti: None,
    )
  let assert Ok(Nil) = claim.validate_read_access(claims, "t", "d", 9)
  let assert Error(claim.TokenExpired(10, 10)) =
    claim.validate_expiration(claims, 10)
  let assert Error(_) = claim.validate_write_access(claims, "t", "d", 9)
  let assert Ok(Nil) = validation.validate_scope(claims, token.DocRead)
  let assert Error(validation.MissingScope(token.DocWrite, [token.DocRead])) =
    validation.validate_scope(claims, token.DocWrite)
  let assert Ok(token.DocRead) =
    json.parse("\"doc:read\"", types.scope_decoder())
  let assert Error(_) = json.parse("\"unknown\"", types.scope_decoder())

  let signal = signals.targeted(1, "c2", None, None, None)
  assert signals.should_receive(signal, "c2")
  assert !signals.should_receive(signal, "c3")
  let envelope = signals.targeted_envelope(signal, ["c1", "c2"])
  assert signals.get_signal_recipients(envelope, ["c1", "c2"], "c1") == ["c2"]
  assert signals.get_signal_recipients(envelope, ["c1"], "c1") == ["c2"]
  assert signals.get_signal_recipients(envelope, [], "c1") == ["c2"]
  assert signals.should_client_receive_signal(envelope, "c2", "c1")
  assert !signals.should_client_receive_signal(envelope, "c1", "c1")
  // An envelope's routing ignores the inner single target, as before.
  let broadcast = signals.broadcast_envelope(signal)
  assert signals.get_signal_recipients(broadcast, ["c1", "c2", "c3"], "c1")
    == ["c2", "c3"]
  let ignored = signals.ignored_envelope(signal, ["c2"])
  assert signals.get_signal_recipients(ignored, ["c1", "c2", "c3"], "c1")
    == ["c3"]
  assert session_logic.determine_signal_recipients(
      "c1",
      Some(["c2"]),
      Some(["c2"]),
      Some("c3"),
      ["c1", "c2", "c3"],
    )
    == ["c2"]
  assert session_logic.determine_signal_recipients(
      "c1",
      None,
      Some(["c2"]),
      Some("c3"),
      ["c1", "c2", "c3"],
    )
    == ["c3"]
  assert session_logic.determine_signal_recipients(
      "c1",
      Some(["c2"]),
      None,
      None,
      ["c1"],
    )
    == []
  let nack = nack.invalid_scope(token.DocWrite, None)
  assert nack.content.code == 403
  assert nack.content.message == "Missing required scope: doc:write"
  let tree =
    summary.empty_summary_tree()
    |> summary.add_to_summary_tree("file", summary.SummaryBlob("text"))
  assert summary.get_from_summary_tree(tree, "file")
    == Ok(summary.SummaryBlob("text"))
  assert message.message_type_to_string(message.Operation) == "op"
  let assert Ok(_) =
    json.parse(
      json.to_string(schema.generate_protocol_schema()),
      decode.dict(decode.string, decode.dynamic),
    )
  Nil
}
