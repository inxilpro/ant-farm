# Ant Farm

**[⬇ Download the latest release](https://github.com/inxilpro/ant-farm/releases/latest)**
(macOS 27 or later)

Ant Farm is a Mac app for running Ansible playbooks. It does what
[ansible-interactive](https://github.com/glhd/ansible-interactive) does in the
terminal: pick hosts, pick tags, choose check or live mode, and run.

## How it works

1. Open a folder with your Ansible inventory and playbooks. Ant Farm reopens
   the last folder on launch.
2. **Inventory pane:** pick the groups and hosts to run on. Click to include,
   Option-click (or right-click) to exclude. With nothing picked, the run
   targets every host.
3. **Tags pane:** pick tags to run or skip. With nothing picked, every task runs.
   Put extra `ansible-playbook` arguments (`-e env=staging`,
   `--ask-become-pass`) in the field below the tags.
4. **Toolbar:** choose the playbook and Check or Live mode, then Run (⌘R).
5. **Terminal pane:** shows the command and the run. It is a real terminal, so
   password prompts work. Stop (⌘.) interrupts the run and lets Ansible
   clean up. Ctrl-C or ⌥⌘. kills it at once.

Live runs ask for confirmation first. You can turn that off in Settings.

## Discovery

Ant Farm follows the same rules as ansible-interactive:

- **Inventories:** Ansible's configured default (from `ansible.cfg` or
  `ANSIBLE_INVENTORY`), an `inventory/` folder, each entry in `inventories/`,
  and INI or YAML inventory files in the folder root.
- **Playbooks:** YAML files in the folder root and `playbooks/` whose top level
  is a list of plays.
- **Tags:** from `ansible-playbook --list-tags`.
- **Groups and hosts:** from `ansible-inventory --list`.

Ant Farm finds Ansible through your login shell's `PATH`, then Homebrew and
`~/.local/bin`. You can set the folder in Settings.

## History

Runs are saved to `.ansible-interactive-history` in the workspace, the same
file the CLI uses, so the two share history. The clock button in the toolbar
re-runs a past command in check or live mode or restores its selections.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open folder | ⌘O |
| Run | ⌘R |
| Run in check mode | ⌥⌘R |
| Stop / force stop | ⌘. / ⌃C or ⌥⌘. |
| Check mode / live mode | ⌘1 / ⌘2 |
| Clear terminal | ⌘K |
| Reload | ⇧⌘R |

## Development

Open `Ant Farm.xcodeproj` in Xcode 27. The app icon is `Ant Farm/AntFarmIcon.icon`; edit it
in Icon Composer. The first build asks you to trust
SwiftTerm's build plugin. CI (`.github/workflows/ci.yml`) builds and runs the
unit tests on every push to `main`. `Documentation/RELEASING.md` covers
releases, and `Documentation/ROADMAP.md` lists planned work.
