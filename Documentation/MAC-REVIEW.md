# Mac review

A review of Ant Farm against the `mac-assed-mac-app` skill
(`.claude/skills/mac-assed-mac-app`), done on 2026-09-26. The review read the
code only; nobody ran the app on macOS for it. The manual checks at the end
still need a pass on a Mac.

## What kind of app this is

A folder-based workspace with a runner. The "document" is a folder of Ansible
content. The core objects are hosts, groups, tags, playbooks, the command, and
a run's report. The app has one window with one folder at a time.

## Scores

Scored 0–3 per the skill's rubric.

| Area | Before | After | Notes |
| --- | --- | --- | --- |
| Native behaviour | 2 | 2 | Native split view, lists, pickers, forms, and alerts. The filter fields are plain `TextField`s, so text editing works. |
| Menus/commands | 2 | 3 | Mode items now show a checkmark. Added Copy Command, Show in Finder, Show Terminal, font size, sidebar, and real Help items. |
| Keyboard/focus | 1 | 1 | Good shortcuts, but you can't reach list rows from the keyboard. Esc now clears a filter. |
| Text handling | 2 | 2 | Native fields; command, output, and diffs are selectable. |
| Selection | 1 | 1 | Click toggles one row. No multiple selection. |
| Drag/drop | 1 | 2 | Folders now drop on the workspace window and the Dock icon, not only the welcome screen. Nothing drags out. |
| Copy/paste | 1 | 1 | Copy Command is now in the Edit menu (⇧⌘C). Rows can't be copied. |
| Windows/documents | 1 | 1 | One window, one folder. Settings and the confirmation sheet are right. |
| State/config | 2 | 2 | Selections, recents, and settings persist. Sidebar visibility and the report's filter now persist too. |
| Interoperability | 1 | 2 | Ant Farm now registers for folders, so Open With, drops on the Dock icon, `open -a`, and the Dock's recent items work. |
| Accessibility | 2 | 2 | Rows have values and actions. Collapsed tag stacks now read out every tag, and animations respect Reduce Motion. |
| Craft/detail | 2 | 2 | Plan preview, live report, Dock bounce, and the Ctrl-C escape hatch are good touches. |
| **Total** | **18** | **21** | "Runs on Mac, but feels generic or incomplete" (13–24). |

## Fixed in this pass

1. **Open folders from the system.** `Info.plist` declares `public.folder` as a
   viewer type (rank Alternate, so Ant Farm never becomes the default).
   `AppDelegate.application(_:open:)` hands the folder to `AppState`, which
   waits until Ansible is located if the app is still starting. Before this,
   the Dock's recent items, which `noteNewRecentDocumentURL` fills, did
   nothing when clicked.
2. **Main window comes back.** Opening a folder while the window is closed now
   reopens it.
3. **Drop a folder on the workspace** to switch to it (ignored during a run).
4. **Menus.**
   - Run > Check Mode / Live Mode are toggles with a checkmark.
   - Edit > Copy Command (⇧⌘C).
   - File > Show in Finder.
   - View > Show Sidebar, Show Terminal (⌃⌘T), and Bigger / Smaller /
     Default Font Size (⌘+ / ⌘- / ⌘0) for the terminal.
   - Help opens the README, release notes, and a new issue, in place of
     "Help isn't available".
   - Clear Menu also clears the Dock's recent items.
5. **Undo.** Include, exclude, and Clear in the host and tag lists are
   undoable and redoable, with names such as "Undo Exclude" and "Undo Clear
   Hosts".
6. **Recent folders** on the welcome screen have a context menu: Open, Show in
   Finder, Remove from Recents.
7. **State.** Sidebar visibility (`@SceneStorage`) and "Only changes and
   failures" (`@AppStorage`) survive relaunch.
8. **Accessibility.** Collapsed tag stacks expose every tag to VoiceOver and
   in a tooltip; the fan-out and auto-scroll skip animation under Reduce
   Motion.

## Still to do

Largest gains first. The first two are already in `ROADMAP.md`.

1. **One window per folder.** Use `WindowGroup(for: URL.self)` and move the
   workspace, terminal, and monitor into per-window state. Menu commands then
   route through `@FocusedValue`. This is the biggest gap: Mac users expect to
   open two projects side by side, and the Window menu to list them.
2. **Keyboard and multiple selection in the lists.** Use `List(selection:)`,
   Space to toggle, Delete to clear, and `contextMenu(forSelectionType:)` so
   one right-click acts on every selected row. ⌘C on rows could copy the
   names, one per line.
3. **Run-finished notification** through `UserNotifications` when the app is
   in the background, with the result in the title.
4. **⌘F for the host filter.** SwiftUI's Edit > Find item already uses ⌘F.
5. **Customizable toolbar** with `.toolbar(id:)`.
6. **Drag out.** Hosts and the command could drag out as text, and the
   report as a text file.

## Manual checks on a Mac

- [ ] Build and run the unit tests.
- [ ] Right-click a folder in Finder > Open With > Ant Farm: it opens, with
      the app running and not running.
- [ ] Drop a folder on the Dock icon and on the workspace window.
- [ ] Close the window, then use ⌘O and the Dock's recent items: the window
      comes back.
- [ ] Run menu: the checkmark follows the mode, and ⌘1 / ⌘2 still switch it.
- [ ] ⇧⌘C copies the command; paste it into Terminal and it runs.
- [ ] ⌃⌘T switches between summary and terminal during and after a run.
- [ ] ⌘+ / ⌘- / ⌘0 change the terminal font, and Settings shows the new size.
- [ ] Include a host, then ⌘Z and ⇧⌘Z. Clear hosts, then ⌘Z.
- [ ] Hide the sidebar, quit, relaunch: it stays hidden.
- [ ] Esc in a filter field clears it.
- [ ] VoiceOver reads all tags on a collapsed tag stack.
- [ ] Help menu items open the right pages.
