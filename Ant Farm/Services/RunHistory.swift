//
//  RunHistory.swift
//  Ant Farm
//

import Foundation

/// Past commands, stored in `.ansible-interactive-history` in the workspace so
/// Ant Farm and the ansible-interactive CLI share one history.
///
/// The file is a JSON array of argv arrays, newest first.
nonisolated enum RunHistory {
    static let fileName = ".ansible-interactive-history"
    static let maxEntries = 100

    static func url(in directory: URL) -> URL {
        directory.appending(path: fileName)
    }

    static func load(from directory: URL) -> [[String]] {
        guard let data = try? Data(contentsOf: url(in: directory)) else { return [] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [[String]] {
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return entries.compactMap(migrate)
    }

    /// Versions of the CLI before 1.0 stored arguments like `--tags='a,b'`; strip those quotes.
    static func migrate(_ entry: Any) -> [String]? {
        guard let args = entry as? [String], !args.isEmpty else { return nil }
        return args.map { arg in
            arg.replacing(/^(--[\w-]+)='(.*)'$/) { "\($0.1)=\($0.2)" }
        }
    }

    @discardableResult
    static func save(_ argv: [String], in directory: URL) throws -> [[String]] {
        let history = Array(([argv] + load(from: directory).filter { $0 != argv }).prefix(maxEntries))
        let data = try JSONSerialization.data(withJSONObject: history, options: [.prettyPrinted, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: url(in: directory), options: .atomic)
        return history
    }
}
