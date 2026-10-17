//// Connection payload decoding and typed scope decisions.
////
//// The application verifies the JWT signature, requires read access, and owns
//// the session join. This module checks the additional write-mode requirement.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import signet/types as token
import spillway/types.{type ConnectionMode, ReadMode, WriteMode}

pub type ConnectRequest {
  ConnectRequest(
    tenant_id: String,
    document_id: String,
    token: String,
    mode: Option(ConnectionMode),
  )
}

pub type ConnectError {
  InvalidPayload(errors: List(decode.DecodeError))
  WriteModeWithoutWriteScope
}

pub fn decoder() -> Decoder(ConnectRequest) {
  use tenant_id <- decode.field("tenantId", nonempty_string())
  use document_id <- decode.field("id", nonempty_string())
  use token <- decode.field("token", nonempty_string())
  use mode <- decode.optional_field(
    "mode",
    None,
    decode.optional(mode_decoder()),
  )
  decode.success(ConnectRequest(tenant_id:, document_id:, token:, mode:))
}

pub fn parse_request(payload: Dynamic) -> Result(ConnectRequest, ConnectError) {
  decode.run(payload, decoder()) |> result.map_error(InvalidPayload)
}

pub fn mode_decoder() -> Decoder(ConnectionMode) {
  use mode <- decode.then(decode.string)
  case mode {
    "write" -> decode.success(WriteMode)
    "read" -> decode.success(ReadMode)
    _ -> decode.failure(ReadMode, expected: "\"read\" or \"write\"")
  }
}

fn nonempty_string() -> Decoder(String) {
  use text <- decode.then(decode.string)
  case text {
    "" -> decode.failure("", expected: "nonempty string")
    _ -> decode.success(text)
  }
}

pub fn validate_mode_scope(
  mode: Option(ConnectionMode),
  scopes: List(token.Scope),
) -> Result(Nil, ConnectError) {
  case mode {
    Some(WriteMode) ->
      case list.contains(scopes, token.DocWrite) {
        True -> Ok(Nil)
        False -> Error(WriteModeWithoutWriteScope)
      }
    _ -> Ok(Nil)
  }
}
