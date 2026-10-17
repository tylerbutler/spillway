//// Pure Fluid Framework protocol logic for Gleam on Erlang and JavaScript.
////
//// Import the domain modules directly:
////
//// - `spillway/sequencing`: explicit document state and sequence assignment.
//// - `spillway/validation` and `signet/claims`: typed protocol/claim checks.
//// - `spillway/signals`: v1/v2 decoding, routing, and JSON encoding.
//// - `spillway/summary`, `spillway/nack`, `spillway/types`, and
////   `spillway/message`: protocol data and constructors.
//// - `spillway/session_logic`: negotiation, history, and wire builders.
//// - `spillway/rest` and `spillway/socketio`: JSON responses and text frames.
//// - `spillway/connect_document`: connection decoding and scope checks.
//// - `spillway/schema`: protocol JSON Schema generation.
////
//// Your application owns networking, storage, signature verification, clocks,
//// and document lifetime. Spillway does not start processes or perform IO.

/// Supported compilation targets. See the module guide for the domain APIs.
pub const supported_targets = ["erlang", "javascript"]
