# serotonin-scripts

Personal scripts for the [Serotonin](https://serotonin-1.gitbook.io) Lua scripting API.

## Development setup

### Requirements

- [VS Code](https://code.visualstudio.com/)
- [luau-lsp](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp) extension
- [Python 3.10+](https://www.python.org/downloads/) — for the MCP bridge server
- [Node.js LTS](https://nodejs.org/) — for the MCP docs server
- Git

### 1. Clone the repo

```bash
git clone git@github.com:mixercodes/serotonin-scripts.git
cd serotonin-scripts
```

### 2. Open in VS Code

```bash
code .
```

Install the [luau-lsp](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp) extension. The repo's `.vscode/settings.json` and `.globals/environment.d.luau` wire it up automatically — full autocomplete and type hints for every Serotonin global with no extra config.

### 3. Set up the MCP servers

Two MCP servers let Claude Code talk to the live game and API docs:

| Server | What it does |
|---|---|
| `serotonin-bridge` | Connects Claude to the running game via `bridge.lua` — live instance inspection, Lua eval, player positions |
| `serotonin-docs` | Serves the community-audited Serotonin API reference so Claude looks up signatures instead of guessing |

**Clone the bridge server**

```bash
git clone https://github.com/DeftSolutions-dev/mcp-serotonin C:/Serotonin/mcp-serotonin
```

**Install Python dependencies**

```bash
pip install -r C:/Serotonin/mcp-serotonin/requirements.txt
```

**Create `.mcp.json` in the repo root** (already present if you cloned this repo — verify the path is correct):

```json
{
  "mcpServers": {
    "serotonin-bridge": {
      "command": "python",
      "args": ["C:/Serotonin/mcp-serotonin/server.py"],
      "env": { "PYTHONUNBUFFERED": "1" }
    },
    "serotonin-docs": {
      "command": "npx",
      "args": ["-y", "mcp-serotonin-docs"]
    }
  }
}
```

**Load `bridge.lua` in Serotonin**

`bridge.lua` is included in this repo at `bridge.lua`. In Serotonin's Scripting tab, load it. You should see:

```
[serotonin-bridge v2] loaded, polling http://127.0.0.1:8765
```

The bridge must be running whenever you want Claude to query live game state.

### 4. Run Claude Code

```bash
claude
```

`CLAUDE.md` is picked up automatically. Claude will use `serotonin-bridge` to inspect the live game and `serotonin-docs` to look up API signatures before writing any Serotonin call.

To verify the bridge is connected, ask Claude to ping it — you should get `"pong"`.

---

## Running scripts

In Serotonin's Scripting tab, use **Load** to run a `.lua` file directly from disk, or fetch from the raw GitHub URL:

```lua
http.Get("https://raw.githubusercontent.com/mixercodes/serotonin-scripts/master/<script>.lua", {}, function(body)
    loadstring(body)()
end)
```

Replace `<script>` with the filename (without `.lua` extension not needed in the URL, include it).

---

## API reference

- **Community docs (preferred)**: https://deftsolutions-dev.github.io/serotonin-api-docs/ — hand-audited against a live runtime, correct signatures and crash flags for all 17 libraries.
- **Official gitbook**: https://serotonin-1.gitbook.io — use as fallback only, known to have drifted from the actual runtime.

## Folder structure

```
.globals/          Luau type stubs for luau-lsp autocomplete
.vscode/           VS Code workspace settings
bridge.lua         Load this in Serotonin to enable the MCP bridge
.mcp.json          MCP server config for Claude Code
CLAUDE.md          Claude Code instructions (AI workflow, conventions, gotchas)
*.lua              Scripts
```
