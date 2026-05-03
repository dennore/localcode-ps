---
name: sendkeys
description: Simulate keyboard input and key combinations to the active window.
---

# SendKeys

Simulates keyboard input via WScript.Shell.

```powershell
.\.agents\skills\sendkeys.ps1 -text "<keys>"
```

## Special Keys

| Key | Syntax | | Key | Syntax |
|:---|:---|:---|:---|:---|
| Enter | `{ENTER}` | | Ctrl | `^` (prefix) |
| Tab | `{TAB}` | | Alt | `%` (prefix) |
| Escape | `{ESC}` | | Shift | `+` (prefix) |
| Arrows | `{UP}` `{DOWN}` `{LEFT}` `{RIGHT}` | | Delete | `{DELETE}` |

## Examples

```powershell
.\.agents\skills\sendkeys.ps1 -text "Hello World"
.\.agents\skills\sendkeys.ps1 -text "^a"          # Ctrl+A
.\.agents\skills\sendkeys.ps1 -text "%{F4}"       # Alt+F4
```

Focus the target window first (use click skill if needed).
