/// Pure business logic for document collaboration sessions
///
/// Applications own the session runtime. These functions make protocol
/// decisions without IO or process communication.
import gleam/dict.{type Dict}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}

// =============================================================================
// Feature Negotiation
// =============================================================================

/// Negotiate features between server and client capabilities.
/// Returns a map of features that both sides agree on.
///
/// Rules:
/// - Server supports (true), client supports (true) -> true
/// - Server supports (true), client doesn't specify -> true (advertise)
/// - Server supports (true), client declines (false) -> false
/// - Otherwise -> server value
pub fn negotiate_features(
  server_features: Dict(String, Bool),
  client_features: Dict(String, Bool),
) -> Dict(String, Bool) {
  dict.map_values(server_features, fn(feature, server_value) {
    case server_value, dict.get(client_features, feature) {
      True, Ok(True) -> True
      True, Error(_) -> True
      True, Ok(False) -> False
      _, _ -> server_value
    }
  })
}

// =============================================================================
// Version Negotiation
// =============================================================================

/// Negotiate protocol version based on client's supported version ranges.
/// Returns the first server version that matches any client version range.
/// Falls back to "0.1.0" if no match found.
pub fn negotiate_version(
  supported_versions: List(String),
  client_versions: List(String),
) -> String {
  case
    list.find(supported_versions, fn(sv) {
      // Simple check: does any client version range contain this version's prefix?
      // e.g., "^0.1.0" matches supported "^0.1.0"
      list.contains(client_versions, sv)
    })
  {
    Ok("^0.1.0") -> "0.1.0"
    Ok("^1.0.0") -> "1.0.0"
    Ok(v) -> v
    Error(_) -> "0.1.0"
  }
}

// =============================================================================
// Signal Recipients
// =============================================================================

/// Determine which clients should receive a signal based on targeting rules.
///
/// Priority: targeted_clients > ignored_clients > single target > broadcast
///
/// - targeted_clients: send only to specified clients (excluding sender)
/// - ignored_clients: send to all except ignored and sender
/// - single_target: send only to the target (if in all_clients and not sender)
/// - broadcast: send to all except sender
pub fn determine_signal_recipients(
  sender_client_id: String,
  targeted_clients: Option(List(String)),
  ignored_clients: Option(List(String)),
  single_target: Option(String),
  all_client_ids: List(String),
) -> List(String) {
  case targeted_clients, ignored_clients, single_target {
    // V2 with targetedClients: send only to specified clients (excluding sender)
    Some(targets), _, _ ->
      targets
      |> list.filter(fn(c) { c != sender_client_id })
      |> list.filter(fn(c) { list.contains(all_client_ids, c) })

    // V2 with ignoredClients: send to all except ignored and sender
    None, Some(ignored), _ ->
      all_client_ids
      |> list.filter(fn(c) {
        c != sender_client_id && !list.contains(ignored, c)
      })

    // V2 with single targetClientId
    None, None, Some(target) ->
      case target != sender_client_id && list.contains(all_client_ids, target) {
        True -> [target]
        False -> []
      }

    // V1 or V2 broadcast: send to all except sender
    None, None, None ->
      list.filter(all_client_ids, fn(c) { c != sender_client_id })
  }
}

// =============================================================================
// History Management
// =============================================================================

/// Add an operation to the history (newest first) and trim to max size.
pub fn add_to_history(op: a, history: List(a), max_size: Int) -> List(a) {
  [op, ..history]
  |> list.take(max_size)
}

// =============================================================================
// Wire Format Builders
// =============================================================================

/// Build a sequenced operation map for the wire format.
/// Takes the original op fields and server-assigned values.
pub type SequencedOpParams {
  SequencedOpParams(
    client_id: String,
    sequence_number: Int,
    minimum_sequence_number: Int,
    client_sequence_number: Int,
    reference_sequence_number: Int,
    op_type: String,
    contents: Json,
    metadata: Json,
    timestamp: Int,
  )
}

/// Build a complete sequenced operation JSON object.
pub fn build_sequenced_op(params: SequencedOpParams) -> Json {
  json.object([
    #("clientId", json.string(params.client_id)),
    #("sequenceNumber", json.int(params.sequence_number)),
    #("minimumSequenceNumber", json.int(params.minimum_sequence_number)),
    #("clientSequenceNumber", json.int(params.client_sequence_number)),
    #("referenceSequenceNumber", json.int(params.reference_sequence_number)),
    #("type", json.string(params.op_type)),
    #("contents", params.contents),
    #("metadata", params.metadata),
    #("timestamp", json.int(params.timestamp)),
  ])
}

/// Build a summary ack JSON object. `sn` is the proposal's sequence number;
/// the ack uses `sn + 1`. Reserve that number in the sequencer separately.
pub fn build_summary_ack(
  handle: String,
  sn: Int,
  msn: Int,
  timestamp: Int,
) -> Json {
  let summary_proposal = json.object([#("summarySequenceNumber", json.int(sn))])

  let contents =
    json.object([
      #("handle", json.string(handle)),
      #("summaryProposal", summary_proposal),
    ])

  json.object([
    #("clientId", json.null()),
    #("sequenceNumber", json.int(sn + 1)),
    #("minimumSequenceNumber", json.int(msn)),
    #("clientSequenceNumber", json.int(-1)),
    #("referenceSequenceNumber", json.int(sn)),
    #("type", json.string("summaryAck")),
    #("contents", contents),
    #("metadata", json.null()),
    #("timestamp", json.int(timestamp)),
  ])
}
