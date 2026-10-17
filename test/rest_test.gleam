import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import protocol_checks
import spillway/rest
import spillway/types
import startest/expect

pub fn base_url_omits_default_http_port_test() {
  rest.base_url("http", "example.test", 80)
  |> expect.to_equal("http://example.test")
}

pub fn base_url_omits_default_https_port_test() {
  rest.base_url("https", "example.test", 443)
  |> expect.to_equal("https://example.test")
}

pub fn base_url_keeps_non_default_port_test() {
  rest.base_url("http", "localhost", 4000)
  |> expect.to_equal("http://localhost:4000")
}

pub fn object_urls_test() {
  rest.blob_url("http://localhost:4000", "tenant1", "abc123")
  |> expect.to_equal("http://localhost:4000/repos/tenant1/git/blobs/abc123")
  rest.tree_url("http://localhost:4000", "tenant1", "abc123")
  |> expect.to_equal("http://localhost:4000/repos/tenant1/git/trees/abc123")
  rest.commit_url("http://localhost:4000", "tenant1", "abc123")
  |> expect.to_equal("http://localhost:4000/repos/tenant1/git/commits/abc123")
}

pub fn ref_url_strips_refs_prefix_test() {
  rest.ref_url("http://localhost:4000", "tenant1", "refs/heads/main")
  |> expect.to_equal("http://localhost:4000/repos/tenant1/git/refs/heads/main")
}

pub fn ref_url_keeps_path_without_refs_prefix_test() {
  rest.ref_url("http://localhost:4000", "tenant1", "heads/main")
  |> expect.to_equal("http://localhost:4000/repos/tenant1/git/refs/heads/main")
}

pub fn build_ref_path_test() {
  rest.build_ref_path(["heads", "main"]) |> expect.to_equal("refs/heads/main")
}

pub fn tree_response_test() {
  rest.format_tree_response("http://localhost:4000", "t", "root", [
    rest.TreeEntry("file", "100644", "blob", "blob"),
    rest.TreeEntry("dir", "040000", "tree", "tree"),
    rest.TreeEntry("unknown", "0", "other", "other"),
  ])
  |> protocol_checks.assert_json(
    "{\"sha\":\"root\",\"url\":\"http://localhost:4000/repos/t/git/trees/root\",\"tree\":[{\"path\":\"file\",\"mode\":\"100644\",\"sha\":\"blob\",\"type\":\"blob\",\"url\":\"http://localhost:4000/repos/t/git/blobs/blob\"},{\"path\":\"dir\",\"mode\":\"040000\",\"sha\":\"tree\",\"type\":\"tree\",\"url\":\"http://localhost:4000/repos/t/git/trees/tree\"},{\"path\":\"unknown\",\"mode\":\"0\",\"sha\":\"other\",\"type\":\"other\",\"url\":null}]}",
  )
}

pub fn commit_response_preserves_nested_payloads_test() {
  rest.format_commit_response(
    "http://localhost:4000",
    "t",
    "commit",
    "tree",
    ["parent"],
    json.string("Initial commit"),
    json.object([#("name", json.string("Author"))]),
    json.null(),
  )
  |> protocol_checks.assert_json(
    "{\"sha\":\"commit\",\"tree\":{\"sha\":\"tree\",\"url\":\"http://localhost:4000/repos/t/git/trees/tree\"},\"parents\":[{\"sha\":\"parent\",\"url\":\"http://localhost:4000/repos/t/git/commits/parent\"}],\"message\":\"Initial commit\",\"author\":{\"name\":\"Author\"},\"committer\":null,\"url\":\"http://localhost:4000/repos/t/git/commits/commit\"}",
  )
}

pub fn ref_response_test() {
  rest.format_ref_response("http://localhost:4000", "t", "refs/heads/main", "c")
  |> protocol_checks.assert_json(
    "{\"ref\":\"refs/heads/main\",\"object\":{\"sha\":\"c\",\"type\":\"commit\",\"url\":\"http://localhost:4000/repos/t/git/commits/c\"},\"url\":\"http://localhost:4000/repos/t/git/refs/heads/main\"}",
  )
}

pub fn document_response_test() {
  rest.format_document_response("doc-1", "tenant1", 5)
  |> protocol_checks.assert_json(
    "{\"id\":\"doc-1\",\"tenantId\":\"tenant1\",\"sequenceNumber\":5}",
  )
}

pub fn session_info_test() {
  rest.session_info("http://localhost:4000", "t", "d", True)
  |> protocol_checks.assert_json(
    "{\"ordererUrl\":\"http://localhost:4000/socket\",\"historianUrl\":\"http://localhost:4000/repos/t\",\"deltaStreamUrl\":\"http://localhost:4000/deltas/t/d\",\"isSessionAlive\":true,\"isSessionActive\":true}",
  )
  rest.session_info("http://localhost:4000", "t", "d", False)
  |> json.to_string
  |> json.parse(decode.at(["isSessionActive"], decode.bool))
  |> expect.to_equal(Ok(False))
}

pub fn delta_data_rules_test() {
  rest.requires_data_field("join") |> expect.to_equal(True)
  rest.requires_data_field("leave") |> expect.to_equal(True)
  rest.requires_data_field("op") |> expect.to_equal(False)
  rest.requires_data_field("summarize") |> expect.to_equal(False)
}

pub fn delta_operation_omits_data_test() {
  rest.format_delta_message(delta_message("op", Some("c1"), Some("ignored")))
  |> protocol_checks.assert_json(
    "{\"sequenceNumber\":1,\"clientSequenceNumber\":-1,\"minimumSequenceNumber\":0,\"clientId\":\"c1\",\"referenceSequenceNumber\":0,\"type\":\"op\",\"contents\":{},\"metadata\":null,\"timestamp\":1700000000}",
  )
}

pub fn delta_join_includes_stringified_data_test() {
  rest.format_delta_message(delta_message(
    "join",
    None,
    Some("{\"clientId\":\"c1\"}"),
  ))
  |> protocol_checks.assert_json(
    "{\"sequenceNumber\":1,\"clientSequenceNumber\":-1,\"minimumSequenceNumber\":0,\"clientId\":null,\"referenceSequenceNumber\":0,\"type\":\"join\",\"contents\":{},\"metadata\":null,\"timestamp\":1700000000,\"data\":\"{\\\"clientId\\\":\\\"c1\\\"}\"}",
  )
}

fn delta_message(
  message_type: String,
  client_id: Option(String),
  data: Option(String),
) -> types.SequencedDocumentMessage(json.Json) {
  types.SequencedDocumentMessage(
    client_id:,
    sequence_number: 1,
    minimum_sequence_number: 0,
    client_sequence_number: -1,
    reference_sequence_number: 0,
    message_type:,
    contents: json.object([]),
    metadata: None,
    server_metadata: None,
    origin: None,
    traces: None,
    timestamp: 1_700_000_000,
    data:,
  )
}
