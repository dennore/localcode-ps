---
name: click
description: Simulate mouse clicks at specific screen coordinates.
---

# Click

Simulates mouse clicks at exact pixel coordinates via Windows API.

```powershell
.\.agents\skills\click.ps1 -x <X> -y <Y> [-clickType left|right|middle|double]
```

- Coordinates are absolute screen pixels (top-left = 0,0)
- Default click type: `left`
- Always take a screenshot first to identify coordinates
