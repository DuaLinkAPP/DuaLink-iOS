// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation
import Testing
@testable import NotificationLabCore

@Test func harmonyX963PublicKeyConvertsToAppleRawPoint() throws {
    let publicKey = P256.KeyAgreement.PrivateKey().publicKey
    let wireKey = publicKey.x963Representation
    #expect(wireKey.count == 65)
    #expect(wireKey.first == 0x04)

    // This was the failing boundary: CryptoKit's raw initializer rejects wireKey.
    #expect(throws: CryptoKitError.incorrectParameterSize) {
        try P256.KeyAgreement.PublicKey(rawRepresentation: wireKey)
    }
    let systemKey = try LabP256PublicKey.appleRawRepresentation(fromWireKey: wireKey)
    #expect(systemKey.count == 64)
    #expect(systemKey == publicKey.rawRepresentation)
    #expect(try P256.KeyAgreement.PublicKey(rawRepresentation: systemKey).x963Representation == wireKey)
}

@Test func rejectsMalformedHarmonyPublicKey() {
    let rawKey = P256.KeyAgreement.PrivateKey().publicKey.rawRepresentation
    #expect(throws: LabProtocolError.invalidKey) {
        try LabP256PublicKey.appleRawRepresentation(fromWireKey: rawKey)
    }
    #expect(throws: (any Error).self) {
        try LabP256PublicKey.appleRawRepresentation(fromWireKey: Data([0x04] + Array(repeating: 0, count: 64)))
    }
}

@Test func appleHPKEEncapsulationKeepsThe65ByteHarmonyWireFormat() throws {
    let accessoryKey = P256.KeyAgreement.PrivateKey()
    let systemKey = try LabP256PublicKey.appleRawRepresentation(fromWireKey: accessoryKey.publicKey.x963Representation)
    let info = Data("p256-Version1-00000000-0000-0000-0000-000000000001".utf8)
    let sender = try HPKE.Sender(recipientKey: P256.KeyAgreement.PublicKey(rawRepresentation: systemKey),
                                 ciphersuite: .P256_SHA256_AES_GCM_256, info: info)
    #expect(sender.encapsulatedKey.count == 65)
    #expect(sender.encapsulatedKey.first == 0x04)
    let recipient = try HPKE.Recipient(privateKey: accessoryKey, ciphersuite: .P256_SHA256_AES_GCM_256,
                                      info: info, encapsulatedKey: sender.encapsulatedKey)
    // Verify both directions after conversion, using Apple's documented exporter context.
    for direction in ["HostToAccessory", "AccessoryToHost"] {
        let context = info + Data("-\(direction)-00000000-0000-0000-0000-000000000002".utf8)
        #expect(try sender.exportSecret(context: context, outputByteCount: 32) ==
                    recipient.exportSecret(context: context, outputByteCount: 32))
    }
}
