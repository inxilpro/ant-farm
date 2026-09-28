//
//  SelectionRow.swift
//  Ant Farm
//

import AppKit
import SwiftUI

/// A list row that can be included, excluded, or left alone.
///
/// Click toggles inclusion. Option-click (or the context menu) excludes.
struct SelectionRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String
    var help: String?
    let state: SelectionState
    /// Set when a group's state covers this row; the row shows it and can't change.
    var inheritedState: SelectionState?
    let onChange: (SelectionState) -> Void

    private var shownState: SelectionState { inheritedState ?? state }

    var body: some View {
        HStack(spacing: 8) {
            StateIcon(state: shownState)
            Label {
                Text(title)
                    .strikethrough(shownState == .excluded, color: .secondary)
                    .foregroundStyle(shownState == .excluded ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(inheritedState == nil ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture {
            guard inheritedState == nil else { return }
            if NSEvent.modifierFlags.contains(.option) {
                onChange(state == .excluded ? .none : .excluded)
            } else {
                onChange(state.toggled)
            }
        }
        .help(inheritedState.map { $0 == .excluded ? "Excluded with a group it's in" : "Included with a group it's in" }
              ?? help ?? "Click to include, Option-click to exclude")
        .contextMenu {
            Button("Include", systemImage: "checkmark.circle") { onChange(.included) }
                .disabled(inheritedState != nil || state == .included)
            Button("Exclude", systemImage: "minus.circle") { onChange(.excluded) }
                .disabled(inheritedState != nil || state == .excluded)
            Divider()
            Button("Clear", systemImage: "circle") { onChange(.none) }
                .disabled(inheritedState != nil || state == .none)
            Divider()
            Button("Copy Name", systemImage: "doc.on.doc") { copyLines([title]) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(inheritedState == nil ? state.accessibilityLabel : shownState.accessibilityLabel + " with a group it's in")
        .accessibilityAddTraits(inheritedState == nil ? .isButton : [])
        .accessibilityAction { if inheritedState == nil { onChange(state.toggled) } }
        .accessibilityAction(named: "Exclude") { if inheritedState == nil { onChange(.excluded) } }
    }
}

/// Puts names on the pasteboard, one per line.
func copyLines(_ lines: [String]) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
}

struct StateIcon: View {
    let state: SelectionState

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .contentTransition(.symbolEffect(.replace))
            .imageScale(.medium)
            .frame(width: 16)
    }

    private var symbol: String {
        switch state {
        case .none: "circle"
        case .included: "checkmark.circle.fill"
        case .excluded: "minus.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .none: .secondary
        case .included: .green
        case .excluded: .red
        }
    }
}

extension SelectionState {
    /// The name Edit > Undo shows for a change to this state.
    var actionName: String {
        switch self {
        case .none: "Deselect"
        case .included: "Include"
        case .excluded: "Exclude"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .none: "Not selected"
        case .included: "Included"
        case .excluded: "Excluded"
        }
    }
}

/// A compact filter field for the top of a pane. Edit > Filter Hosts / Filter Tags focuses it.
struct FilterField: View {
    @Environment(WindowSession.self) private var session
    let prompt: String
    let target: FilterTarget
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand { text = "" }
                .onChange(of: session.focusRequest, initial: true) { _, request in
                    guard request == target else { return }
                    isFocused = true
                    session.focusRequest = nil
                }
            if !text.isEmpty {
                Button("Clear Filter", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 7))
    }
}

/// The summary and Clear button at the bottom of a pane.
struct SelectionSummary: View {
    let emptyText: String
    let selection: Selection
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)
            Spacer()
            if !selection.isEmpty {
                Button("Clear", action: onClear)
                    .controlSize(.small)
            }
        }
    }

    private var summary: AttributedString {
        guard !selection.isEmpty else { return AttributedString(emptyText) }
        var result = AttributedString()
        if !selection.included.isEmpty {
            result += AttributedString(selection.included.joined(separator: ", "))
        }
        if !selection.excluded.isEmpty {
            if !result.characters.isEmpty { result += AttributedString("  ") }
            var excluded = AttributedString("not " + selection.excluded.joined(separator: ", "))
            excluded.foregroundColor = Color.red
            result += excluded
        }
        return result
    }
}
