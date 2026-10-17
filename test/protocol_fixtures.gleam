//// Target-independent examples of the existing Fluid wire contract.

pub const blob = "{\"sha\":\"sha1\",\"size\":11,\"content\":\"aGVsbG8gd29ybGQ=\",\"encoding\":\"base64\",\"url\":\"http://localhost:4000/repos/tenant1/git/blobs/sha1\"}"

pub const summary_ack = "{\"clientId\":null,\"sequenceNumber\":11,\"minimumSequenceNumber\":5,\"clientSequenceNumber\":-1,\"referenceSequenceNumber\":10,\"type\":\"summaryAck\",\"contents\":{\"handle\":\"handle-1\",\"summaryProposal\":{\"summarySequenceNumber\":10}},\"metadata\":null,\"timestamp\":1000}"

pub const operation = "{\"clientId\":\"c1\",\"sequenceNumber\":11,\"minimumSequenceNumber\":5,\"clientSequenceNumber\":2,\"referenceSequenceNumber\":10,\"type\":\"op\",\"contents\":{\"text\":\"water 🌊\",\"items\":[1,null,true,{}]},\"metadata\":null,\"timestamp\":1000}"

pub const signal_v1 = "{\"address\":\"\",\"contents\":{\"type\":\"cursor\",\"content\":{\"x\":1}},\"clientBroadcastSignalSequenceNumber\":7}"

pub const signal_v2 = "{\"signal\":{\"content\":{\"x\":1},\"type\":\"cursor\",\"clientConnectionNumber\":7},\"targetedClients\":[\"c2\"]}"

pub const normalized_signal = "{\"content\":{\"x\":1},\"type\":\"cursor\",\"clientConnectionNumber\":7,\"referenceSequenceNumber\":null,\"targetClientId\":null,\"targetedClients\":[\"c2\"],\"ignoredClients\":null}"

pub const connection = "{\"tenantId\":\"tenant-a\",\"id\":\"doc-a\",\"token\":\"token-a\",\"mode\":\"write\"}"

pub const op_frame = "42[\"op\",\"doc-1\",[]]"
