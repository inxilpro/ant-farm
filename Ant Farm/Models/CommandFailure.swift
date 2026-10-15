//
//  CommandFailure.swift
//  Ant Farm
//

import Foundation

/// Failures with a known cause, recognized from a helper command's error output,
/// so Ant Farm can say what to do instead of showing Ansible's raw output.
nonisolated enum CommandFailure: Equatable, Sendable {
    /// The vault password script runs the 1Password CLI, which can't reach the
    /// 1Password app. macOS treats Ant Farm as responsible for `op`'s access to
    /// 1Password's shared data, so `op` fails until Ant Farm is allowed that
    /// access, though the same command works in a terminal that already has it.
    case onePasswordAccess

    static func recognize(_ message: String) -> CommandFailure? {
        guard message.contains("Vault password script") else { return nil }
        let onePasswordSigns = ["1Password CLI", "op signin", "op://"]
        if onePasswordSigns.contains(where: message.contains) {
            return .onePasswordAccess
        }
        return nil
    }
}
