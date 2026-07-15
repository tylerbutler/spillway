import gleam/dict
import gleam/dynamic
import gleam/option
import gleam/string
import spillway
import spillway/nack
import spillway/sequencing
import spillway/session_logic
import spillway/signals
import startest
import startest/expect

pub fn main() -> Nil {
  startest.run(startest.default_config())
}

// ─────────────────────────────────────────────────────────────────────────────
// Sequencing Tests
// ─────────────────────────────────────────────────────────────────────────────

pub fn new_sequence_state_starts_at_zero_test() {
  let state = spillway.new_sequence_state()
  spillway.current_sn(state) |> expect.to_equal(0)
  spillway.current_msn(state) |> expect.to_equal(0)
  spillway.client_count(state) |> expect.to_equal(0)
}

pub fn client_join_test() {
  let state = spillway.new_sequence_state()
  let state = spillway.client_join(state, "client-1", 0)

  spillway.client_count(state) |> expect.to_equal(1)
  spillway.is_client_connected(state, "client-1") |> expect.to_be_true()
  spillway.is_client_connected(state, "client-2") |> expect.to_be_false()
}

pub fn assign_sequence_number_test() {
  let state = spillway.new_sequence_state()
  let state = spillway.client_join(state, "client-1", 0)

  let assert sequencing.SequenceOk(new_state, assigned_sn, msn) =
    sequencing.assign_sequence_number(state, "client-1", 1, 0)

  assigned_sn |> expect.to_equal(1)
  msn |> expect.to_equal(0)
  spillway.current_sn(new_state) |> expect.to_equal(1)
}

pub fn multiple_ops_increment_sn_test() {
  let state = spillway.new_sequence_state()
  let state = spillway.client_join(state, "client-1", 0)

  let assert sequencing.SequenceOk(state, sn, _) =
    sequencing.assign_sequence_number(state, "client-1", 1, 0)
  sn |> expect.to_equal(1)

  let assert sequencing.SequenceOk(state, sn, _) =
    sequencing.assign_sequence_number(state, "client-1", 2, 1)
  sn |> expect.to_equal(2)

  spillway.current_sn(state) |> expect.to_equal(2)
}

pub fn invalid_csn_rejected_test() {
  let state = spillway.new_sequence_state()
  let state = spillway.client_join(state, "client-1", 0)

  let assert sequencing.SequenceOk(state, _, _) =
    sequencing.assign_sequence_number(state, "client-1", 1, 0)

  case sequencing.assign_sequence_number(state, "client-1", 1, 1) {
    sequencing.SequenceError(sequencing.InvalidCsn(_, _)) -> Nil
    other ->
      panic as { "Expected InvalidCsn error, got: " <> string.inspect(other) }
  }
}

pub fn client_leave_test() {
  let state = spillway.new_sequence_state()
  let state = spillway.client_join(state, "client-1", 0)
  let state = spillway.client_join(state, "client-2", 0)

  spillway.client_count(state) |> expect.to_equal(2)

  let state = spillway.client_leave(state, "client-1")

  spillway.client_count(state) |> expect.to_equal(1)
  spillway.is_client_connected(state, "client-1") |> expect.to_be_false()
  spillway.is_client_connected(state, "client-2") |> expect.to_be_true()
}

pub fn msn_tracks_minimum_rsn_across_clients_test() {
  let state = spillway.new_sequence_state()

  let state = spillway.client_join(state, "client-1", 0)

  let assert sequencing.SequenceOk(state, _, msn) =
    sequencing.assign_sequence_number(state, "client-1", 1, 0)
  msn |> expect.to_equal(0)

  let state = spillway.client_join(state, "client-2", 1)

  let assert sequencing.SequenceOk(state, _, msn) =
    sequencing.assign_sequence_number(state, "client-2", 1, 1)
  msn |> expect.to_equal(0)

  let assert sequencing.SequenceOk(_, _, msn) =
    sequencing.assign_sequence_number(state, "client-1", 2, 2)
  msn |> expect.to_equal(1)
}

// ─────────────────────────────────────────────────────────────────────────────
// Session Logic Tests
// ─────────────────────────────────────────────────────────────────────────────

// -- Feature Negotiation --

pub fn negotiate_features_both_support_test() {
  let server = dict.from_list([#("submit_signals_v2", True)])
  let client = dict.from_list([#("submit_signals_v2", True)])

  let result = session_logic.negotiate_features(server, client)
  dict.get(result, "submit_signals_v2") |> expect.to_equal(Ok(True))
}

pub fn negotiate_features_client_declines_test() {
  let server = dict.from_list([#("submit_signals_v2", True)])
  let client = dict.from_list([#("submit_signals_v2", False)])

  let result = session_logic.negotiate_features(server, client)
  dict.get(result, "submit_signals_v2") |> expect.to_equal(Ok(False))
}

pub fn negotiate_features_client_unspecified_test() {
  let server = dict.from_list([#("submit_signals_v2", True)])
  let client = dict.new()

  let result = session_logic.negotiate_features(server, client)
  dict.get(result, "submit_signals_v2") |> expect.to_equal(Ok(True))
}

// -- Version Negotiation --

pub fn negotiate_version_match_test() {
  let result = session_logic.negotiate_version(["^0.1.0", "^1.0.0"], ["^0.1.0"])
  result |> expect.to_equal("0.1.0")
}

pub fn negotiate_version_1_0_test() {
  let result = session_logic.negotiate_version(["^0.1.0", "^1.0.0"], ["^1.0.0"])
  result |> expect.to_equal("1.0.0")
}

pub fn negotiate_version_fallback_test() {
  let result = session_logic.negotiate_version(["^0.1.0", "^1.0.0"], ["^2.0.0"])
  result |> expect.to_equal("0.1.0")
}

pub fn negotiate_version_empty_client_test() {
  let result = session_logic.negotiate_version(["^0.1.0", "^1.0.0"], [])
  result |> expect.to_equal("0.1.0")
}

// -- Validate Summarize Contents --

pub fn validate_summarize_contents_all_present_test() {
  let contents =
    dict.from_list([
      #("handle", coerce("h1")),
      #("message", coerce("msg")),
      #("parents", coerce([])),
      #("head", coerce("sha")),
    ])

  session_logic.validate_summarize_contents(contents)
  |> expect.to_be_ok()
}

pub fn validate_summarize_contents_missing_fields_test() {
  let contents = dict.from_list([#("handle", coerce("h1"))])

  case session_logic.validate_summarize_contents(contents) {
    Error(msg) -> {
      string.contains(msg, "message") |> expect.to_be_true()
      string.contains(msg, "parents") |> expect.to_be_true()
      string.contains(msg, "head") |> expect.to_be_true()
    }
    Ok(_) -> panic as "Expected Error, got Ok"
  }
}

// -- Determine Signal Recipients --

pub fn signal_recipients_broadcast_test() {
  let result =
    session_logic.determine_signal_recipients(
      "sender",
      option.None,
      option.None,
      option.None,
      ["sender", "a", "b", "c"],
    )
  result |> expect.to_equal(["a", "b", "c"])
}

pub fn signal_recipients_targeted_test() {
  let result =
    session_logic.determine_signal_recipients(
      "sender",
      option.Some(["a", "c"]),
      option.None,
      option.None,
      ["sender", "a", "b", "c"],
    )
  result |> expect.to_equal(["a", "c"])
}

pub fn signal_recipients_ignored_test() {
  let result =
    session_logic.determine_signal_recipients(
      "sender",
      option.None,
      option.Some(["b"]),
      option.None,
      ["sender", "a", "b", "c"],
    )
  result |> expect.to_equal(["a", "c"])
}

pub fn signal_recipients_single_target_test() {
  let result =
    session_logic.determine_signal_recipients(
      "sender",
      option.None,
      option.None,
      option.Some("b"),
      ["sender", "a", "b", "c"],
    )
  result |> expect.to_equal(["b"])
}

pub fn signal_recipients_single_target_is_sender_test() {
  let result =
    session_logic.determine_signal_recipients(
      "sender",
      option.None,
      option.None,
      option.Some("sender"),
      ["sender", "a", "b"],
    )
  result |> expect.to_equal([])
}

pub fn signal_recipients_targeted_excludes_sender_test() {
  let result =
    session_logic.determine_signal_recipients(
      "sender",
      option.Some(["sender", "a"]),
      option.None,
      option.None,
      ["sender", "a", "b"],
    )
  result |> expect.to_equal(["a"])
}

// -- Add To History --

pub fn add_to_history_prepends_test() {
  let history = [2, 1]
  let result = session_logic.add_to_history(3, history, 10)
  result |> expect.to_equal([3, 2, 1])
}

pub fn add_to_history_trims_to_max_test() {
  let history = [3, 2, 1]
  let result = session_logic.add_to_history(4, history, 3)
  result |> expect.to_equal([4, 3, 2])
}

// ─────────────────────────────────────────────────────────────────────────────
// Nack Tests
// ─────────────────────────────────────────────────────────────────────────────

pub fn nack_unknown_client_test() {
  let n = nack.unknown_client("client-42")
  n.content.code |> expect.to_equal(400)
  n.content.message |> expect.to_equal("Unknown client: client-42")
  n.sequence_number |> expect.to_equal(-1)
}

pub fn nack_read_only_client_test() {
  let n = nack.read_only_client(option.None)
  n.content.code |> expect.to_equal(400)
  n.content.message |> expect.to_equal("Client is in read-only mode")
}

pub fn nack_invalid_csn_test() {
  let n = nack.invalid_csn(5, 3, option.None)
  n.content.code |> expect.to_equal(400)
  string.contains(n.content.message, "5") |> expect.to_be_true()
  string.contains(n.content.message, "3") |> expect.to_be_true()
}

pub fn nack_invalid_rsn_test() {
  let n = nack.invalid_rsn(10, 5, option.None)
  n.content.code |> expect.to_equal(400)
  string.contains(n.content.message, "10") |> expect.to_be_true()
  string.contains(n.content.message, "5") |> expect.to_be_true()
}

pub fn nack_error_type_roundtrip_test() {
  nack.nack_error_type_to_string(nack.BadRequestError)
  |> nack.nack_error_type_from_string()
  |> expect.to_equal(Ok(nack.BadRequestError))

  nack.nack_error_type_to_string(nack.ThrottlingError)
  |> nack.nack_error_type_from_string()
  |> expect.to_equal(Ok(nack.ThrottlingError))
}

// ─────────────────────────────────────────────────────────────────────────────
// Signal Normalization Tests
// ─────────────────────────────────────────────────────────────────────────────

pub fn normalize_v2_signal_test() {
  let raw =
    dict.from_list([
      #("content", coerce("hello")),
      #("type", coerce("myType")),
      #("clientConnectionNumber", coerce(42)),
    ])

  let result = signals.normalize_signal(raw)
  result.signal_type |> expect.to_equal(option.Some("myType"))
  result.client_connection_number |> expect.to_equal(option.Some(42))
  result.target_client_id |> expect.to_equal(option.None)
}

pub fn normalize_v1_signal_test() {
  let raw =
    dict.from_list([
      #("address", coerce("")),
      #(
        "contents",
        coerce(
          dict.from_list([
            #("type", coerce("v1Type")),
            #("content", coerce("data")),
          ]),
        ),
      ),
      #("clientBroadcastSignalSequenceNumber", coerce(7)),
    ])

  let result = signals.normalize_signal(raw)
  result.signal_type |> expect.to_equal(option.Some("v1Type"))
  result.client_connection_number |> expect.to_equal(option.Some(7))
  result.targeted_clients |> expect.to_equal(option.None)
}

pub fn normalize_v2_envelope_signal_test() {
  let inner =
    dict.from_list([
      #("content", coerce("payload")),
      #("type", coerce("sigType")),
    ])

  let raw =
    dict.from_list([
      #("signal", coerce(inner)),
      #("targetedClients", coerce(["a", "b"])),
    ])

  let result = signals.normalize_signal(raw)
  result.signal_type |> expect.to_equal(option.Some("sigType"))
  result.targeted_clients |> expect.to_equal(option.Some(["a", "b"]))
}

// Helper for tests - coerce a value to Dynamic
@external(erlang, "gleam_stdlib", "identity")
fn coerce(value: a) -> dynamic.Dynamic
