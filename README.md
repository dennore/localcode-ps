# localcode-ps

A super lightweight single-file PowerShell script that connects any OpenAI-compatible endpoint to your codebase as a hands-on coding agent.

No frameworks, no dependencies, just PowerShell.

## ✨ Features

- **File Operations** — Read, write, and edit files with precision (line ranges, string replacement)
- **Command Execution** — Run arbitrary PowerShell commands and capture output
- **Vision Support** — Automatically encodes images (PNG, JPG, GIF, WebP) as base64 for multimodal models
- **Streaming** — Real-time streaming of reasoning and responses
- **Skills System** — On-demand instruction sets that extend agent capabilities without bloating the system prompt
- **Project Memory** — Injects `workspace.md` into the system prompt for persistent context
- **Chat History** — Saves conversations to `.agents/history.md` for future reference
- **Interactive Controls**
  - `Esc` — Stop generation mid-stream
  - `/new` — Reset conversation history
  - `/summarize` — Compress conversation into a summary for continued context
  - `/set <param> <value>` — Tweak sampling parameters on the fly
  - `/<KEY>=<value>` — Set any `.env` variable at runtime (persists to file)
  - `/help` — Show available commands
  - `exit` — Quit

## 🛠️ Tools

| Tool | Description |
| :--- | :--- |
| `read` | Read file content. Supports `start_line` / `end_line` for chunking. Auto-detects images. |
| `write` | Create or overwrite a file. |
| `edit` | Find-and-replace text within a file. |
| `run` | Execute a PowerShell command and return output. |
| `use_skill` | Load a skill's full instructions on demand. |

## 🧩 Skills

Skills are modular instruction sets in `.agents/skills/`. Only a manifest (name + description) is loaded into the system prompt — full instructions are loaded on demand via `use_skill`, keeping context lean.

| Skill | Description |
| :--- | :--- |
| `browser-cdp` | Control Chrome via Chrome DevTools Protocol — web automation, scraping, UI testing |
| `screenshot` | Capture a screenshot of the primary monitor with cursor overlay |
| `click` | Simulate mouse clicks at specific screen coordinates |
| `sendkeys` | Simulate keyboard input and key combinations |
| `caveman` | Ultra-compressed communication mode — cuts token usage ~75% |
| `grill-me` | Stress-test a plan or design through relentless questioning |
| `perplexity` | Research topics using Perplexity AI via the browser |

To add a skill, create `.agents/skills/<name>.md` with YAML frontmatter (`name` + `description`) and optionally a companion `.ps1` script.

## 🚀 Quick Start

### 1. Install PowerShell 7

```powershell
winget install Microsoft.PowerShell
```

### 2. Install Ollama

```powershell
irm https://ollama.com/install.ps1 | iex
```

### 3. Pull a model

```powershell
ollama pull gemma4:e4b
```

### 4. Configure

```powershell
cp .env.example .env
```

Edit `.env` to set your model, endpoint, and preferences:

```env
API_URL=http://localhost:11434/v1/chat/completions
API_KEY=sk-no-key-required
MODEL_NAME=gemma4:e4b
TEMPERATURE=0.7
TOP_P=0.9
REPEAT_PENALTY=1.1
MAX_TOKENS=4096

# Agent Settings
SHOW_REASONING=true
SHOW_FILE_READS=true
SHOW_FILE_EDITS=true
SHOW_FILE_WRITES=true
SHOW_CONSOLE_RETURN=false
SHOW_USE_SKILL=false
```

Works with any OpenAI-compatible endpoint — Ollama, llama.cpp, LM Studio, vLLM, etc.

### 5. Run

```powershell
.\localcode-ps.ps1
```

## 📂 Project Structure

```
localcode-ps.ps1          # Agent entry point (single file, ~200 lines)
.env                      # Local configuration (not tracked)
.env.example              # Configuration template
.agents/
  workspace.md            # Persistent project memory & instructions
  history.md              # Chat history log
  skills/
    <name>.md             # Skill instructions (YAML frontmatter + markdown)
    <name>.ps1            # Optional companion script
```

## ⚠️ Notes

- The **browser-cdp** skill launches Chrome with an **isolated debug profile** (`Chrome\Agent`) — it does not touch your real Chrome profile or sign-in state.
- Skills with companion `.ps1` scripts (screenshot, click, sendkeys, cdp) require **Windows**.

## 📝 License

MIT
