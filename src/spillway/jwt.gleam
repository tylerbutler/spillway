/// JWT validation for Fluid Framework protocol
///
/// Provides token claims validation per spec section 3:
/// - Document match
/// - Tenant match
/// - Expiration check
/// - Scope checking
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string

import spillway/types.{type TokenClaims, TokenClaims, User}

/// JWT validation error types
pub type JwtValidationError {
  /// Token has expired
  TokenExpired(expired_at: Int, current_time: Int)
  /// Token tenant doesn't match request
  TenantMismatch(token_tenant: String, request_tenant: String)
  /// Token document doesn't match request
  DocumentMismatch(token_document: String, request_document: String)
  /// Token missing required scope
  MissingScope(required: String, available: List(String))
  /// Token is missing a required claim
  MissingClaim(claim_name: String)
  /// Token claim has invalid value
  InvalidClaim(claim_name: String, reason: String)
}

/// Validation result type
pub type JwtValidationResult(a) =
  Result(a, JwtValidationError)

/// Standard permission scopes
pub const scope_doc_read = "doc:read"

pub const scope_doc_write = "doc:write"

pub const scope_summary_write = "summary:write"

/// Validate that the token has not expired
pub fn validate_expiration(
  claims: TokenClaims,
  current_time_seconds: Int,
) -> JwtValidationResult(Nil) {
  case claims.expiration > current_time_seconds {
    True -> Ok(Nil)
    False ->
      Error(TokenExpired(
        expired_at: claims.expiration,
        current_time: current_time_seconds,
      ))
  }
}

/// Validate that the token tenant matches the request tenant
pub fn validate_tenant(
  claims: TokenClaims,
  request_tenant_id: String,
) -> JwtValidationResult(Nil) {
  case claims.tenant_id == request_tenant_id {
    True -> Ok(Nil)
    False ->
      Error(TenantMismatch(
        token_tenant: claims.tenant_id,
        request_tenant: request_tenant_id,
      ))
  }
}

/// Validate that the token document matches the request document
pub fn validate_document(
  claims: TokenClaims,
  request_document_id: String,
) -> JwtValidationResult(Nil) {
  case claims.document_id == request_document_id {
    True -> Ok(Nil)
    False ->
      Error(DocumentMismatch(
        token_document: claims.document_id,
        request_document: request_document_id,
      ))
  }
}

/// Validate that the token has the required scope
pub fn validate_scope(
  claims: TokenClaims,
  required_scope: String,
) -> JwtValidationResult(Nil) {
  case list.contains(claims.scopes, required_scope) {
    True -> Ok(Nil)
    False ->
      Error(MissingScope(required: required_scope, available: claims.scopes))
  }
}

/// Check if token has a specific scope (returns Bool, doesn't error)
pub fn has_scope(claims: TokenClaims, scope: String) -> Bool {
  list.contains(claims.scopes, scope)
}

/// Check if token has read permission
pub fn has_read_scope(claims: TokenClaims) -> Bool {
  has_scope(claims, scope_doc_read)
}

/// Check if token has write permission
pub fn has_write_scope(claims: TokenClaims) -> Bool {
  has_scope(claims, scope_doc_write)
}

/// Check if token has summary write permission
pub fn has_summary_write_scope(claims: TokenClaims) -> Bool {
  has_scope(claims, scope_summary_write)
}

/// Validate all claims for a document connection
/// Per spec section 3.3:
/// 1. Expiration check
/// 2. Tenant match
/// 3. Document match
pub fn validate_connection_claims(
  claims: TokenClaims,
  tenant_id: String,
  document_id: String,
  current_time_seconds: Int,
) -> JwtValidationResult(Nil) {
  use _ <- result.try(validate_expiration(claims, current_time_seconds))
  use _ <- result.try(validate_tenant(claims, tenant_id))
  use _ <- result.try(validate_document(claims, document_id))
  Ok(Nil)
}

/// Validate claims for read access
/// Requires doc:read scope in addition to connection validation
pub fn validate_read_access(
  claims: TokenClaims,
  tenant_id: String,
  document_id: String,
  current_time_seconds: Int,
) -> JwtValidationResult(Nil) {
  use _ <- result.try(validate_connection_claims(
    claims,
    tenant_id,
    document_id,
    current_time_seconds,
  ))
  use _ <- result.try(validate_scope(claims, scope_doc_read))
  Ok(Nil)
}

/// Validate claims for write access
/// Requires doc:write scope in addition to read access validation
pub fn validate_write_access(
  claims: TokenClaims,
  tenant_id: String,
  document_id: String,
  current_time_seconds: Int,
) -> JwtValidationResult(Nil) {
  use _ <- result.try(validate_read_access(
    claims,
    tenant_id,
    document_id,
    current_time_seconds,
  ))
  use _ <- result.try(validate_scope(claims, scope_doc_write))
  Ok(Nil)
}

/// Validate claims for summary write access
/// Requires summary:write scope in addition to read access
pub fn validate_summary_access(
  claims: TokenClaims,
  tenant_id: String,
  document_id: String,
  current_time_seconds: Int,
) -> JwtValidationResult(Nil) {
  use _ <- result.try(validate_read_access(
    claims,
    tenant_id,
    document_id,
    current_time_seconds,
  ))
  use _ <- result.try(validate_scope(claims, scope_summary_write))
  Ok(Nil)
}

/// Format JWT validation error as human-readable message
pub fn format_error(error: JwtValidationError) -> String {
  case error {
    TokenExpired(expired_at, current_time) ->
      "Token expired at "
      <> int.to_string(expired_at)
      <> " (current time: "
      <> int.to_string(current_time)
      <> ")"

    TenantMismatch(token_tenant, request_tenant) ->
      "Token tenant '"
      <> token_tenant
      <> "' does not match request tenant '"
      <> request_tenant
      <> "'"

    DocumentMismatch(token_document, request_document) ->
      "Token document '"
      <> token_document
      <> "' does not match request document '"
      <> request_document
      <> "'"

    MissingScope(required, _available) -> "Missing required scope: " <> required

    MissingClaim(claim_name) -> "Missing required claim: " <> claim_name

    InvalidClaim(claim_name, reason) ->
      "Invalid claim '" <> claim_name <> "': " <> reason
  }
}

/// Get HTTP status code for JWT validation error
pub fn error_to_http_code(error: JwtValidationError) -> Int {
  case error {
    TokenExpired(_, _) -> 401
    TenantMismatch(_, _) -> 403
    DocumentMismatch(_, _) -> 403
    MissingScope(_, _) -> 403
    MissingClaim(_) -> 401
    InvalidClaim(_, _) -> 401
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cryptographic verification (HS256) and minting
//
// The wire/crypto half of JWT handling: HS256 signature verification, claim
// parsing into `TokenClaims`, `Authorization` header extraction, and token
// minting. Callers combine `verify_signature` with the `validate_*` functions
// above. Uses `gleam_crypto` (constant-time compare, HMAC-SHA256) — no FFI.
// ─────────────────────────────────────────────────────────────────────────────

/// Errors from cryptographic verification and wire parsing, distinct from claim
/// validation (`JwtValidationError`).
pub type JwtCryptoError {
  /// Malformed token, header, or `Authorization` value.
  BadFormat
  /// Signature did not match (or an empty secret was supplied).
  BadSignature
}

/// Extract a bare JWT from an `Authorization` header value. Accepts
/// Routerlicious's `Basic <base64(user:jwt)>` scheme and the conventional
/// `Bearer <jwt>` scheme (and a `Basic <jwt>` shorthand when the value is
/// already a dotted JWT).
pub fn extract_token(authorization: String) -> Result(String, JwtCryptoError) {
  case string.split(authorization, " ") {
    ["Basic", token] if token != "" -> extract_basic_token(token)
    ["Bearer", token] if token != "" -> Ok(token)
    _ -> Error(BadFormat)
  }
}

fn extract_basic_token(token: String) -> Result(String, JwtCryptoError) {
  case string.contains(token, ".") {
    True -> Ok(token)
    False -> {
      use credentials <- result.try(
        bit_array.base64_decode(token) |> result.replace_error(BadFormat),
      )
      use credentials <- result.try(
        bit_array.to_string(credentials) |> result.replace_error(BadFormat),
      )
      case string.split(credentials, ":") {
        [_, token] if token != "" -> Ok(token)
        _ -> Error(BadFormat)
      }
    }
  }
}

/// Verify an HS256 signature and parse the payload into `TokenClaims`. Does not
/// validate tenant/document/expiry — pair with the `validate_*` functions.
pub fn verify_signature(
  token: String,
  secret: String,
) -> Result(TokenClaims, JwtCryptoError) {
  case secret, string.split(token, ".") {
    "", _ -> Error(BadSignature)
    _, [header, payload, signature] -> {
      use _ <- result.try(verify_header(header))
      let signed = bit_array.from_string(header <> "." <> payload)
      let expected =
        crypto.hmac(signed, crypto.Sha256, bit_array.from_string(secret))
      case bit_array.base64_url_decode(signature) {
        Ok(actual) ->
          case crypto.secure_compare(actual, expected) {
            True -> parse_claims(payload)
            False -> Error(BadSignature)
          }
        _ -> Error(BadSignature)
      }
    }
    _, _ -> Error(BadFormat)
  }
}

fn verify_header(header: String) -> Result(Nil, JwtCryptoError) {
  use bytes <- result.try(
    bit_array.base64_url_decode(header) |> result.replace_error(BadFormat),
  )
  use text <- result.try(
    bit_array.to_string(bytes) |> result.replace_error(BadFormat),
  )
  use algorithm <- result.try(
    json.parse(text, decode.field("alg", decode.string, decode.success))
    |> result.replace_error(BadFormat),
  )
  case algorithm {
    "HS256" -> Ok(Nil)
    _ -> Error(BadFormat)
  }
}

fn parse_claims(payload: String) -> Result(TokenClaims, JwtCryptoError) {
  let dec = {
    use doc <- decode.field("documentId", decode.string)
    use tenant <- decode.field("tenantId", decode.string)
    use exp <- decode.field("exp", decode.int)
    use scopes <- decode.field("scopes", decode.list(decode.string))
    use user <- decode.field("user", {
      use id <- decode.field("id", decode.string)
      use name <- decode.optional_field("name", id, decode.string)
      decode.success(User(id, dict.from_list([#("name", dynamic.string(name))])))
    })
    use issued_at <- decode.field("iat", decode.int)
    use version <- decode.field("ver", decode.string)
    use jti <- decode.optional_field(
      "jti",
      None,
      decode.optional(decode.string),
    )
    decode.success(TokenClaims(
      doc,
      scopes,
      tenant,
      user,
      issued_at,
      exp,
      version,
      jti,
    ))
  }
  use bytes <- result.try(
    bit_array.base64_url_decode(payload) |> result.replace_error(BadFormat),
  )
  use text <- result.try(
    bit_array.to_string(bytes) |> result.replace_error(BadFormat),
  )
  use claims <- result.try(
    json.parse(text, dec) |> result.replace_error(BadFormat),
  )
  case claims.version == "1.0", claims.user.id != "" {
    True, True -> Ok(claims)
    _, _ -> Error(BadFormat)
  }
}

/// Mint a strict HS256 document token (version "1.0").
pub fn mint_token(
  tenant: String,
  document_id: String,
  scopes: List(String),
  user_id: String,
  secret: String,
  now: Int,
  expires_in: Int,
) -> String {
  let header =
    json.object([#("alg", json.string("HS256")), #("typ", json.string("JWT"))])
    |> json.to_string
    |> bit_array.from_string
    |> bit_array.base64_url_encode(False)
  let payload =
    json.object([
      #("documentId", json.string(document_id)),
      #("tenantId", json.string(tenant)),
      #("scopes", json.array(scopes, json.string)),
      #("user", json.object([#("id", json.string(user_id))])),
      #("ver", json.string("1.0")),
      #("iat", json.int(now)),
      #("exp", json.int(now + expires_in)),
      #(
        "jti",
        crypto.strong_random_bytes(16)
          |> bit_array.base16_encode
          |> string.lowercase
          |> json.string,
      ),
    ])
    |> json.to_string
    |> bit_array.from_string
    |> bit_array.base64_url_encode(False)
  let signed = header <> "." <> payload
  let signature =
    crypto.hmac(
      bit_array.from_string(signed),
      crypto.Sha256,
      bit_array.from_string(secret),
    )
    |> bit_array.base64_url_encode(False)
  signed <> "." <> signature
}
