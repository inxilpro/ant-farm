//
//  TerminalController.swift
//  Ant Farm
//

import AppKit
import Observation
import SwiftTerm

/// Owns the terminal view and the ansible-playbook process running in it.
///
/// This is the only type that knows about SwiftTerm, so swapping in another
/// terminal engine (e.g. libghostty) means replacing this file and `AntTerminalView`.
@Observable
final class TerminalController {
    enum Status: Equatable {
        case idle
        case running
        case finished(exitCode: Int32?)
        case stopped
    }

    private(set) var status: Status = .idle
    private(set) var command: [String]?
    private(set) var mode: RunMode?
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?

    var isRunning: Bool { status == .running }

    @ObservationIgnored private(set) lazy var view: AntTerminalView = {
        let view = AntTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.processDelegate = self
        view.applyFontSize(UserDefaults.standard.double(forKey: SettingsKey.terminalFontSize))
        return view
    }()

    @ObservationIgnored private var stopRequested = false

    func run(argv: [String], executable: URL, environment: [String: String], directory: URL, mode: RunMode) {
        guard !isRunning else { return }

        let view = self.view
        view.resetForNewRun()
        let dim = "\u{1B}[2m", reset = "\u{1B}[0m"
        view.feed(text: "\(dim)\(directory.path)\(reset)\r\n$ \(ShellQuoting.format(argv))\r\n\r\n")

        command = argv
        self.mode = mode
        startedAt = Date()
        finishedAt = nil
        stopRequested = false
        status = .running

        view.startProcess(
            executable: executable.path,
            args: Array(argv.dropFirst()),
            environment: environment.map { "\($0.key)=\($0.value)" },
            execName: "ansible-playbook",
            currentDirectory: directory.path
        )
        view.window?.makeFirstResponder(view)
    }

    /// Interrupts the run by typing Ctrl-C into the terminal, so Ansible can clean up.
    func stop() {
        guard isRunning else { return }
        stopRequested = true
        view.send([0x03])
    }

    /// Kills the run's process group when it ignores Stop.
    func forceStop() {
        guard isRunning else { return }
        stopRequested = true
        let pid = view.process.shellPid
        if pid > 0 {
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
        }
    }

    func clear() {
        guard !isRunning else { return }
        view.resetForNewRun()
        status = .idle
        command = nil
        mode = nil
    }

    func setFontSize(_ size: Double) {
        view.applyFontSize(size)
    }

    fileprivate func processFinished(exitCode: Int32?) {
        finishedAt = Date()
        status = stopRequested ? .stopped : .finished(exitCode: exitCode)

        let text: String
        switch status {
        case .stopped:
            text = "\u{1B}[33m■ Stopped\u{1B}[0m"
        case .finished(let code) where code == 0:
            text = "\u{1B}[32m✔ Finished\u{1B}[0m"
        case .finished(let code):
            text = "\u{1B}[31m✘ Exited with status \(code.map(String.init) ?? "unknown")\u{1B}[0m"
        default:
            text = ""
        }
        view.feed(text: "\r\n\(text)\r\n")

        NotificationCenter.default.post(name: .antFarmRunFinished, object: self)
    }
}

extension Notification.Name {
    static let antFarmRunFinished = Notification.Name("AntFarmRunFinished")
}

extension TerminalController: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            processFinished(exitCode: exitCode)
        }
    }
}

/// SwiftTerm's view, adjusted to follow the system appearance.
final class AntTerminalView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        optionAsMetaKey = false
        applyColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            nativeForegroundColor = .textColor
            nativeBackgroundColor = .textBackgroundColor
            caretColor = .controlAccentColor
            selectedTextBackgroundColor = .selectedTextBackgroundColor
        }
    }

    func applyFontSize(_ size: Double) {
        let size = size > 0 ? size : 12
        font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Clears the screen and scrollback before a new run.
    func resetForNewRun() {
        // RIS: full reset, then clear scrollback.
        feed(text: "\u{1B}c\u{1B}[3J")
    }
}
