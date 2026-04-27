# serotonin-scripts

Personal scripts for the [Serotonin](https://serotonin-1.gitbook.io) Lua scripting API.

## Setup

### 1. Clone the repo

```bash
git clone git@github.com:mixercodes/serotonin-scripts.git
```

Place the folder wherever you like, the scripts are loaded directly from disk by Serotonin.

### 2. Install luau-lsp (VS Code)

Install the [luau-lsp](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp) extension. The included `.vscode/settings.json` and `.globals/environment.d.luau` wire it up automatically, giving you full autocomplete and type hints for every Serotonin API out of the box.

### 3. Load a script

Open Serotonin → Scripting tab → load the `.lua` file. Scripts are event-driven; they register callbacks rather than running top-to-bottom.

## Scripts

| Script | Game | Description |
|---|---|---|
| `blue_lock_rivals.lua` | Blue Lock: Rivals | Ball physics manipulation (speed multiplier, flat path), ball teleport modes (pull, glue, auto steal), and ESP/on-screen visuals for the ball and players. |

## Loadstring

```lua
http.Get("https://raw.githubusercontent.com/mixercodes/serotonin-scripts/master/blue_lock_rivals.lua", {}, function(body)
    loadstring(body)()
end)
```

## API reference

- **Community docs**: https://deftsolutions-dev.github.io/serotonin-api-docs/ - hand-audited against a live runtime, covers all 17 libraries with correct signatures and crash flags. Prefer this over the official gitbook.
- **Official gitbook**: https://serotonin-1.gitbook.io - use as a fallback only, known to have drifted.
