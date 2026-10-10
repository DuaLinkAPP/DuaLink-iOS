// SPDX-License-Identifier: MPL-2.0
import CryptoKit
import Foundation

/// Harmony's wire key is an uncompressed X9.63 point (0x04 || X || Y).
/// SecurityMessage expects CryptoKit's raw point (X || Y), which omits 0x04.
nonisolated enum LabP256PublicKey {
    static func appleRawRepresentation(fromWireKey key: Data) throws -> Data {
        guard key.count == 65, key.first == 0x04 else { throw LabProtocolError.invalidKey }
        // Parse the point as well as its length so an invalid curve point is rejected.
        return try P256.KeyAgreement.PublicKey(x963Representation: key).rawRepresentation
    }
}
