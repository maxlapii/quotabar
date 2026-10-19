# ClaudeStatus — Setup Guide

A macOS menu bar extra that shows your Claude Code usage limits:

```
[Claude icon] 5h 0% ▯▯▯▯▯  W 64% ▮▮▮▯▯  F 80% ▮▮▮▮▯
```

| Label | Source field                     | Meaning                                   |
|-------|----------------------------------|-------------------------------------------|
| 5h    | `five_hour.utilization`          | Current 5-hour session window             |
| W     | `seven_day.utilization`          | Weekly limit, all models                  |
| F     | `limits[kind=weekly_scoped].percent` where `scope.model.display_name` is Fable | Weekly Fable limit (falls back to `seven_day_*` keys, then `seven_day`) |

Data comes from `GET https://api.anthropic.com/api/oauth/usage` using the OAuth
token Claude Code saved when you ran `/login`. The endpoint is unofficial and
may change without notice.

## Quick start (no Xcode needed)

Only the Command Line Tools are required (`xcode-select --install`).

```bash
./build.sh run
```

That compiles the three Swift files into `build/ClaudeStatus.app`, signs it
ad-hoc, and launches it. Look at the top-right of the menu bar.

**First run:** the label shows dashes and the dropdown says *Not signed in to
Claude Code*. Claude Desktop keeps its own login private to its Code tab, so
the `claude` command-line tool must be signed in once:

1. Click **Sign in via Terminal** in the dropdown (or run `claude` yourself).
2. Type `/login`, press Return, finish in the browser.
3. Back in the menu bar, click **Refresh (3min)**. (In the unlikely event macOS
   asks to allow Keychain access, click **Always Allow**.)

**Keep it running on its own.** An app launched from inside a Claude Desktop
session (for example by Claude running `./build.sh run` for you) belongs to that
session and quits when Claude Desktop quits. To make it independent:

1. Run this in your own Terminal (not from Claude) to install it:

   ```bash
   ./build.sh install
   ```

2. Open the dropdown and tick **Launch at login**. That registers the copy in
   `/Applications` as a login item (visible in System Settings ▸ General ▸
   Login Items), so it starts with your Mac and is unaffected by Claude Desktop.

Or simply double-click `/Applications/ClaudeStatus.app` in Finder.

### After editing the code

Changed a title, colour, or anything else in the Swift files? Quit the running
copy and rebuild in one go:

```bash
pkill -f ClaudeStatus.app/Contents/MacOS/ClaudeStatus; ./build.sh run
```

- A typo shows up as a compiler error with the file and line; the app is not
  rebuilt until it compiles.
- The Keychain is read through `/usr/bin/security`, so a rebuild normally
  causes no permission dialog. If one appears anyway, click **Always Allow**.
- Happy with the result? Install the permanent copy (also replaces an older
  one in /Applications):

```bash
./build.sh install
```

Sections 2–9 below describe the full Xcode route instead, which you only need
for signing with your team, Xcode previews, or App Store style distribution.

## Files in this folder

| File                     | Purpose                                                        |
|--------------------------|----------------------------------------------------------------|
| `App.swift`              | `@main` app, `MenuBarExtra` scene                              |
| `Service.swift`          | Credentials loading, API client, observable service, 3-min timer |
| `Views.swift`            | `StatusLabelView` (menu bar text), `StatusMenuView` (dropdown) |
| `build.sh`               | Builds, signs and launches the app without Xcode               |
| `Info.plist`             | Reference plist for the Xcode route (`LSUIElement = YES`)      |
| `assets/claude.svg`      | Claude spark mark (vector, for the Xcode asset catalog)        |
| `assets/claude.png`      | Same mark rasterised, bundled by `build.sh`                    |

## 1. Prerequisites

- macOS 13 Ventura or newer (needed for `MenuBarExtra`).
- Xcode 15 or newer (Xcode 16/26 recommended).
- Claude Code installed and signed in (`claude` → `/login`).

## 2. Create the Xcode project

1. Open Xcode → **File ▸ New ▸ Project…**
2. Choose **macOS ▸ App**, click **Next**.
3. Fill in:
   - Product Name: `ClaudeStatus`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None**
   - Uncheck *Include Tests* (optional)
4. Save it **somewhere else** (e.g. `~/Developer/ClaudeStatus`) — you will copy
   the Swift files from this folder into it.

## 3. Add the source files

1. In the Project navigator, delete the generated `ClaudeStatusApp.swift` and
   `ContentView.swift` (choose *Move to Trash*).
2. Drag these three files from this folder into the `ClaudeStatus` group:
   - `App.swift`
   - `Service.swift`
   - `Views.swift`
3. In the dialog tick **Copy items if needed** and make sure the
   `ClaudeStatus` target is checked.

## 4. Set the deployment target

1. Select the project in the navigator → **ClaudeStatus** target → **General**.
2. Under *Minimum Deployments* set **macOS 13.0** or newer.

## 5. Hide the Dock icon (LSUIElement)

Modern templates have no `Info.plist` file; the values live in the target.

1. Select the **ClaudeStatus** target → **Info** tab.
2. Hover over any row, click **+**, and add:
   - Key: `Application is agent (UIElement)` (raw key `LSUIElement`)
   - Type: Boolean, Value: **YES**

If your project *does* have an `Info.plist` file, copy the `LSUIElement` entry
from the reference `Info.plist` in this folder instead.

The app also calls `NSApplication.shared.setActivationPolicy(.accessory)` at
launch, so it stays out of the Dock even if the plist entry is missing.

## 6. Allow reading credentials and network access

The app reads `~/.claude/.credentials.json` (or the Claude Code entry in your
login Keychain) and talks to `api.anthropic.com`.

1. Select the target → **Signing & Capabilities**.
2. Either **remove the App Sandbox capability** (click the ✕ next to it) — the
   simplest option for a personal tool — **or** keep the sandbox and:
   - tick **Outgoing Connections (Client)** under *Network*, and
   - accept that the sandbox blocks `~/.claude`, so only the Keychain fallback
     will work.
3. Set **Signing ▸ Team** to your Apple ID / team, or choose *Sign to Run
   Locally*.

## 7. Add the Claude icon

1. Open `Assets.xcassets` and drag `assets/claude.svg` from this folder into
   the catalog. Xcode creates an image set named **`claude`** — keep that exact
   name; the code looks it up with `NSImage(named: "claude")`.
2. Select the new image set. The SVG should sit in the **All** slot.
3. In the Attributes inspector set:
   - **Render As: Original Image** — the mark is Claude orange and shown in colour.
   - **Resizing: Preserve Vector Data** (for SVG/PDF).
4. If the asset is missing the app falls back to the `sparkle` SF Symbol, so
   this step is optional to get running.

## 8. Sign in to Claude Code

The app reuses the login of the `claude` command-line tool. Claude Desktop's
own login is not shared with other apps, so sign the CLI in once:

```bash
claude
```

Type `/login` and finish in the browser. On macOS the token lands in the login
Keychain (item **Claude Code-credentials**); on Linux in
`~/.claude/.credentials.json`. The app reads the file first, then the Keychain
(via `/usr/bin/security`, the tool Claude Code stores it with, so no permission
dialog), and the dropdown has a **Sign in via Terminal** button that opens `claude` for
you whenever a sign-in is needed.

When the token expires, start Claude Code again (it refreshes the token), then
click **Refresh (3min)**. If the dropdown says *Claude Code is signed out*, the
Keychain entry exists but holds no token (after `/logout` or a failed refresh):
run `claude` in Terminal and `/login` again. The last failure reason is also
written to `~/Library/Caches/ClaudeStatus/last-error.txt`.

## 9. Build and run

1. Select the **My Mac** destination and press **⌘R**.
2. Look at the top-right of the menu bar for the Claude icon and the three
   gauges. The first fetch happens immediately; then every 3 minutes.
3. Click the label to open the dropdown: a block gauge per limit, reset times
   (live countdown), last-updated stamp, **Refresh (3min)** (⌘R) and **Quit** (⌘Q).
4. Keychain access needs no dialog. If the dropdown ever says "macOS refused
   access to the Claude Code login", open Keychain Access ▸ login ▸
   *Claude Code-credentials* ▸ Access Control and allow ClaudeStatus.

## 10. Launch at login (optional)

1. Build a Release copy: **Product ▸ Archive ▸ Distribute App ▸ Copy App**, or
   **Product ▸ Show Build Folder in Finder** and drag `ClaudeStatus.app` to
   `/Applications`.
2. Launch it from `/Applications` and tick **Launch at login** in the dropdown.
   (Equivalent to adding it under System Settings ▸ General ▸ Login Items.)
   Tick it from the copy you intend to keep — the login item points at that
   exact bundle path.

## Troubleshooting

| Symptom                                                        | Fix |
|----------------------------------------------------------------|-----|
| Label shows `5h –% ▯▯▯▯▯ … ⚠︎`                                  | Open the dropdown — the yellow banner names the problem. |
| "Not signed in to Claude Code"                                 | Click **Sign in via Terminal**, type `/login`. Claude Desktop's login is not shared. If the sandbox is on, disable it (step 6). |
| "OAuth token expired" / "rejected the token (401)"             | Run any `claude` command to refresh the token, then click **Refresh (3min)**. |
| "Unexpected response format" or a gauge looks wrong             | The unofficial endpoint changed. The last raw response (usage numbers only, no token) is saved at `~/Library/Caches/ClaudeStatus/last-usage.json`; compare it with `UsageAPI.parse` in Service.swift. |
| App shows in the Dock                                          | Re-check `LSUIElement = YES` (step 5) and clean build (⇧⌘K). |
| App quits whenever Claude Desktop quits                        | It was launched from a Claude session. Launch it yourself from `/Applications` (or tick **Launch at login**). |
| "Launch at login" toggle won't stick                           | Enable it from the copy in `/Applications`, not from `build/`; macOS ties the login item to the bundle path. |
