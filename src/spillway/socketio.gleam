//// Engine.IO / Socket.IO transport framing for Fluid (Routerlicious)
//// compatibility.
////
//// Wraps `windsock`'s Socket.IO event-frame primitives behind a small
//// BEAM-callable surface, so servers (e.g. an Elixir WebSock adapter or a
//// Gleam transport) only classify/encode frames through spillway instead of
//// re-deriving Engine.IO/Socket.IO framing themselves. This module owns no
//// session/runtime state — callers still drive their own `connect_document`
//// auth and session runtime and just pass the resulting event payloads back
//// through the `encode_*` helpers here.
////
//// Engine.IO's opening handshake (`0{...}`) and the Socket.IO namespace
//// connect ack (`40{...}`) aren't part of `windsock`'s scope (it only owns
//// the Socket.IO *event* frame, `42[...]`), so those couple of transport
//// bytes are the one piece of framing hand-rolled here.
////
//// The Routerlicious event names are declared here rather than taken from
//// `dewdrop/events` (which has the same constants) because dewdrop depends
//// on beryl, a server runtime spillway must stay independent of.

import gleam/dynamic.{type Dynamic}
import gleam/json
import windsock

/// A classified inbound Engine.IO/Socket.IO frame.
pub type Frame {
  EnginePing
  EnginePong
  SocketConnect
  FluidEvent(event: String, args: List(Dynamic))
  Unrecognized(reason: String)
}

/// Engine.IO opening handshake packet prefix (`0`).
pub const engine_open_prefix = "0"

/// Socket.IO namespace-connect packet prefix (`40`).
pub const socket_connect_prefix = "40"

/// Routerlicious `op` fan-out event name.
pub const op_event = "op"

/// Routerlicious `signal` fan-out event name.
pub const signal_event = "signal"

/// Routerlicious `connect_document_success` reply event name.
pub const connect_document_success_event = "connect_document_success"

/// Routerlicious `connect_document_error` reply event name.
pub const connect_document_error_event = "connect_document_error"

/// Engine.IO ping packet, delegated to `windsock`.
pub fn engine_ping() -> String {
  windsock.ping
}

/// Engine.IO pong packet, delegated to `windsock`.
pub fn engine_pong() -> String {
  windsock.pong
}

/// Classify a raw inbound text frame as Engine.IO ping/pong, the Socket.IO
/// namespace connect, a decoded Fluid event, or an unrecognized frame.
pub fn classify(text: String) -> Frame {
  case text {
    t if t == windsock.ping -> EnginePing
    t if t == windsock.pong -> EnginePong
    t if t == socket_connect_prefix -> SocketConnect
    _ ->
      case windsock.decode(text) {
        Ok(windsock.Incoming(event, args)) -> FluidEvent(event, args)
        Error(windsock.InvalidJson(reason)) -> Unrecognized(reason)
        Error(windsock.InvalidFormat(reason)) -> Unrecognized(reason)
      }
  }
}

/// Encode the Engine.IO opening handshake packet.
pub fn encode_open(
  sid: String,
  ping_interval_ms: Int,
  ping_timeout_ms: Int,
  max_payload: Int,
) -> String {
  engine_open_prefix
  <> json.to_string(
    json.object([
      #("sid", json.string(sid)),
      #("upgrades", json.preprocessed_array([])),
      #("pingInterval", json.int(ping_interval_ms)),
      #("pingTimeout", json.int(ping_timeout_ms)),
      #("maxPayload", json.int(max_payload)),
    ]),
  )
}

/// Encode the Socket.IO namespace-connect ack.
pub fn encode_connect_ack(sid: String) -> String {
  socket_connect_prefix
  <> json.to_string(json.object([#("sid", json.string(sid))]))
}

/// Encode an Engine.IO pong reply.
pub fn encode_pong() -> String {
  windsock.pong
}

/// Encode a sequenced-ops fan-out frame: `op(documentId, messages)`. Kept as
/// its own function (rather than a generic "encode any event" helper) so the
/// Routerlicious-required two-argument shape is enforced by the function
/// signature, not just by caller convention.
pub fn encode_op(document_id: json.Json, messages: json.Json) -> String {
  windsock.encode(op_event, [document_id, messages])
}

/// Encode a signal fan-out frame: `signal(signalMessage)`.
pub fn encode_signal(signal_message: json.Json) -> String {
  windsock.encode(signal_event, [signal_message])
}

/// Encode a `connect_document_success` reply.
pub fn encode_connect_document_success(payload: json.Json) -> String {
  windsock.encode(connect_document_success_event, [payload])
}

/// Encode a `connect_document_error` reply.
pub fn encode_connect_document_error(payload: json.Json) -> String {
  windsock.encode(connect_document_error_event, [payload])
}
