## 🎯 Skills System

Skills are on-demand instruction sets in `.agents/skills/`. The system prompt only loads a manifest (name + description per skill). Use the `use_skill` tool to load full instructions when needed.

To add a new skill: create `.agents/skills/<name>.md` with YAML frontmatter (`name` + `description`) and optionally a `.ps1` script alongside it.

### Skill Evolution
When you solve a reusable multi-step task, create a skill for it. Be generous — it's cheaper to prune than to miss patterns. Skills will be reviewed and cleaned up periodically.

## ⚙️ Configuration

- **Entry Point**: `localcode-ps.ps1`
- **API Endpoint**: Configurable via `.env`
- **Environment**: Windows / PowerShell7

## 🛠️ Guidelines
- Commit every change to the repository.
- When asked to "remember" something, update this file.

## 📝 Chat History
- Conversations are saved to `.agents/history.md` for future reference.

## 🧠 Memory
- Always commit every change to the repository.