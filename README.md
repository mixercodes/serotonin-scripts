# serotonin-scripts

Personal scripts for the [Serotonin](https://serotonin-1.gitbook.io) Lua scripting API.

## Setup

### 1. Clone the repo

```bash
git clone git@github.com:mixercodes/serotonin-scripts.git
```

Place the folder wherever you like — the scripts are loaded directly from disk by Serotonin.

### 2. Install luau-lsp (VS Code)

Install the [luau-lsp](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp) extension. The included `.vscode/settings.json` and `.globals/environment.d.luau` wire it up automatically — you get full autocomplete and type hints for every Serotonin API out of the box.

### 3. Load a script

Open Serotonin → Scripting tab → load the `.lua` file. Scripts are event-driven; they register callbacks rather than running top-to-bottom.

## Scripts

| Script | Description |
|---|---|
| `pitch_control.lua` | ... |

## API reference

Community-audited docs: https://deftsolutions-dev.github.io/serotonin-api-docs/
