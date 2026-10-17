# Spillway

Spillway provides Fluid Framework protocol logic in Gleam. Use the same
library on Erlang, Node.js, and browsers.

Your application owns networking, storage, JWT signature verification, clocks,
and document lifetime. Use Spillway for sequencing, connection checks, signals,
summaries, nacks, REST response JSON, and Socket.IO text framing.

## Install

Use Gleam 1.14 or later. Add a Git dependency to `gleam.toml`, then run
`gleam deps download`. Pin a commit for reproducible application builds.

```toml
[dependencies]
spillway = { git = "https://github.com/tylerbutler/spillway", ref = "main" }
```

Spillway depends on `gleam_stdlib`, `gleam_json`, Signet, and Windsock.
Signet supplies identity types, scopes, and claim validation. Windsock supplies
Socket.IO event framing. Spillway pins both Git dependencies to commits.

## Sequence operations

Import domain modules and use their constructors. Sequence assignment returns
the standard `Result` type with a named success record.

```gleam
import spillway/sequencing

pub fn sequence() {
  let state =
    sequencing.new()
    |> sequencing.client_join("client-7", 0)

  sequencing.assign_sequence_number(state, "client-7", 1, 0)
}
```

Match `Ok(sequencing.SequenceAssignment(next_state, assigned_sn, minimum_sn))`
or `Error(reason)`. Pass the returned state to the next operation. Reserve a
sequence number with `sequencing.reserve_sequence_number` for a server message.

## Decode and encode signals

Decode input into a typed payload. Supply an encoder when you send it.
You do not need native Erlang terms or JavaScript object conversion.

```gleam
import gleam/dynamic/decode
import gleam/json
import gleam/result
import spillway/signals

pub fn signal_json(text: String) {
  use signal <- result.try(
    json.parse(text, signals.decoder(decode.string)),
  )
  Ok(signals.normalized_to_json(signal, json.string))
}
```

This example accepts a string payload such as `{"content":"hello"}`. For an
application record, pass its decoder and encoder instead. Use
`signals.parse_batch(text, content_decoder)` for a singleton, an array, or
JSON-stringified legacy envelopes inside an array. Use
`signals.normalize_signal_batch` for data you have decoded into `Dynamic`.

Malformed signal fields return decode errors with field paths. Batch errors
also identify the zero-based item index. A valid empty batch returns `Ok([])`;
an invalid item fails the batch. Missing or null optional fields become `None`.
The normalized encoder writes those fields as JSON null. Required fields and
present optional fields of the wrong type fail decoding.

## Build wire responses

REST builders return complete `gleam/json.Json` objects. Pass them to
`json.to_string`, your HTTP response adapter, or a Socket.IO encoder:

```gleam
import gleam/json
import spillway/rest
import spillway/socketio

pub fn response_json() {
  rest.format_document_response("doc-1", "tenant-1", 5)
  |> json.to_string
}

pub fn signal_frame() {
  socketio.encode_signal(json.object([#("content", json.string("hello"))]))
}
```

Use `rest.TreeEntry` for tree entries and
`types.SequencedDocumentMessage(Json)` with `rest.format_delta_message`.
Delta output retains the existing REST fields; it includes `data` for join and
leave messages only. Set `data` to a JSON-stringified sidecar string.
Missing client IDs and metadata encode as null. Optional `data` encodes as null
for a system message without a sidecar.

`DocumentMessage(payload)`, `SequencedDocumentMessage(payload)`, `Nack(payload)`,
and the signal records accept caller-owned payload types. Spillway does not
guess how to serialize a `Dynamic` value. Use typed values and explicit
encoders at output boundaries.

## Check connections and claims

Use `connect_document.decoder()` with `json.parse`, or
`connect_document.parse_request` with `Dynamic`. The decoded request includes
an optional typed mode. Unknown mode strings and malformed required fields
return errors. An absent or null mode makes no additional write-scope demand.

Pass `request.mode` and typed Signet scopes to
`connect_document.validate_mode_scope`. Use `types.scope_decoder()` to decode
known scope strings; unknown scopes fail decoding.

Import `signet/claims` for tenant, document, expiration, and permission checks.
Use `signet/types.DocRead` and `signet/types.DocWrite` rather than strings.
These checks do not verify token signatures. Your application must verify
signatures before trusting claims.

The pure `signet/claims` module works in browsers. Signet's separate token
signing and signature-verification APIs use Node crypto on JavaScript;
Spillway does not import those APIs.

## Develop

The checked-in tool configuration uses Gleam 1.16, Erlang, Node 24, and pnpm 12.
Gleam defaults to Erlang; select JavaScript with `--target javascript`.
Both builds use the same public APIs and wire contracts.

```sh
gleam test --target erlang
gleam test --target javascript
pnpm install --frozen-lockfile
pnpm exec playwright install chromium
pnpm run test:browser
```

`just build` builds both targets. `just test` runs both test suites.
`just ci` checks formatting, tests, both builds, and real-browser contracts.
The browser check imports all public modules as ES modules without Node
polyfills. CI installs Chromium's system dependencies with Playwright.

Use `pnpm run dev` or `pnpm run build` for the documentation site.
Generate the protocol schema with
`gleam run --target erlang -m schema_cli` or the JavaScript target.
JavaScript uses safe integers through `2^53 - 1`; do not rely on Erlang's
larger integer range for shared sequence numbers or timestamps.

## Migration from the Elixir-facing API

This change removes the interop facade and changes source-level APIs.
Valid Fluid wire messages retain their field names and shapes.

| Previous API | Replacement |
| --- | --- |
| `spillway.new_sequence_state()` | `sequencing.new()` |
| `spillway.sequence_state_from_checkpoint` | `sequencing.from_checkpoint` |
| Root sequencing, validation, nack, summary, and session forwarding functions | Import the corresponding `spillway/*` module |
| `SequenceOk` / `SequenceError` result variants | `Ok(SequenceAssignment(...))` / `Error(reason)` |
| `spillway.write_mode()` and other constructor wrappers | `types.WriteMode`, `nack.ThrottlingError`, `summary.SummaryBlob(...)`, etc. |
| Root `jwt_validate_*`, `jwt_has_*`, and JWT error helpers | `signet/claims.validate_*`, `has_*`, `format_error`, `error_to_http_code` |
| Signet JWT validation error constructors under `jwt.*` | Import constructors from `signet/claims` |
| String scope arguments | Typed `signet/types.Scope`; decode strings at the boundary |
| `rest.JsonTerm`, `json_term`, `json_term_to_dynamic` | `gleam/json.Json` and its constructors |
| REST field lists and session map builders | Complete JSON values; call `json.to_string` when sending |
| `rest.TreeEntryIn` tuples | `rest.TreeEntry` records |
| Ten-argument `rest.format_delta_message` | A `types.SequencedDocumentMessage(Json)` argument |
| `signals.normalized_to_map` | `signals.normalized_to_json(signal, encode_content)` |
| Map-based `normalize_signal` / `parse_v1_envelope_from_map` | `signals.decoder` / `v1_decoder` with `json.parse` or `decode.run` |
| Infallible signal normalization / empty-list error fallback | `Result` with decode paths or `InvalidBatchItem(index, error)` |
| Raw-map connection scope checks | Decode with `connect_document.decoder`, then pass typed mode/scopes |
| `session_logic.validate_summarize_contents` | `summary.summarize_contents_decoder()` |
| `message.SignalMessage` / `message.SummaryContext` | `signals.SignalMessage(payload)` / `summary.SummaryContext` |
