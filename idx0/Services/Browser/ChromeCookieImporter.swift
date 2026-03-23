import CommonCrypto
import Foundation
import Security
import SQLite3
import WebKit

private struct ChromeCookieRow {
    let host: String
    let name: String
    let value: String
    let encryptedValue: Data
    let path: String
    let expiresUTC: Int64
    let isSecure: Bool
    let isHTTPOnly: Bool
    let sameSite: Int
}

struct ChromeCookieDefinition: Sendable {
    let domain: String
    let path: String
    let name: String
    let value: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
    let sameSite: Int
}

enum ChromeCookieImporter {
    private static let chromeEpochOffsetSeconds = 11_644_473_600.0
    private static let chromeEncryptionPrefixV10 = Data([0x76, 0x31, 0x30]) // "v10"
    private static let chromeEncryptionPrefixV11 = Data([0x76, 0x31, 0x31]) // "v11"
    private static let chromePBKDF2Salt = Array("saltysalt".utf8)
    private static let chromePBKDF2Iterations: UInt32 = 1003
    private static let chromePBKDF2KeyLength = kCCKeySizeAES128

    // During XCTest runs we mock keychain reads to avoid macOS keychain UI prompts.
    // Set IDX0_USE_REAL_KEYCHAIN_IN_TESTS=1 to opt back into real keychain access.
    private static var shouldUseMockKeychain: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["XCTestConfigurationFilePath"] != nil else { return false }
        return environment["IDX0_USE_REAL_KEYCHAIN_IN_TESTS"] != "1"
    }

    static func loadCookieDefinitions() async -> [ChromeCookieDefinition] {
        await Task.detached(priority: .utility) {
            loadCookieDefinitionsSync()
        }.value
    }

    @MainActor
    static func hydrate(cookieStore: WKHTTPCookieStore) async -> Int {
        let definitions = await loadCookieDefinitions()
        guard !definitions.isEmpty else { return 0 }

        var imported = 0
        for definition in definitions {
            guard let cookie = makeCookie(from: definition) else { continue }
            await cookieStore.setCookie(cookie)
            imported += 1
        }
        return imported
    }

    private static func loadCookieDefinitionsSync() -> [ChromeCookieDefinition] {
        let now = Date()
        let databaseURLs = discoverCookieDatabaseURLs()
        guard !databaseURLs.isEmpty else { return [] }

        let decryptionKey = chromeCookieDecryptionKey()
        var definitions: [ChromeCookieDefinition] = []
        var dedupe: Set<String> = []

        for databaseURL in databaseURLs {
            let rows = readCookieRows(from: databaseURL)
            for row in rows {
                guard let definition = makeCookieDefinition(from: row, decryptionKey: decryptionKey, now: now) else { continue }
                let dedupeKey = "\(definition.domain)|\(definition.path)|\(definition.name)"
                if dedupe.insert(dedupeKey).inserted {
                    definitions.append(definition)
                }
            }
        }

        return definitions
    }

    private static func makeCookieDefinition(
        from row: ChromeCookieRow,
        decryptionKey: Data?,
        now: Date
    ) -> ChromeCookieDefinition? {
        guard !row.host.isEmpty, !row.name.isEmpty else { return nil }

        let cookieValue: String
        if !row.value.isEmpty {
            cookieValue = row.value
        } else if let decryptedValue = decryptCookieValue(row.encryptedValue, hostKey: row.host, with: decryptionKey), !decryptedValue.isEmpty {
            cookieValue = decryptedValue
        } else {
            return nil
        }

        let expiresDate = dateFromChromeTimestamp(row.expiresUTC)
        if let expiresDate, expiresDate <= now {
            return nil
        }

        return ChromeCookieDefinition(
            domain: row.host,
            path: row.path.isEmpty ? "/" : row.path,
            name: row.name,
            value: cookieValue,
            expiresDate: expiresDate,
            isSecure: row.isSecure,
            isHTTPOnly: row.isHTTPOnly,
            sameSite: row.sameSite
        )
    }

    private static func makeCookie(from definition: ChromeCookieDefinition) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: definition.domain,
            .path: definition.path,
            .name: definition.name,
            .value: definition.value,
        ]

        if definition.isSecure {
            properties[.secure] = "TRUE"
        }
        if definition.isHTTPOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        if let sameSite = sameSiteString(from: definition.sameSite) {
            properties[HTTPCookiePropertyKey("SameSite")] = sameSite
        }
        if let expiresDate = definition.expiresDate {
            properties[.expires] = expiresDate
        } else {
            properties[.discard] = "TRUE"
        }

        return HTTPCookie(properties: properties)
    }

    private static func sameSiteString(from raw: Int) -> String? {
        switch raw {
        case 0: return "None"
        case 1: return "Lax"
        case 2: return "Strict"
        default: return nil
        }
    }

    private static func discoverCookieDatabaseURLs(fileManager: FileManager = .default) -> [URL] {
        let chromeRoots = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome Beta", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome Canary", isDirectory: true),
        ]

        var found: [URL] = []

        for root in chromeRoots where fileManager.fileExists(atPath: root.path) {
            let profileURLs = discoverProfileDirectories(in: root, fileManager: fileManager)
            for profileURL in profileURLs {
                let primaryPath = profileURL.appendingPathComponent("Network/Cookies", isDirectory: false)
                let legacyPath = profileURL.appendingPathComponent("Cookies", isDirectory: false)
                if fileManager.fileExists(atPath: primaryPath.path) {
                    found.append(primaryPath)
                } else if fileManager.fileExists(atPath: legacyPath.path) {
                    found.append(legacyPath)
                }
            }
        }

        var uniqueByPath: [String: URL] = [:]
        for url in found {
            uniqueByPath[url.path] = url
        }

        let uniqueURLs = Array(uniqueByPath.values)
        return uniqueURLs.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    private static func discoverProfileDirectories(in root: URL, fileManager: FileManager) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var profiles: [URL] = []
        for url in contents {
            guard let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory == true else {
                continue
            }
            let name = url.lastPathComponent
            if name == "Default" || name.hasPrefix("Profile ") {
                profiles.append(url)
            }
        }
        return profiles
    }

    private static func readCookieRows(from sourceDatabaseURL: URL, fileManager: FileManager = .default) -> [ChromeCookieRow] {
        guard let stagedDatabaseURL = stageDatabase(sourceDatabaseURL, fileManager: fileManager) else {
            return []
        }
        defer {
            try? fileManager.removeItem(at: stagedDatabaseURL.deletingLastPathComponent())
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(stagedDatabaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database {
                sqlite3_close(database)
            }
            return []
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite
        FROM cookies
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return []
        }
        defer { sqlite3_finalize(statement) }

        var rows: [ChromeCookieRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let host = stringColumn(statement, index: 0)
            let name = stringColumn(statement, index: 1)
            let value = stringColumn(statement, index: 2)
            let encryptedValue = blobColumn(statement, index: 3)
            let path = stringColumn(statement, index: 4)
            let expiresUTC = sqlite3_column_int64(statement, 5)
            let isSecure = sqlite3_column_int(statement, 6) != 0
            let isHTTPOnly = sqlite3_column_int(statement, 7) != 0
            let sameSite = Int(sqlite3_column_int(statement, 8))

            rows.append(
                ChromeCookieRow(
                    host: host,
                    name: name,
                    value: value,
                    encryptedValue: encryptedValue,
                    path: path,
                    expiresUTC: expiresUTC,
                    isSecure: isSecure,
                    isHTTPOnly: isHTTPOnly,
                    sameSite: sameSite
                )
            )
        }

        return rows
    }

    private static func stageDatabase(_ sourceDatabaseURL: URL, fileManager: FileManager) -> URL? {
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "idx0-chrome-cookies-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            let stagedDatabaseURL = tempDirectory.appendingPathComponent(sourceDatabaseURL.lastPathComponent, isDirectory: false)
            try fileManager.copyItem(at: sourceDatabaseURL, to: stagedDatabaseURL)

            for suffix in ["-wal", "-shm"] {
                let sourceSidecarURL = URL(fileURLWithPath: sourceDatabaseURL.path + suffix)
                guard fileManager.fileExists(atPath: sourceSidecarURL.path) else { continue }
                let destinationSidecarURL = URL(fileURLWithPath: stagedDatabaseURL.path + suffix)
                try? fileManager.copyItem(at: sourceSidecarURL, to: destinationSidecarURL)
            }

            return stagedDatabaseURL
        } catch {
            try? fileManager.removeItem(at: tempDirectory)
            return nil
        }
    }

    private static func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let raw = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: raw)
    }

    private static func blobColumn(_ statement: OpaquePointer?, index: Int32) -> Data {
        let byteCount = Int(sqlite3_column_bytes(statement, index))
        guard byteCount > 0, let raw = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: raw, count: byteCount)
    }

    private static func chromeCookieDecryptionKey() -> Data? {
        guard let safeStorageSecret = readChromeSafeStorageSecret() else { return nil }
        return deriveChromeCookieKey(from: safeStorageSecret)
    }

    private static func readChromeSafeStorageSecret() -> Data? {
        let candidates: [(service: String, account: String?)] = [
            ("Chrome Safe Storage", "Chrome"),
            ("Chrome Safe Storage", nil),
            ("Chromium Safe Storage", "Chromium"),
            ("Chromium Safe Storage", nil),
        ]

        for candidate in candidates {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: candidate.service,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            if let account = candidate.account {
                query[kSecAttrAccount as String] = account
            }

            var result: CFTypeRef?
            let status: OSStatus
            if shouldUseMockKeychain {
                status = errSecItemNotFound
            } else {
                status = SecItemCopyMatching(query as CFDictionary, &result)
            }
            if status == errSecSuccess, let data = result as? Data, !data.isEmpty {
                return data
            }
        }
        return nil
    }

    private static func deriveChromeCookieKey(from safeStorageSecret: Data) -> Data? {
        var derived = [UInt8](repeating: 0, count: chromePBKDF2KeyLength)
        let status: Int32 = safeStorageSecret.withUnsafeBytes { secretBuffer in
            chromePBKDF2Salt.withUnsafeBytes { saltBuffer in
                let passwordPtr = secretBuffer.bindMemory(to: Int8.self).baseAddress
                let saltPtr = saltBuffer.bindMemory(to: UInt8.self).baseAddress
                return CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordPtr,
                    safeStorageSecret.count,
                    saltPtr,
                    chromePBKDF2Salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    chromePBKDF2Iterations,
                    &derived,
                    derived.count
                )
            }
        }

        guard status == kCCSuccess else { return nil }
        return Data(derived)
    }

    private static func decryptCookieValue(_ encryptedValue: Data, hostKey: String, with key: Data?) -> String? {
        guard !encryptedValue.isEmpty else { return nil }

        if encryptedValue.starts(with: chromeEncryptionPrefixV10) || encryptedValue.starts(with: chromeEncryptionPrefixV11) {
            guard let key else { return nil }
            let cipherText = Data(encryptedValue.dropFirst(3))
            guard let plainText = decryptChromeCipherText(cipherText, key: key) else { return nil }
            let normalized = stripHostDigestPrefixIfPresent(from: plainText, hostKey: hostKey)
            if let decoded = String(data: normalized, encoding: .utf8), !decoded.isEmpty {
                return decoded
            }

            // Fallback for Chromium variants that prepend a 32-byte digest but where
            // host normalization does not match exactly what we computed.
            if plainText.count > 32 {
                let fallback = Data(plainText.dropFirst(32))
                if let decoded = String(data: fallback, encoding: .utf8), !decoded.isEmpty {
                    return decoded
                }
            }

            return nil
        }

        return String(data: encryptedValue, encoding: .utf8)
    }

    private static func stripHostDigestPrefixIfPresent(from decryptedValue: Data, hostKey: String) -> Data {
        guard decryptedValue.count > 32 else { return decryptedValue }
        guard let hostData = hostKey.data(using: .utf8) else { return decryptedValue }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        hostData.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(hostData.count), &digest)
        }
        let expectedPrefix = Data(digest)

        if decryptedValue.prefix(expectedPrefix.count) == expectedPrefix {
            return Data(decryptedValue.dropFirst(expectedPrefix.count))
        }
        return decryptedValue
    }

    private static func decryptChromeCipherText(_ cipherText: Data, key: Data) -> Data? {
        guard !cipherText.isEmpty else { return nil }
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        let outputCapacity = cipherText.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var outputLength: size_t = 0

        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBuffer in
            cipherText.withUnsafeBytes { inputBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress,
                            key.count,
                            ivBuffer.baseAddress,
                            inputBuffer.baseAddress,
                            cipherText.count,
                            outputBuffer.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private static func dateFromChromeTimestamp(_ timestamp: Int64) -> Date? {
        guard timestamp > 0 else { return nil }
        let unixSeconds = Double(timestamp) / 1_000_000.0 - chromeEpochOffsetSeconds
        guard unixSeconds > 0 else { return nil }
        return Date(timeIntervalSince1970: unixSeconds)
    }
}
