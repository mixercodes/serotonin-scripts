# serotonin-scripts

Personal scripts for the [Serotonin](https://serotonin.win/) Lua scripting API, with a full Claude Code AI setup for script writing and live game inspection.

## Development setup

### Requirements

- [VS Code](https://code.visualstudio.com/)
- [luau-lsp](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp) extension
- [Node.js LTS](https://nodejs.org/)
- Git

### 1. Clone the repo

```bash
git clone https://github.com/mixercodes/serotonin-scripts.git C:/Serotonin/scripts
cd C:/Serotonin/scripts
```

> The repo must live at `C:\Serotonin\scripts` — the MCP server and `CLAUDE.md` paths depend on it.

### 2. Open in VS Code

```bash
code .
```

Install the [luau-lsp](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp) extension. The repo's `.vscode/settings.json` and `.globals/environment.d.luau` wire it up automatically — full autocomplete and type hints for every Serotonin global with no extra config.

### 3. Set up the MCP servers

Two MCP servers let Claude Code talk to the live game and API docs:

| Server | What it does |
|---|---|
| `serotonin` | File-based IPC bridge to the running game — workspace dumps, Lua eval, instance inspection, UI read/write |
| `serotonin-docs` | Community-audited API reference so Claude looks up signatures instead of guessing |

**Clone and build the serotonin MCP server:**

```bash
git clone https://github.com/mixercodes/mcp-serotonin-v2 C:/Serotonin/mcp-serotonin-v2
cd C:/Serotonin/mcp-serotonin-v2
npm install
npm run build
```

**The `.mcp.json` in this repo is pre-configured** — verify the path matches your install location:

```json
{
  "mcpServers": {
    "serotonin": {
      "command": "node",
      "args": ["C:/Serotonin/mcp-serotonin-v2/dist/index.js"]
    },
    "serotonin-docs": {
      "command": "npx",
      "args": ["-y", "mcp-serotonin-docs"]
    }
  }
}
```

**Load `agent.lua` in Serotonin:**

In Serotonin's Scripting tab, load `C:/Serotonin/mcp-serotonin-v2/lua/agent.lua` directly from the MCP repo. The HUD bottom-right will show `Agent: idle` when ready. Loading it from the MCP repo means you always get the latest version when you pull updates there.

### 4. Run Claude Code

```bash
claude
```

`CLAUDE.md` is picked up automatically. To verify everything is connected, ask Claude to ping — you should get `pong — agent is live`.

---

## Running scripts

In Serotonin's Scripting tab, use **Load** to run a `.lua` file directly from disk, or fetch from the raw GitHub URL:

```lua
http.Get("https://raw.githubusercontent.com/mixercodes/serotonin-scripts/master/<script-name>.lua", {}, function(body)
    loadstring(body)()
end)
```

---

## API reference

- **Community docs (preferred)**: https://deftsolutions-dev.github.io/serotonin-api-docs/ — hand-audited against a live runtime, correct signatures and crash flags for all 17 libraries.
- **Official gitbook**: https://serotonin-1.gitbook.io — use as fallback only, known to have drifted from the actual runtime.

---

## Folder structure

```
.globals/          Luau type stubs for luau-lsp autocomplete
.vscode/           VS Code workspace settings
.mcp.json          MCP server config for Claude Code
CLAUDE.md          Claude Code instructions (AI workflow, conventions, gotchas)
*.lua              Scripts
```
