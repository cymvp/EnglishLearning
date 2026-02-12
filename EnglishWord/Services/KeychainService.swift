import Foundation
import Security

enum KeychainService {

    // MARK: - Multi-provider API

    static func save(apiKey: String, for provider: AIProvider) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainServiceName,
            kSecAttrAccount as String: keychainAccount(for: provider)
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func getAPIKey(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainServiceName,
            kSecAttrAccount as String: keychainAccount(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func deleteAPIKey(for provider: AIProvider) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainServiceName,
            kSecAttrAccount as String: keychainAccount(for: provider)
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Legacy (backward compatible, delegates to .claude)

    static func save(apiKey: String) -> Bool {
        save(apiKey: apiKey, for: .claude)
    }

    static func getAPIKey() -> String? {
        getAPIKey(for: .claude)
    }

    static func deleteAPIKey() -> Bool {
        deleteAPIKey(for: .claude)
    }

    // MARK: - Private

    private static func keychainAccount(for provider: AIProvider) -> String {
        switch provider {
        case .claude: return Constants.keychainAccountName
        case .openai: return Constants.keychainOpenAIAccountName
        }
    }
}
