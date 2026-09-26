# Ant Farm

A native macOS app (SwiftUI) for running Ansible playbooks. It is a GUI
version of [ansible-interactive](https://github.com/glhd/ansible-interactive)
and follows that CLI's discovery rules and history file format.

## Layout

- `Ant Farm/Models`: `AppState` (open workspace, located tools, runs),
  `Workspace` (discovery results and selections for one folder),
  `AnsibleCommand` (argv building and parsing), `Selection` (include/exclude).
- `Ant Farm/Services`: `Discovery` (inventories, playbooks, tags),
  `AnsibleTools` and `LoginShell` (find Ansible through the login shell's
  PATH), `ProcessRunner`, `RunHistory`, `UpdaterController` (Sparkle).
- `Ant Farm/Terminal/TerminalController.swift`: the only code that touches
  SwiftTerm. Keep it that way so the engine can be swapped for libghostty.
- `Ant Farm/Views`: the three-pane `WorkspaceView` (a sidebar with the
  folder, playbook, inventory, and group tree; tags; terminal),
  `WelcomeView`, `SettingsView`. The toolbar holds only actions.

## Conventions

- The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Pure logic
  types are marked `nonisolated` so tests and background work can use them;
  work that blocks (processes, file scans) is `@concurrent`.
- The app is **not sandboxed**: it spawns `ansible-playbook` and reads any
  folder. Hardened runtime stays on.
- Unit tests use Swift Testing (`Ant FarmTests`). CI runs them on every push
  to `main`; the build can't run on Linux.
- Releases: push a `vX.Y.Z` tag; see `Documentation/RELEASING.md`.
- Future work: `Documentation/ROADMAP.md`.
