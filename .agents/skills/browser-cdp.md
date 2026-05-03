---
name: browser-cdp
description: Navigate, interact, and screenshot web pages via Chrome/Edge.
---

# Browser CDP

Control a browser via CDP WebSocket. Auto-discovers running Chrome/Edge or launches a new instance with an isolated debug profile.

## Usage

```
pwsh -File cdp.ps1 -Action <action> -Params '<json>' [-Port <port>]
```

| Action | Params | Description |
|:---|:---|:---|
| `navigate` | `{"url": "..."}` | Go to URL |
| `eval` | `{"expression": "..."}` | Run JS, return result |
| `click` | `{"selector": "..."}` | Click element by CSS selector |
| `type` | `{"selector": "...", "text": "..."}` | Type into element |
| `screenshot`| `{"path": "out.png"}` | Capture page as PNG |
| `tabs` | `{}` | List open pages |

## Workflow

1. `navigate` to target URL
2. `eval` / `click` / `type` to interact
3. `screenshot` or `eval` to verify results
4. `tabs` to see all open pages

## Notes

- Auto-discovers browser via `DevToolsActivePort` files, launches Chrome if none found
- Uses isolated profile (`Chrome\Agent`) — never touches your real profile
- Attaches to the first non-`chrome://` page target, or creates a blank tab
