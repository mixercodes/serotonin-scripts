# serotonin-scripts

Personal scripts for the [Serotonin](https://serotonin-1.gitbook.io) Lua scripting API.

## Scripts

Paste the loadstring into Serotonin's script editor (and then execute) to run a script.

### blue_lock_rivals.lua - Blue Lock: Rivals

Ball physics manipulation (speed multiplier, flat path), ball teleport modes (pull, glue, auto steal), and ESP/on-screen visuals for the ball and players.

```lua
http.Get("https://raw.githubusercontent.com/mixercodes/serotonin-scripts/master/blue_lock_rivals.lua", {}, function(body)
    loadstring(body)()
end)
```

---

## Development

### Requirements

- [VS Code](https://code.visualstudio.com/)
- [luau-lsp](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp) extension
- Git (SSH key configured for GitHub, or use HTTPS)

### Setup

**1. Clone the repo**

```bash
git clone git@github.com:mixercodes/serotonin-scripts.git
cd serotonin-scripts
```

**2. Open in VS Code**

```bash
code .
```

**3. Install luau-lsp**

Install the [luau-lsp](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp) VS Code extension. The repo includes `.vscode/settings.json` and `.globals/environment.d.luau` which wire it up automatically - you get full autocomplete and type hints for every Serotonin global (`game`, `entity`, `draw`, `ui`, etc.) with no extra config.

**4. Edit and push**

Scripts live in the repo root as `.lua` files. Edit, commit, push - the loadstring URLs pull directly from `master` so changes are live immediately.

### Running a script

In Serotonin's Scripting tab, paste the loadstring for the script you want and execute. Each script's loadstring is listed above under Scripts.

### Folder structure

```
.globals/          - Luau type stubs for luau-lsp autocomplete
.vscode/           - VS Code workspace settings (luau-lsp config)
*.lua              - Scripts
CLAUDE.md          - AI assistant instructions (see below)
```

## API reference

- **Community docs (preferred)**: https://deftsolutions-dev.github.io/serotonin-api-docs/ - hand-audited against a live runtime, covers all 17 libraries with correct signatures and crash flags.
- **Official gitbook**: https://serotonin-1.gitbook.io - use as fallback only, known to have drifted from the actual runtime.
