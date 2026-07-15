/// Core types for Fluid Framework protocol
/// These types map directly to the protocol specification
import gleam/dynamic.{type Dynamic}
import gleam/option.{type Option}
import signet/types as token

/// User identity — re-exported from signet (the shared token/identity domain).
pub type User =
  token.User

/// Connection mode - determines if client can submit operations
pub type ConnectionMode {
  WriteMode
  ReadMode
}

/// Client capabilities
pub type ClientCapabilities {
  ClientCapabilities(interactive: Bool)
}

/// Client details
pub type ClientDetails {
  ClientDetails(
    capabilities: ClientCapabilities,
    client_type: Option(String),
    environment: Option(String),
    device: Option(String),
  )
}

/// Client information
pub type Client {
  Client(
    mode: ConnectionMode,
    details: ClientDetails,
    permission: List(String),
    user: User,
    scopes: List(String),
    timestamp: Option(Int),
  )
}

/// Client with sequence information (for quorum tracking)
pub type SequencedClient {
  SequencedClient(client: Client, sequence_number: Int)
}

/// Client info sent with signals
pub type SignalClient {
  SignalClient(
    client_id: String,
    client: Client,
    client_connection_number: Option(Int),
    reference_sequence_number: Option(Int),
  )
}

/// Service configuration returned to clients
pub type ServiceConfiguration {
  ServiceConfiguration(
    block_size: Int,
    max_message_size: Int,
    noop_time_frequency: Option(Int),
    noop_count_frequency: Option(Int),
  )
}

/// Latency trace point
pub type Trace {
  Trace(service: String, action: String, timestamp: Int)
}

/// Document message (client -> server)
pub type DocumentMessage {
  DocumentMessage(
    client_sequence_number: Int,
    reference_sequence_number: Int,
    message_type: String,
    contents: Dynamic,
    metadata: Option(Dynamic),
    server_metadata: Option(Dynamic),
    traces: Option(List(Trace)),
    compression: Option(String),
  )
}

/// Sequenced document message (server -> clients)
pub type SequencedDocumentMessage {
  SequencedDocumentMessage(
    /// Client ID (null for system messages)
    client_id: Option(String),
    /// Server-assigned sequence number
    sequence_number: Int,
    /// Minimum sequence number at time of sequencing
    minimum_sequence_number: Int,
    /// Client's sequence number
    client_sequence_number: Int,
    /// Client's reference sequence number
    reference_sequence_number: Int,
    /// Message type
    message_type: String,
    /// Message contents
    contents: Dynamic,
    /// Application metadata
    metadata: Option(Dynamic),
    /// Server metadata
    server_metadata: Option(Dynamic),
    /// Branch origin (if applicable)
    origin: Option(MessageOrigin),
    /// Latency traces
    traces: Option(List(Trace)),
    /// Server timestamp (ms since epoch)
    timestamp: Int,
    /// Server-provided data (system messages only)
    data: Option(String),
  )
}

/// Branch origin for forked documents
pub type MessageOrigin {
  MessageOrigin(id: String, sequence_number: Int, minimum_sequence_number: Int)
}

/// JWT token claims — re-exported from signet (scopes are typed `List(Scope)`).
pub type TokenClaims =
  token.TokenClaims

/// Permission scopes — re-exported from signet (adds `SummaryRead`).
pub type Scope =
  token.Scope

/// Convert scope to string
pub fn scope_to_string(scope: Scope) -> String {
  token.scope_to_string(scope)
}

/// Parse scope from string
pub fn scope_from_string(value: String) -> Result(Scope, Nil) {
  token.scope_from_string(value)
}
