import gleam/dynamic
import spillway/rest
import startest/expect

fn term(value: String) -> rest.JsonTerm {
  rest.json_term(dynamic.string(value))
}

fn term_int(value: Int) -> rest.JsonTerm {
  rest.json_term(dynamic.int(value))
}

fn term_bool(value: Bool) -> rest.JsonTerm {
  rest.json_term(dynamic.bool(value))
}

fn term_nil() -> rest.JsonTerm {
  rest.json_term(dynamic.nil())
}

// ─────────────────────────────────────────────────────────────────────────────
// base_url / object URL construction
// ─────────────────────────────────────────────────────────────────────────────

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

pub fn blob_url_test() {
  rest.blob_url("http://localhost:4000", "tenant1", "abc123")
  |> expect.to_equal("http://localhost:4000/repos/tenant1/git/blobs/abc123")
}

pub fn tree_url_test() {
  rest.tree_url("http://localhost:4000", "tenant1", "abc123")
  |> expect.to_equal("http://localhost:4000/repos/tenant1/git/trees/abc123")
}

pub fn commit_url_test() {
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

pub fn build_ref_path_joins_wildcard_segments_test() {
  rest.build_ref_path(["heads", "main"])
  |> expect.to_equal("refs/heads/main")
}

// ─────────────────────────────────────────────────────────────────────────────
// Git object response shaping
// ─────────────────────────────────────────────────────────────────────────────

pub fn format_blob_response_test() {
  let fields =
    rest.format_blob_response(
      "http://localhost:4000",
      "tenant1",
      "sha1",
      11,
      "aGVsbG8gd29ybGQ=",
    )

  fields
  |> expect.to_equal([
    #("sha", term("sha1")),
    #("size", term_int(11)),
    #("content", term("aGVsbG8gd29ybGQ=")),
    #("encoding", term("base64")),
    #("url", term("http://localhost:4000/repos/tenant1/git/blobs/sha1")),
  ])
}

pub fn format_tree_response_builds_entry_urls_by_type_test() {
  let entries = [
    #("file.txt", "100644", "blobsha", "blob"),
    #("subdir", "040000", "treesha", "tree"),
  ]

  // case instead of let assert: startest's rescue wraps let-assert values
  // in Ok(), so non-Ok patterns never match.
  case
    rest.format_tree_response(
      "http://localhost:4000",
      "tenant1",
      "roottree",
      entries,
    )
  {
    [#("sha", _), #("url", _), #("tree", tree_dynamic)] ->
      // The tree field is a Dynamic-wrapped list; classify proves the shape
      // without needing a full decode.
      dynamic.classify(rest.json_term_to_dynamic(tree_dynamic))
      |> expect.to_equal("List")
    _ -> panic as "expected [sha, url, tree] fields"
  }
}

pub fn format_commit_response_shape_test() {
  let author = term("author-placeholder")
  let committer = term("committer-placeholder")
  let message = term("Initial commit")

  let fields =
    rest.format_commit_response(
      "http://localhost:4000",
      "tenant1",
      "commitsha",
      "treesha",
      ["parent1", "parent2"],
      message,
      author,
      committer,
    )

  case fields {
    [
      #("sha", sha),
      #("tree", _tree),
      #("parents", parents),
      #("message", msg),
      #("author", auth),
      #("committer", committer_out),
      #("url", url),
    ] -> {
      sha |> expect.to_equal(term("commitsha"))
      msg |> expect.to_equal(message)
      auth |> expect.to_equal(author)
      committer_out |> expect.to_equal(committer)
      url
      |> expect.to_equal(term(
        "http://localhost:4000/repos/tenant1/git/commits/commitsha",
      ))
      dynamic.classify(rest.json_term_to_dynamic(parents))
      |> expect.to_equal("List")
    }
    _ -> panic as "unexpected commit response shape"
  }
}

pub fn format_ref_response_shape_test() {
  let fields =
    rest.format_ref_response(
      "http://localhost:4000",
      "tenant1",
      "refs/heads/main",
      "commitsha",
    )

  case fields {
    [#("ref", ref_field), #("object", _object), #("url", url_field)] -> {
      ref_field |> expect.to_equal(term("refs/heads/main"))
      url_field
      |> expect.to_equal(term(
        "http://localhost:4000/repos/tenant1/git/refs/heads/main",
      ))
    }
    _ -> panic as "unexpected ref response shape"
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Document / session response shaping
// ─────────────────────────────────────────────────────────────────────────────

pub fn format_document_response_test() {
  rest.format_document_response("doc-1", "tenant1", 5)
  |> expect.to_equal([
    #("id", term("doc-1")),
    #("tenantId", term("tenant1")),
    #("sequenceNumber", term_int(5)),
  ])
}

pub fn session_info_alive_test() {
  rest.session_info("http://localhost:4000", "tenant1", "doc-1", True)
  |> expect.to_equal([
    #("ordererUrl", term("http://localhost:4000/socket")),
    #("historianUrl", term("http://localhost:4000/repos/tenant1")),
    #("deltaStreamUrl", term("http://localhost:4000/deltas/tenant1/doc-1")),
    #("isSessionAlive", term_bool(True)),
    #("isSessionActive", term_bool(True)),
  ])
}

pub fn session_info_not_alive_test() {
  rest.session_info("http://localhost:4000", "tenant1", "doc-1", False)
  |> expect.to_equal([
    #("ordererUrl", term("http://localhost:4000/socket")),
    #("historianUrl", term("http://localhost:4000/repos/tenant1")),
    #("deltaStreamUrl", term("http://localhost:4000/deltas/tenant1/doc-1")),
    #("isSessionAlive", term_bool(False)),
    #("isSessionActive", term_bool(False)),
  ])
}

// ─────────────────────────────────────────────────────────────────────────────
// Delta (operation history) response shaping
// ─────────────────────────────────────────────────────────────────────────────

pub fn requires_data_field_for_join_and_leave_test() {
  rest.requires_data_field("join") |> expect.to_equal(True)
  rest.requires_data_field("leave") |> expect.to_equal(True)
  rest.requires_data_field("op") |> expect.to_equal(False)
  rest.requires_data_field("summarize") |> expect.to_equal(False)
}

pub fn format_delta_message_op_omits_data_field_test() {
  let contents = term("some-op-contents")
  let metadata = term_nil()
  let client_id = term("client-1")

  let fields =
    rest.format_delta_message(
      1,
      1,
      0,
      client_id,
      0,
      "op",
      contents,
      metadata,
      1_700_000_000,
      term_nil(),
    )

  fields
  |> expect.to_equal([
    #("sequenceNumber", term_int(1)),
    #("clientSequenceNumber", term_int(1)),
    #("minimumSequenceNumber", term_int(0)),
    #("clientId", client_id),
    #("referenceSequenceNumber", term_int(0)),
    #("type", term("op")),
    #("contents", contents),
    #("metadata", metadata),
    #("timestamp", term_int(1_700_000_000)),
  ])
}

pub fn format_delta_message_join_includes_data_field_test() {
  let contents = term("{\"clientId\":\"client-1\"}")
  let metadata = term_nil()
  let client_id = term_nil()
  let data = term("{\"clientId\":\"client-1\"}")

  let fields =
    rest.format_delta_message(
      1,
      -1,
      0,
      client_id,
      0,
      "join",
      contents,
      metadata,
      1_700_000_000,
      data,
    )

  case fields {
    [
      #("sequenceNumber", _),
      #("clientSequenceNumber", _),
      #("minimumSequenceNumber", _),
      #("clientId", _),
      #("referenceSequenceNumber", _),
      #("type", type_field),
      #("contents", _),
      #("metadata", _),
      #("timestamp", _),
      #("data", data_field),
    ] -> {
      type_field |> expect.to_equal(term("join"))
      data_field |> expect.to_equal(data)
    }
    _ -> panic as "expected a trailing data field on join"
  }
}
