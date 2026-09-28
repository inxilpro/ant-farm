# Ant Farm

**[⬇ Download the latest release](https://github.com/inxilpro/ant-farm/releases/latest)**
(macOS 27 or later)

Ant Farm is a Mac app for running Ansible playbooks. It does what
[ansible-interactive](https://github.com/glhd/ansible-interactive) does in the
terminal: pick hosts, pick tags, choose check or live mode, and run.

## How it works

1. Open a folder with your Ansible inventory and playbooks: use File > Open
   Folder, drop the folder on the window or the Dock icon, or use Open With in
   Finder. Each folder gets its own window (or tab), and Ant Farm reopens
   them on launch. Opening a folder that's already open brings its window
   forward.
2. **Inventory pane:** pick the groups and hosts to run on. Click to include,
   Option-click (or right-click) to exclude. Checking a group covers the
   groups and hosts inside it: they show as checked and can't be changed
   until you uncheck the group. A host in an excluded group shows as
   excluded, even if another of its groups is included. With nothing picked, the run targets every host.
   Edit > Undo reverses a change.
3. **Tags pane:** pick tags to run or skip, the same way. With nothing picked,
   every task runs. The pane opens wide enough for most of the playbook's
   tags.
   Put extra `ansible-playbook` arguments (`-e env=staging`,
   `--ask-become-pass`) in the field below the tags.
4. **Toolbar:** choose the playbook and Check or Live mode, then Run (⌘R).
   View > Customize Toolbar adds Copy Command, Show in Finder, and Open in
   Terminal.
5. **Run pane:** before a run, shows what it will do: each play, the hosts
   it targets, and the tasks it will run with your tags (from
   `ansible-playbook --list-hosts --list-tasks`). During and after a run, it
   shows each task's result per host, with diffs and errors, and the recap.
   Stop (⌘.) interrupts the run and lets Ansible clean up. Ctrl-C or ⌥⌘. kills
   it at once.
6. **Terminal:** the switch in the pane's header shows Ansible's own output
   in a real terminal. It opens by itself when Ansible asks for input, such as
   a password or a `vars_prompt`.

Live runs ask for confirmation first. You can turn that off in Settings. A
window can't close while its run is going, and quitting during a run asks
first. When a run finishes while you're in another app, Ant Farm posts a
notification; click it to go back to that window.

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

## How the run view works

Ant Farm adds a small callback plugin (`Ant Farm/Callback/antfarm.py`) to each
run through `ANSIBLE_CALLBACK_PLUGINS`, after copying it to a temporary
folder. The plugin writes each event as a line of JSON to a file Ant Farm
reads; Ansible's normal output still goes to the terminal. Callback folders
from your `ansible.cfg` stay on the path, and `callbacks_enabled` is left
alone. If the plugin doesn't load, Ant Farm shows the terminal instead.

## History

Runs are saved to `.ansible-interactive-history` in the workspace, the same
file the CLI uses, so the two share history. The clock button in the toolbar
re-runs a past command in check or live mode or restores its selections.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New window | ⌘N |
| Open folder | ⌘O |
| Copy command | ⇧⌘C |
| Run | ⌘R |
| Run in check mode | ⌥⌘R |
| Stop / force stop | ⌘. / ⌃C or ⌥⌘. |
| Check mode / live mode | ⌘1 / ⌘2 |
| Clear run | ⌘K |
| Reload | ⇧⌘R |
| Show terminal | ⌃⌘T |
| Terminal font bigger / smaller / default | ⌘+ / ⌘- / ⌘0 |
| Filter hosts / filter tags | ⌥⌘F / ⇧⌥⌘F |
| Clear a filter field | Esc |

## Development

Open `Ant Farm.xcodeproj` in Xcode 27. The app icon is `Ant Farm/AntFarmIcon.icon`; edit it
in Icon Composer. The first build asks you to trust
SwiftTerm's build plugin. CI (`.github/workflows/ci.yml`) builds and runs the
unit tests on every push to `main`. `Documentation/RELEASING.md` covers
releases, and `Documentation/ROADMAP.md` lists planned work.
