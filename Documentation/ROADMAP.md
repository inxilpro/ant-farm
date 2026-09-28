# Roadmap

## Terminal

- **Run view follow-ups.** Show planned tasks as pending in the run report,
  per-item results for loops, and timing per task.
- **libghostty.** Swap SwiftTerm for libghostty-vt once its API settles and
  there is a way to ship it as an xcframework. Only
  `Terminal/TerminalController.swift` (and the `AntTerminalView` in it) knows
  about SwiftTerm, so the swap stays in that file.

## Workflow

- Several runs at once, in tabs.
- Drag hosts, tags, and the command out as text, and the run report as a
  file.
- Keyboard control of the host and tag lists that keeps click-to-toggle
  (list selection was tried and dropped: a click should toggle a row, not
  select it).
- Show which tasks each tag covers.
- Saved presets (named sets of hosts, tags, and extra arguments).
- Vault support: pick a vault password file or prompt through the Keychain.
- Watch the folder and reload when inventories or playbooks change.
