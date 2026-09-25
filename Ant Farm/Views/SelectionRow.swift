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
    let onChange: (SelectionState) -> Void

    var body: some View {
        HStack(spacing: 8) {
            StateIcon(state: state)
            Label {
                Text(title)
                    .strikethrough(state == .excluded, color: .secondary)
                    .foregroundStyle(state == .excluded ? .secondary : .primary)
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
        .contentShape(Rectangle())
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option) {
                onChange(state == .excluded ? .none : .excluded)
            } else {
                onChange(state.toggled)
            }
        }
        .help(help ?? "Click to include, Option-click to exclude")
        .contextMenu {
            Button("Include", systemImage: "checkmark.circle") { onChange(.included) }
                .disabled(state == .included)
            Button("Exclude", systemImage: "minus.circle") { onChange(.excluded) }
                .disabled(state == .excluded)
            Divider()
            Button("Clear", systemImage: "circle") { onChange(.none) }
                .disabled(state == .none)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(state.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onChange(state.toggled) }
        .accessibilityAction(named: "Exclude") { onChange(.excluded) }
    }
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
    var accessibilityLabel: String {
        switch self {
        case .none: "Not selected"
        case .included: "Included"
        case .excluded: "Excluded"
        }
    }
}

/// A compact filter field for the top of a pane.
struct FilterField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
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
            excluded.foregroundColor = .red
            result += excluded
        }
        return result
    }
}
