import CryptoKit
import Foundation

/// Одноразовые коды по RFC 6238 (SHA-1, 6 цифр, 30 секунд) — как в Google Authenticator.
enum TOTP {
    static func code(secret: String, date: Date = Date(), digits: Int = 6, period: TimeInterval = 30) -> String? {
        guard let key = base32Decode(secret) else { return nil }

        var counter = UInt64(date.timeIntervalSince1970 / period).bigEndian
        let message = Data(bytes: &counter, count: MemoryLayout<UInt64>.size)
        let mac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: key)))

        let offset = Int(mac[mac.count - 1] & 0x0f)
        let truncated = mac[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) } & 0x7fff_ffff
        var modulo: UInt32 = 1
        for _ in 0..<digits { modulo *= 10 }

        let value = String(truncated % modulo)
        return String(repeating: "0", count: digits - value.count) + value
    }

    static func base32Decode(_ string: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var buffer: UInt64 = 0
        var bits = 0
        var bytes: [UInt8] = []

        for char in string.uppercased() where !"= -".contains(char) {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            buffer = (buffer << 5) | UInt64(index)
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((buffer >> UInt64(bits - 8)) & 0xff))
                bits -= 8
            }
        }
        return bytes.isEmpty ? nil : Data(bytes)
    }
}
