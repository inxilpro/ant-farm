//
//  ProcessRunner.swift
//  Ant Farm
//

import Foundation

nonisolated struct ProcessResult: Sendable {
    var status: Int32
    var stdout: Data
    var stderr: Data

    var output: String { String(decoding: stdout, as: UTF8.self) }
    var errorOutput: String { String(decoding: stderr, as: UTF8.self) }
}

/// Runs short-lived helper commands (ansible-inventory, --list-tags, …) and collects their output.
nonisolated enum ProcessRunner {
    @concurrent
    static func run(
        _ executable: URL,
        arguments: [String],
        in directory: URL? = nil,
        environment: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        if let environment {
            process.environment = environment
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if process.isRunning { process.terminate() }
                    }
                }

                // Drain stderr on another thread so a full pipe can't stall the child.
                let errorBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errorBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                continuation.resume(returning: ProcessResult(
                    status: process.terminationStatus,
                    stdout: out,
                    stderr: errorBox.data
                ))
            }
        }
    }
}

private nonisolated final class DataBox: @unchecked Sendable {
    var data = Data()
}
