import protocol_checks
import readme_examples

pub fn wire_contracts_test() {
  protocol_checks.wire_contracts()
}

pub fn signal_decoding_contracts_test() {
  protocol_checks.signal_decoding()
}

pub fn portable_domain_contracts_test() {
  protocol_checks.domain_contracts()
}

pub fn documentation_examples_test() {
  readme_examples.run()
}
