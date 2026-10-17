//// Pure REST response-shape decisions for the Storage/Historian-style HTTP
//// surface (`POST /documents/:tenant`, `GET /documents/:tenant/:id`,
//// `GET /documents/:tenant/session/:id`, `GET /deltas/:tenant/:id`,
//// `/repos/:tenant/git/*`).
////
//// These functions only decide *shape* (URLs, wire field names, which
//// optional fields are present) from plain values the caller already has —
//// they do not touch storage, JWTs, or HTTP plumbing. Servers keep doing the
//// actual storage calls and request handling, and delegate the
//// response-shape decision to these functions so the wire format lives in
//// one place.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/string
import spillway/types.{type SequencedDocumentMessage}

// ─────────────────────────────────────────────────────────────────────────────
// Base URL / git object URL construction
// ─────────────────────────────────────────────────────────────────────────────

/// Build the scheme://host[:port] prefix, omitting the port for the
/// scheme's default (80 for http, 443 for https).
pub fn base_url(scheme: String, host: String, port: Int) -> String {
  let port_suffix = case scheme, port {
    "http", 80 -> ""
    "https", 443 -> ""
    _, p -> ":" <> int.to_string(p)
  }
  scheme <> "://" <> host <> port_suffix
}

pub fn blob_url(base_url: String, tenant_id: String, sha: String) -> String {
  base_url <> "/repos/" <> tenant_id <> "/git/blobs/" <> sha
}

pub fn tree_url(base_url: String, tenant_id: String, sha: String) -> String {
  base_url <> "/repos/" <> tenant_id <> "/git/trees/" <> sha
}

pub fn commit_url(base_url: String, tenant_id: String, sha: String) -> String {
  base_url <> "/repos/" <> tenant_id <> "/git/commits/" <> sha
}

/// The "refs/" prefix is stripped for the URL (e.g. `refs/heads/main`
/// becomes `.../git/refs/heads/main`).
pub fn ref_url(
  base_url: String,
  tenant_id: String,
  ref_path: String,
) -> String {
  let path = case string.starts_with(ref_path, "refs/") {
    True -> string.drop_start(ref_path, 5)
    False -> ref_path
  }
  base_url <> "/repos/" <> tenant_id <> "/git/refs/" <> path
}

/// Join wildcard-route ref path segments (from `GET/PATCH .../refs/*ref`)
/// into a full `refs/...` path.
pub fn build_ref_path(ref_parts: List(String)) -> String {
  "refs/" <> string.join(ref_parts, "/")
}

// ─────────────────────────────────────────────────────────────────────────────
// Git object response shaping
// ─────────────────────────────────────────────────────────────────────────────

pub fn format_blob_response(
  base_url: String,
  tenant_id: String,
  sha: String,
  size: Int,
  content_base64: String,
) -> Json {
  json.object([
    #("sha", json.string(sha)),
    #("size", json.int(size)),
    #("content", json.string(content_base64)),
    #("encoding", json.string("base64")),
    #("url", json.string(blob_url(base_url, tenant_id, sha))),
  ])
}

pub type TreeEntry {
  TreeEntry(path: String, mode: String, sha: String, entry_type: String)
}

fn format_tree_entry(
  base_url: String,
  tenant_id: String,
  entry: TreeEntry,
) -> Json {
  let TreeEntry(path, mode, sha, entry_type) = entry

  let entry_url = case entry_type {
    "blob" -> json.string(blob_url(base_url, tenant_id, sha))
    "tree" -> json.string(tree_url(base_url, tenant_id, sha))
    _ -> json.null()
  }

  json.object([
    #("path", json.string(path)),
    #("mode", json.string(mode)),
    #("sha", json.string(sha)),
    #("type", json.string(entry_type)),
    #("url", entry_url),
  ])
}

pub fn format_tree_response(
  base_url: String,
  tenant_id: String,
  sha: String,
  entries: List(TreeEntry),
) -> Json {
  let formatted_entries =
    list.map(entries, format_tree_entry(base_url, tenant_id, _))

  json.object([
    #("sha", json.string(sha)),
    #("url", json.string(tree_url(base_url, tenant_id, sha))),
    #("tree", json.preprocessed_array(formatted_entries)),
  ])
}

pub fn format_commit_response(
  base_url: String,
  tenant_id: String,
  sha: String,
  tree_sha: String,
  parents: List(String),
  message: Json,
  author: Json,
  committer: Json,
) -> Json {
  let tree_obj =
    json.object([
      #("sha", json.string(tree_sha)),
      #("url", json.string(tree_url(base_url, tenant_id, tree_sha))),
    ])

  let formatted_parents =
    list.map(parents, fn(parent_sha) {
      json.object([
        #("sha", json.string(parent_sha)),
        #("url", json.string(commit_url(base_url, tenant_id, parent_sha))),
      ])
    })

  json.object([
    #("sha", json.string(sha)),
    #("tree", tree_obj),
    #("parents", json.preprocessed_array(formatted_parents)),
    #("message", message),
    #("author", author),
    #("committer", committer),
    #("url", json.string(commit_url(base_url, tenant_id, sha))),
  ])
}

pub fn format_ref_response(
  base_url: String,
  tenant_id: String,
  ref_path: String,
  sha: String,
) -> Json {
  let object =
    json.object([
      #("sha", json.string(sha)),
      #("type", json.string("commit")),
      #("url", json.string(commit_url(base_url, tenant_id, sha))),
    ])

  json.object([
    #("ref", json.string(ref_path)),
    #("object", object),
    #("url", json.string(ref_url(base_url, tenant_id, ref_path))),
  ])
}

// ─────────────────────────────────────────────────────────────────────────────
// Document / session response shaping
// ─────────────────────────────────────────────────────────────────────────────

pub fn format_document_response(
  id: String,
  tenant_id: String,
  sequence_number: Int,
) -> Json {
  json.object([
    #("id", json.string(id)),
    #("tenantId", json.string(tenant_id)),
    #("sequenceNumber", json.int(sequence_number)),
  ])
}

/// Build the `GET /documents/:tenant/session/:id` response shape.
pub fn session_info(
  host: String,
  tenant_id: String,
  document_id: String,
  is_alive: Bool,
) -> Json {
  json.object([
    #("ordererUrl", json.string(host <> "/socket")),
    #("historianUrl", json.string(host <> "/repos/" <> tenant_id)),
    #(
      "deltaStreamUrl",
      json.string(host <> "/deltas/" <> tenant_id <> "/" <> document_id),
    ),
    #("isSessionAlive", json.bool(is_alive)),
    #("isSessionActive", json.bool(is_alive)),
  ])
}

// ─────────────────────────────────────────────────────────────────────────────
// Delta (operation history) response shaping
// ─────────────────────────────────────────────────────────────────────────────

/// System messages (join/leave) carry a JSON-stringified `data` field
/// alongside `contents`, matching the Fluid `ISequencedDocumentMessage`
/// wire shape. Callers decide whether to attach `data` by asking this
/// function, then do the actual JSON encoding themselves.
pub fn requires_data_field(msg_type: String) -> Bool {
  msg_type == "join" || msg_type == "leave"
}

/// Build a single `ISequencedDocumentMessage` for `GET /deltas/:tenant/:id`.
/// `data` is a JSON-stringified sidecar for join/leave messages only.
/// Missing client IDs, metadata, and system data are encoded as null.
pub fn format_delta_message(message: SequencedDocumentMessage(Json)) -> Json {
  let base = [
    #("sequenceNumber", json.int(message.sequence_number)),
    #("clientSequenceNumber", json.int(message.client_sequence_number)),
    #("minimumSequenceNumber", json.int(message.minimum_sequence_number)),
    #("clientId", json.nullable(message.client_id, json.string)),
    #("referenceSequenceNumber", json.int(message.reference_sequence_number)),
    #("type", json.string(message.message_type)),
    #("contents", message.contents),
    #("metadata", json.nullable(message.metadata, fn(value) { value })),
    #("timestamp", json.int(message.timestamp)),
  ]

  case requires_data_field(message.message_type) {
    True ->
      json.object(
        list.append(base, [#("data", json.nullable(message.data, json.string))]),
      )
    False -> json.object(base)
  }
}
