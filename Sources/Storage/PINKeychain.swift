import Foundation
import Security

/// The only file in the app that contains a Keychain query dictionary, and the only file that ever
/// sees the PIN's digits as a string. `PIN` itself is deliberately not `Codable` and not printable,
/// so the conversion can only happen here.
///
/// There is no salt and no digest: a 4–6 digit space is trivially brute-forced by anyone who can
/// already read the Keychain item, and an attacker who can read it can bypass the UI anyway. The
/// boundary that actually buys something is the Keychain's own at-rest encryption and per-app ACL.
///
/// **Fails open by design.** If the item is missing — first run, the viewer cleared it, or the
/// system dropped it — `configuredLength` is nil and settings open freely. Failing closed would
/// lock a household out of their own television with no recovery short of deleting the app.
struct PINKeychain: PINOracle {
    private let service = "com.nostalgiavision.pin"
    private let account = "settings"

    var configuredLength: Int? {
        storedDigits().map(\.count)
    }

    func accepts(_ candidate: PIN) -> Bool {
        guard let stored = storedDigits() else { return false }
        return stored == string(from: candidate)
    }

    func save(_ pin: PIN?) {
        SecItemDelete(baseQuery() as CFDictionary)
        guard let pin, let data = string(from: pin).data(using: .utf8) else { return }
        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private func string(from pin: PIN) -> String {
        pin.digits.map { String($0.value) }.joined()
    }

    private func storedDigits() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty
        else { return nil }
        return text
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
