//
//  RunMonitor.swift
//  Ant Farm
//

import Foundation
import Observation

/// Follows a run through the bundled `antfarm` callback plugin and keeps a `RunReport` of it.
///
/// Before each run, `start` copies the plugin into a temporary folder and returns the
/// environment that makes Ansible load it. The plugin appends JSON lines to an events
/// file there, which the monitor reads while the run goes on. Ansible's normal output
/// still goes to the terminal, so nothing is lost if the plugin can't load.
@Observable
final class RunMonitor {
    private(set) var report = RunReport()
    /// False when the plugin couldn't be set up, so there will be no report for this run.
    private(set) var isAvailable = false

    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var handle: FileHandle?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var poll: Task<Void, Never>?

    /// Prepares to follow a run. Returns the environment variables to add to it.
    ///
    /// `callbackPluginPaths` are the callback folders Ansible would otherwise use;
    /// they stay on the path so the user's own callbacks keep working.
    func start(argv: [String], callbackPluginPaths: [String]) -> [String: String] {
        stop()
        report = RunReport()
        report.isWaitingForInput = argv.contains { AnsibleCommand.promptFlags.contains($0) }
        isAvailable = false

        guard let plugin = Bundle.main.url(forResource: "antfarm", withExtension: "py") else { return [:] }

        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appending(path: "AntFarm-\(UUID().uuidString)")
        let callbacks = folder.appending(path: "callback_plugins")
        let events = folder.appending(path: "events.jsonl")
        do {
            try fm.createDirectory(at: callbacks, withIntermediateDirectories: true)
            try fm.copyItem(at: plugin, to: callbacks.appending(path: "antfarm.py"))
            try Data().write(to: events)
            handle = try FileHandle(forReadingFrom: events)
        } catch {
            try? fm.removeItem(at: folder)
            return [:]
        }

        self.folder = folder
        buffer = Data()
        isAvailable = true
        poll = Task { [weak self] in
            while !Task.isCancelled {
                self?.read()
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        return [
            "ANTFARM_EVENTS": events.path,
            "ANSIBLE_CALLBACK_PLUGINS": ([callbacks.path] + callbackPluginPaths).joined(separator: ":"),
        ]
    }

    /// Reads the last events after the process exits and cleans up.
    func finish() {
        read()
        stop()
        report.finish()
    }

    /// Forgets the last run.
    func clear() {
        stop()
        report = RunReport()
        isAvailable = false
    }

    private func stop() {
        poll?.cancel()
        poll = nil
        try? handle?.close()
        handle = nil
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
        folder = nil
        buffer = Data()
    }

    /// Applies every complete line written since the last read.
    private func read() {
        guard let handle, let data = try? handle.readToEnd(), !data.isEmpty else { return }
        buffer.append(data)

        var updated = report
        var changed = false
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let event = RunEvent.parse(String(decoding: line, as: UTF8.self)) {
                updated.apply(event)
                changed = true
            }
        }
        if changed {
            report = updated
        }
    }
}
