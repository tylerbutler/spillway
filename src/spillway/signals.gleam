//// Fluid v1/v2 signals: typed payloads, explicit decoding, and pure routing.
////
//// Supply a payload decoder at the input boundary and an encoder at output.
//// Missing or null optional fields become `None`; malformed present fields
//// are errors. Normalized output includes optional fields as explicit nulls.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import spillway/session_logic
import spillway/types.{type Client}

pub type SystemSignalType {
  ClientJoinSignal
  ClientLeaveSignal
}

pub type ClientJoinContent {
  ClientJoinContent(client_id: String, client: Client)
}

pub type ClientLeaveContent {
  ClientLeaveContent(client_id: String)
}

pub type SystemSignal {
  JoinSignal(ClientJoinContent)
  LeaveSignal(ClientLeaveContent)
}

pub fn client_join_signal(client_id: String, client: Client) -> SystemSignal {
  JoinSignal(ClientJoinContent(client_id:, client:))
}

pub fn client_leave_signal(client_id: String) -> SystemSignal {
  LeaveSignal(ClientLeaveContent(client_id:))
}

pub type SignalAddress {
  BroadcastAddress
  ContainerAddress(String)
}

pub type SignalV1Contents(payload) {
  SignalV1Contents(signal_type: String, content: payload)
}

pub type SignalV1Envelope(payload) {
  SignalV1Envelope(
    address: String,
    contents: SignalV1Contents(payload),
    client_broadcast_signal_sequence_number: Int,
  )
}

pub type NormalizedSignal(payload) {
  NormalizedSignal(
    content: payload,
    signal_type: Option(String),
    client_connection_number: Option(Int),
    reference_sequence_number: Option(Int),
    target_client_id: Option(String),
    targeted_clients: Option(List(String)),
    ignored_clients: Option(List(String)),
  )
}

pub type SignalParseError {
  InvalidJson(json.DecodeError)
  InvalidSignal(errors: List(decode.DecodeError))
  InvalidBatchItem(index: Int, error: SignalParseError)
}

/// Decode a complete legacy envelope, including its required fields.
pub fn v1_decoder(
  content: Decoder(payload),
) -> Decoder(SignalV1Envelope(payload)) {
  use address <- decode.field("address", decode.string)
  use contents <- decode.field("contents", {
    use signal_type <- decode.field("type", decode.string)
    use content <- decode.field("content", content)
    decode.success(SignalV1Contents(signal_type:, content:))
  })
  use sequence <- decode.field(
    "clientBroadcastSignalSequenceNumber",
    decode.int,
  )
  decode.success(SignalV1Envelope(address, contents, sequence))
}

/// Decode a v1, bare v2, or wrapped v2 signal. The payload schema is caller-owned.
pub fn decoder(
  content: Decoder(payload),
) -> Decoder(NormalizedSignal(payload)) {
  use fields <- decode.then(decode.dict(decode.string, decode.dynamic))
  case dict.has_key(fields, "address") || dict.has_key(fields, "contents") {
    True ->
      v1_decoder(content)
      |> decode.map(fn(v1) {
        NormalizedSignal(
          content: v1.contents.content,
          signal_type: Some(v1.contents.signal_type),
          client_connection_number: Some(
            v1.client_broadcast_signal_sequence_number,
          ),
          reference_sequence_number: None,
          target_client_id: None,
          targeted_clients: None,
          ignored_clients: None,
        )
      })
    False -> {
      let inner = case dict.has_key(fields, "signal") {
        True -> decode.at(["signal"], v2_decoder(content))
        False -> v2_decoder(content)
      }
      use signal <- decode.then(inner)
      use targeted <- optional_field(
        "targetedClients",
        decode.list(decode.string),
      )
      use ignored <- optional_field(
        "ignoredClients",
        decode.list(decode.string),
      )
      decode.success(NormalizedSignal(
        content: signal.content,
        signal_type: signal.signal_type,
        client_connection_number: signal.client_connection_number,
        reference_sequence_number: signal.reference_sequence_number,
        target_client_id: signal.target_client_id,
        targeted_clients: targeted,
        ignored_clients: ignored,
      ))
    }
  }
}

fn v2_decoder(content: Decoder(payload)) -> Decoder(SignalV2(payload)) {
  use content <- decode.field("content", content)
  use signal_type <- optional_field("type", decode.string)
  use connection <- optional_field("clientConnectionNumber", decode.int)
  use reference <- optional_field("referenceSequenceNumber", decode.int)
  use target <- optional_field("targetClientId", decode.string)
  decode.success(SignalV2(content, signal_type, connection, reference, target))
}

fn optional_field(
  name: String,
  decoder: Decoder(a),
  next: fn(Option(a)) -> Decoder(b),
) -> Decoder(b) {
  decode.optional_field(name, None, decode.optional(decoder), next)
}

pub fn normalize_signal(
  raw: Dynamic,
  content: Decoder(payload),
) -> Result(NormalizedSignal(payload), SignalParseError) {
  decode.run(raw, decoder(content)) |> result.map_error(InvalidSignal)
}

/// Decode a singleton or list. List errors include the failing element's index.
/// An empty array succeeds; malformed elements fail the entire batch.
pub fn batch_decoder(
  content: Decoder(payload),
) -> Decoder(List(NormalizedSignal(payload))) {
  use raw <- decode.then(decode.dynamic)
  case decode.run(raw, decode.list(decode.dynamic)) {
    Ok(_) -> decode.list(decoder(content))
    Error(_) -> decode.map(decoder(content), fn(signal) { [signal] })
  }
}

/// Accept already-decoded data or a JSON string containing a singleton/list.
/// JSON-stringified legacy envelopes inside lists are also accepted.
pub fn normalize_signal_batch(
  batch: Dynamic,
  content: Decoder(payload),
) -> Result(List(NormalizedSignal(payload)), SignalParseError) {
  case decode.run(batch, decode.string) {
    Ok(text) -> parse_batch(text, content)
    Error(_) -> {
      case decode.run(batch, decode.list(decode.dynamic)) {
        Ok(items) ->
          items
          |> list.index_map(fn(item, index) { #(item, index) })
          |> list.try_map(fn(pair) {
            let #(item, index) = pair
            normalize_item(item, content)
            |> result.map_error(InvalidBatchItem(index, _))
          })
        Error(_) ->
          normalize_signal(batch, content)
          |> result.map(fn(signal) { [signal] })
      }
    }
  }
}

/// Parse JSON at the wire boundary. No native term conversion is required.
pub fn parse_batch(
  text: String,
  content: Decoder(payload),
) -> Result(List(NormalizedSignal(payload)), SignalParseError) {
  use raw <- result.try(
    json.parse(text, decode.dynamic) |> result.map_error(InvalidJson),
  )
  normalize_signal_batch(raw, content)
}

fn normalize_item(
  raw: Dynamic,
  content: Decoder(payload),
) -> Result(NormalizedSignal(payload), SignalParseError) {
  case decode.run(raw, decode.string) {
    Ok(text) ->
      json.parse(text, decoder(content))
      |> result.map_error(fn(error) {
        case error {
          json.UnableToDecode(errors) -> InvalidSignal(errors)
          _ -> InvalidJson(error)
        }
      })
    Error(_) -> normalize_signal(raw, content)
  }
}

pub fn normalized_to_json(
  signal: NormalizedSignal(payload),
  encode: fn(payload) -> Json,
) -> Json {
  json.object([
    #("content", encode(signal.content)),
    #("type", json.nullable(signal.signal_type, json.string)),
    #(
      "clientConnectionNumber",
      json.nullable(signal.client_connection_number, json.int),
    ),
    #(
      "referenceSequenceNumber",
      json.nullable(signal.reference_sequence_number, json.int),
    ),
    #("targetClientId", json.nullable(signal.target_client_id, json.string)),
    #(
      "targetedClients",
      json.nullable(signal.targeted_clients, json.array(_, json.string)),
    ),
    #(
      "ignoredClients",
      json.nullable(signal.ignored_clients, json.array(_, json.string)),
    ),
  ])
}

pub type SignalV2(payload) {
  SignalV2(
    content: payload,
    signal_type: Option(String),
    client_connection_number: Option(Int),
    reference_sequence_number: Option(Int),
    target_client_id: Option(String),
  )
}

pub type ClientBroadcastSignalEnvelope(payload) {
  ClientBroadcastSignalEnvelope(
    signal: SignalV2(payload),
    targeted_clients: Option(List(String)),
    ignored_clients: Option(List(String)),
  )
}

pub fn is_targeted(signal: SignalV2(payload)) -> Bool {
  option.is_some(signal.target_client_id)
}

pub fn should_receive(signal: SignalV2(payload), client_id: String) -> Bool {
  case signal.target_client_id {
    None -> True
    Some(target) -> target == client_id
  }
}

/// Explicit envelope targets exclude the sender but need not be in the roster.
/// Without explicit targets, route through the roster and ignored-client list.
/// The envelope's routing does not apply its inner single-target field.
pub fn get_signal_recipients(
  envelope: ClientBroadcastSignalEnvelope(payload),
  all_clients: List(String),
  sender_client_id: String,
) -> List(String) {
  case envelope.targeted_clients {
    Some(targets) ->
      list.filter(targets, fn(client) { client != sender_client_id })
    None ->
      session_logic.determine_signal_recipients(
        sender_client_id,
        None,
        envelope.ignored_clients,
        None,
        all_clients,
      )
  }
}

pub fn should_client_receive_signal(
  envelope: ClientBroadcastSignalEnvelope(payload),
  client_id: String,
  sender_client_id: String,
) -> Bool {
  list.contains(
    get_signal_recipients(envelope, [client_id], sender_client_id),
    client_id,
  )
}

pub fn broadcast(
  content: payload,
  signal_type: Option(String),
  connection_number: Option(Int),
  rsn: Option(Int),
) -> SignalV2(payload) {
  SignalV2(content, signal_type, connection_number, rsn, None)
}

pub fn targeted(
  content: payload,
  target_client_id: String,
  signal_type: Option(String),
  connection_number: Option(Int),
  rsn: Option(Int),
) -> SignalV2(payload) {
  SignalV2(content, signal_type, connection_number, rsn, Some(target_client_id))
}

pub fn broadcast_envelope(
  signal: SignalV2(payload),
) -> ClientBroadcastSignalEnvelope(payload) {
  ClientBroadcastSignalEnvelope(signal, None, None)
}

pub fn targeted_envelope(
  signal: SignalV2(payload),
  targets: List(String),
) -> ClientBroadcastSignalEnvelope(payload) {
  ClientBroadcastSignalEnvelope(signal, Some(targets), None)
}

pub fn ignored_envelope(
  signal: SignalV2(payload),
  ignored: List(String),
) -> ClientBroadcastSignalEnvelope(payload) {
  ClientBroadcastSignalEnvelope(signal, None, Some(ignored))
}

pub type SignalMessage(payload) {
  SignalMessage(
    client_id: Option(String),
    content: payload,
    signal_type: Option(String),
    client_connection_number: Option(Int),
    reference_sequence_number: Option(Int),
    target_client_id: Option(String),
  )
}

pub fn signal_message_from_v2(
  sender_client_id: String,
  signal: SignalV2(payload),
) -> SignalMessage(payload) {
  SignalMessage(
    Some(sender_client_id),
    signal.content,
    signal.signal_type,
    signal.client_connection_number,
    signal.reference_sequence_number,
    signal.target_client_id,
  )
}

pub fn system_signal_message(
  content: payload,
  signal_type: String,
) -> SignalMessage(payload) {
  SignalMessage(None, content, Some(signal_type), None, None, None)
}

pub type SignalVersion {
  V1Format
  V2Format
  UnknownFormat
}

pub fn detect_signal_version(
  has_address: Bool,
  has_targeted_clients: Bool,
  has_ignored_clients: Bool,
) -> SignalVersion {
  case has_address, has_targeted_clients || has_ignored_clients {
    True, False -> V1Format
    _, True -> V2Format
    False, False -> V2Format
  }
}
