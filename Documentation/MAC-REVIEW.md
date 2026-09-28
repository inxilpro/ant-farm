# Mac review

Reviews of Ant Farm against the `mac-assed-mac-app` skill
(`.claude/skills/mac-assed-mac-app`). The latest pass is first.

## What kind of app this is

A folder-based workspace with a runner. The "document" is a folder of Ansible
content, and each folder gets its own window. The core objects are hosts,
groups, tags, playbooks, the command, and a run's report.

## Scores

Scored 0–3 per the skill's rubric.

| Area | First pass | Second pass | Notes |
| --- | --- | --- | --- |
| Native behaviour | 2 | 2 | Native split view, lists, pickers, forms, alerts, and tabs. |
| Menus/commands | 3 | 3 | Menu items act on the key window. Added New Window, Filter Hosts / Filter Tags, and Customize Toolbar. |
| Keyboard/focus | 1 | 1 | ⌥⌘F / ⇧⌥⌘F focus the filters, but rows still can't be reached from the keyboard. |
| Text handling | 2 | 2 | Native fields; command, output, and diffs are selectable. |
| Selection | 1 | 1 | A click toggles one row, by design: rows are checkboxes, not items to select. |
| Drag/drop | 2 | 2 | Folders drop on any window and the Dock icon. Nothing drags out yet. |
| Copy/paste | 1 | 2 | Copy Name in each row's context menu; Copy Command (⇧⌘C). |
| Windows/documents | 1 | 3 | One window per folder, tabs, the Window menu, restoration on relaunch. Opening a folder that's already open brings its window forward. |
| State/config | 2 | 3 | Each window's folder is restored. The toolbar is customizable and remembered. |
| Interoperability | 2 | 2 | Open With, Dock drops, recent items, Open in Terminal, and notifications. No Services or Shortcuts. |
| Accessibility | 2 | 2 | Rows have values and named Include/Exclude actions. |
| Craft/detail | 2 | 2 | Missing folders explain themselves; runs can't be lost by closing a window or quitting. |
| **Total** | **21** | **25** | "Solid Mac app with fixable gaps" (25–31). |

## Second pass (2026-09-26)

The app was built and run on macOS 27 for this pass, and the unit tests
pass. Folder opening, window reuse, and restoration were checked in the
running app. Clicks, menus, and sheets weren't driven, because the session
had no accessibility or screen recording access. They're in the manual
checks below.

### Fixed

1. **One window per folder.** `WindowGroup(for: URL.self)` replaces the single
   window. Each window owns a `WindowSession` (workspace, terminal, monitor,
   pending live run). `AppState` keeps what's shared: Ansible, recent folders,
   and the list of windows. Menu commands reach the key window through
   `@FocusedValue`. Opening a folder brings its window forward if it's
   already open, fills an empty window if there is one, or else opens a new
   window. With "Prefer tabs: Always", folders open as tabs. File > New
   Window (⌘N) opens a welcome window. Close Folder is gone; ⌘W closes the
   window.
2. **Restoration.** SwiftUI restores each window's folder on relaunch. If the
   system restores nothing, the first window reopens the last folder, as
   before. A restored folder that's gone falls back to the welcome screen with
   a sheet that says so, and leaves Recents.
3. **Runs can't be lost.** A window can't close while its run is going
   (`windowDismissBehavior`), and quitting during a run asks first. This
   replaces `onDisappear`: SwiftUI sends that when a window becomes a
   background tab, and using it would have stopped runs when switching tabs.
4. **Ctrl-C stops only that window's run.** The key monitor was app-wide, so
   with more than one window, Ctrl-C in one would have killed runs in all of
   them.
5. **Finder and Dock opens.** SwiftUI added an empty window for every folder
   sent from Finder, even with `handlesExternalEvents(matching: [])` on the
   scene. Now an open window claims the event
   (`handlesExternalEvents(preferring:allowing:)` and `onOpenURL`), and
   `AppState` picks the window. At launch, a folder from Finder no longer
   replaces a window that's still restoring its own folder. Folder URLs with
   and without a trailing slash now count as the same folder.
6. **Lists.** Each row's context menu gains Copy Name. (This pass first made
   the lists selectable, with Space, Delete, and ⌘C acting on the selection.
   That was dropped after review: the only reason to click a row is to
   toggle it, so a click toggles.)
7. **Filters.** Edit > Filter Hosts (⌥⌘F) and Filter Tags (⇧⌥⌘F) focus the
   filter fields and show their column if it's hidden. Mail uses ⌥⌘F for
   search, and ⌘F stays with Find.
8. **Customizable toolbar** (`.toolbar(id:)` and View > Customize Toolbar).
   Copy Command, Show in Finder, and Open in Terminal are available, off by
   default.
9. **Run-finished notification** when the app is in the background: title
   "Check run finished" / "Live run failed", the folder, and the recap line.
   Clicking it brings the window forward. The Dock icon still bounces once.
   Permission is asked on the first background run.
10. **Sheets, not app-modal panels.** Open Folder and Settings > Ansible
    folder > Choose use sheets on their window.
11. **Open in Terminal** in the folder menu and the toolbar.
12. **Bug:** the playbook picker's tooltip showed `Playbook: Optional("…")`.
13. **Layout.** The toolbar's actions sit at the trailing edge, over the run
    pane, instead of starting over the tags column. The tags column opens
    wide enough for nine in ten of the playbook's tags (up to 360 pt), and
    the playbook and inventory pickers fill the sidebar's width.
14. **Nested groups.** Including or excluding a group shows its subgroups
    and hosts with the same state, dimmed and disabled, and clears their own
    states, so unchecking the group leaves them unchecked and clickable. A
    host in an excluded group shows as excluded, as Ansible's `--limit`
    treats it.

### Still to do

Largest gains first.

1. **Drag out.** Hosts, tags, and the command could drag out as text, and the
   report as a text file.
2. **Keyboard control of the lists** that keeps click-to-toggle.
3. **Several runs at once** in one window, in tabs of the run pane.
4. **Services and Shortcuts:** "Open in Ant Farm" for a folder, and a Run
   intent.
5. **Session state per window:** the report's expanded tasks and the list
   selections aren't saved with the window.

### Manual checks on a Mac

- [ ] Open two folders: two windows (or tabs), each listed in the Window
      menu under its folder's name.
- [ ] Open a folder that's already open, from File > Open Recent, Finder's
      Open With, and the Dock: its window comes forward and no new one opens.
- [ ] Quit with two folders open and relaunch: both come back.
- [ ] Run in one window, switch to another tab: the run keeps going.
- [ ] Close button and ⌘W are disabled during a run.
- [ ] Quit during a run: the alert appears; Cancel keeps running.
- [ ] Ctrl-C in one window doesn't stop a run in another.
- [ ] Menu items (Run, Stop, Copy Command, Check/Live Mode) act on the key
      window only.
- [ ] Clicking a row toggles it; Option-click excludes; ⌘Z undoes.
- [ ] Right-click a row > Copy Name.
- [ ] Check a parent group: its subgroups and its hosts in the Hosts
      section show checked and dimmed, and clicking them does nothing.
      Uncheck it: they're unchecked and clickable. ⌘Z restores their own
      states.
- [ ] The toolbar's actions sit at the right, over the run pane, with the
      sidebar shown and hidden.
- [ ] A playbook with many tags opens with the tags column wide enough for
      most of them; dragging it narrower sticks.
- [ ] The playbook and inventory pickers span the sidebar.
- [ ] ⌥⌘F focuses the host filter, even with the sidebar hidden.
- [ ] View > Customize Toolbar: add Open in Terminal; relaunch; it stays.
- [ ] Run in check mode, switch apps: a notification appears when it
      finishes, and clicking it brings the window forward.
- [ ] Rename an open folder in Finder, then quit and relaunch: the sheet says
      it can't be found.
- [ ] VoiceOver on a host row reads its state and offers Include/Exclude.

## First pass (2026-09-26)

Code-only review; nobody ran the app for it.

### Fixed

1. **Open folders from the system.** `Info.plist` declares `public.folder` as a
   viewer type (rank Alternate, so Ant Farm never becomes the default).
2. **Main window comes back** when a folder opens with the window closed.
3. **Drop a folder on the workspace** to open it.
4. **Menus.** Check / Live Mode toggles, Copy Command (⇧⌘C), Show in Finder,
   Show Terminal (⌃⌘T), terminal font size (⌘+ / ⌘- / ⌘0), and real Help
   items. Clear Menu also clears the Dock's recent items.
5. **Undo** for include, exclude, and Clear in the host and tag lists.
6. **Recent folders** on the welcome screen have a context menu.
7. **State.** Sidebar visibility and "Only changes and failures" persist.
8. **Accessibility.** Collapsed tag stacks expose every tag; animations
   respect Reduce Motion.
