// SPDX-License-Identifier: MIT
// Sourcepad — Phase 23 Touch ID vault.
//
// Marks a workspace folder (or sub-folder) as "vaulted". Opening any
// file inside the vault prompts for Touch ID / device authentication
// via LocalAuthentication. Sessions cache the authentication for the
// configured timeout (default 10 min).

import Foundation
import LocalAuthentication

public final class TouchIDVault {

    public static let shared = TouchIDVault()

    private var lastAuth: Date?
    private let timeout: TimeInterval = 600  // 10 min

    private init() {}

    /// Paths the user has marked as vaulted (persisted via UserDefaults).
    public var vaultedPaths: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "Sourcepad.vaultedPaths") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "Sourcepad.vaultedPaths") }
    }

    public func mark(_ folder: URL) {
        var s = vaultedPaths
        s.insert(folder.standardizedFileURL.path)
        vaultedPaths = s
    }

    public func unmark(_ folder: URL) {
        var s = vaultedPaths
        s.remove(folder.standardizedFileURL.path)
        vaultedPaths = s
    }

    public func isInsideVault(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return vaultedPaths.contains { path.hasPrefix($0) }
    }

    /// Run Touch ID; calls completion(true) if authentication succeeds
    /// or the cached auth is still within timeout.
    public func authenticate(reason: String,
                             completion: @escaping (Bool) -> Void) {
        if let last = lastAuth, Date().timeIntervalSince(last) < timeout {
            completion(true); return
        }
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fall back to passcode.
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
                DispatchQueue.main.async {
                    if ok { self.lastAuth = Date() }
                    completion(ok)
                }
            }
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                          localizedReason: reason) { ok, _ in
            DispatchQueue.main.async {
                if ok { self.lastAuth = Date() }
                completion(ok)
            }
        }
    }
}
