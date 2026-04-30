# CLAUDE.md

Instructions for Claude Code when working in this repository.

## AI Setup

This repo is configured for use with [Claude Code](https://claude.ai/code) (Anthropic's CLI) as the primary AI assistant. The setup consists of three layers:

**1. This file (CLAUDE.md)**
Loaded automatically by Claude Code on every session. Contains workflow rules, runtime-verified behaviors, coding conventions, and gotchas. Claude follows these over its defaults.

**2. MCP servers**
Two MCP servers extend Claude's capabilities beyond file editing:

- `serotonin-docs` - serves the community-audited Serotonin API reference (17 libraries, 130 functions, crash flags). Claude queries this before writing any API call instead of guessing.
- `serotonin-bridge` - connects to the live running Roblox game via `bridge.lua`. Lets Claude inspect the real instance tree, run Lua, read player positions, and verify game state while writing scripts.

Both MCP servers are from [DeftSolutions-dev/mcp-serotonin](https://github.com/DeftSolutions-dev/mcp-serotonin) - setup instructions are on that repo.

MCP config lives in `.mcp.json` at the repo root (or your Claude Code settings). To use the bridge, load `bridge.lua` in Serotonin before starting a Claude session.

**3. Type stubs (`.globals/environment.d.luau`)**
Luau type definitions for luau-lsp autocomplete. Claude uses these as a secondary reference - runtime behavior always wins over the stubs when they conflict.

### Using Claude Code here

```bash
# From the repo root:
claude
```

Claude will pick up CLAUDE.md automatically. For bridge-assisted script writing, make sure Serotonin is running with `bridge.lua` loaded first - Claude will ping it to confirm the connection before making live game queries.

## No Guessing API Syntax

Never guess Serotonin API signatures. Before writing any API call, look it up via `mcp__serotonin-docs__get_function` or `mcp__serotonin-docs__search_pages`. Serotonin's API regularly differs from Roblox executor conventions, standard Lua, and other scripting platforms.

## Maintenance Rules

CLAUDE.md is for: workflow, conventions, runtime corrections to stubs, and things no other file captures.
CLAUDE.md is **not** for: type signatures or method lists (→ `.globals/environment.d.luau`), crasher lists (→ `crash_blacklist.json`), or generic Lua advice.
Before adding anything here: check if it belongs in one of those files instead. If adding a runtime correction, update the stubs too — don't duplicate, redirect.

## Project Overview

Serotonin is a Lua-based scripting API for Roblox game modifications. Scripts are `.lua` files in `scripts/`, loaded via the Serotonin menu's Scripting tab. The runtime is event-driven — scripts register callbacks, not loops.

## Event System

Register callbacks with `cheat.register(eventName, callback)`:

| Event | Fires | Use for |
|---|---|---|
| `onPaint` | Every frame (incl. alt-tabbed / menu closed) | All drawing, frame-timed automation |
| `onUpdate` | ~5ms | Game logic, target finding |
| `onSlowUpdate` | ~1s | Background checks, periodic tasks |
| `shutdown` | Once | Cleanup on script unload |
| `newPlace` | On change | Place/server transitions |

## Global Modules

All globals are available without `require`:

| Module | Purpose |
|---|---|
| `game` | Live Roblox data model (Workspace, Players, instances) |
| `entity` | Cached player/part snapshots for ESP/aimbot |
| `draw` | 2D rendering (lines, rects, text, polygons) |
| `ui` | Menu UI builder (tabs, containers, widgets) |
| `utility` | Helpers: WorldToScreen, mouse pos, RNG, clipboard, images |
| `mouse` | Mouse simulation and button state |
| `keyboard` | Keyboard simulation and key state |
| `audio` | WAV playback, beeps |
| `file` | Sandboxed file I/O |
| `http` | Async HTTP GET/POST |
| `websocket` | WebSocket connections |
| `memory` | Direct memory read/write/scan |
| `cheat` | Event registration, window size, LoadString |

## Key Concepts

**`game` vs `entity`**: `game` accesses the live instance tree. `entity` provides cached snapshots updated at optimized intervals. Use `entity` for performance-sensitive reads (ESP, aimbot); use `game` for instance manipulation.

**Drawing pipeline**: `draw.GetPartCorners(instance)` -> 8 world-space Vector3 corners -> `utility.WorldToScreen(vec3)` -> screen coords -> draw with `draw.Polyline` / `draw.ConvexPolyFilled`.

**Custom models**: `entity.AddModel(key, data)` / `entity.EditModel()` / `entity.RemoveModel()` add NPCs/objects to the entity cache.

## Live Game State (MCP bridge)

An MCP server at `C:/Serotonin/mcp-serotonin/` exposes **live** data from the running game when `bridge.lua` is loaded in Serotonin. Use it to ground script writing in the actual game state instead of guessing instance names or hoping `entity.GetPlayers` works in this mode.

Tools (all prefixed `serotonin_`):

| Tool | Use when |
|---|---|
| `ping` | Verify bridge is live |
| `eval` | Run arbitrary Lua; returns serialized result (Instances → handles, Vector3/Color3 keep types) |
| `inspect` / `safe_inspect` | Properties / Attributes / Children of an Instance |
| `tree` / `search_instances` / `find_by_class` | Walk the data model |
| `list_players` / `players_full` | Enemy list with live HRP + screen projection (prefer `players_full`) |
| `get_bones` | Bone positions for a player |
| `list_parts` / `nearest` | Parts around the player |
| `project_to_screen` / `screen_info` | WorldToScreen, window size, mouse, camera |
| `memory_read` / `memory_write` / `memory_base` | Direct memory access |
| `get_scripts` | Dot-paths to all Script/LocalScript/ModuleScript (source not exposed) |

**When to use it**: before writing anything mode-specific (ESP, aimbot, entity queries), call `players_full` / `tree` to confirm the instance layout. When a user reports "the script doesn't see X", inspect the live tree first.

**When *not* to use it**: API reference questions. The bridge doesn't know Serotonin's Lua API shape — use the `serotonin-docs` MCP for that.

**Known crashers**: the bridge auto-blocks these in `eval` — see `C:/Serotonin/mcp-serotonin/crash_blacklist.json` for the authoritative list. Parallel `eval` calls also crash — the server serializes them, stay on the tools.

**Gotchas verified via bridge use**:
- `game.GetService` uses dot syntax: `game.GetService("Players")`, not `game:GetService(...)`. The Lua `game` is a sandbox proxy table, not an Instance userdata.
- `entity.GetPlayers()` returns userdata (not indices as older docs claim). Access fields as `p.Name`, call bone methods as `p:GetBonePosition("HumanoidRootPart")`.
- `entity.Position` is often stale (stays at `(0,0,0)` in FFA modes). Use `p:GetBonePosition("HumanoidRootPart")` for the live value.
- Valid `memory.Read` / `memory.Write` types: see `MemoryType` in `.globals/environment.d.luau`.
- **Bridge observations are only valid for the current game state.** Never draw conclusions from bridge data collected outside the game state being debugged — instance structure and value semantics can differ significantly between states.
- **Always verify the Lua `type()` of a value before writing comparisons against it.** A `BoolValue.Value` may be exposed as a number in Serotonin's sandbox — `op.Value == true` silently fails if the value is numeric.

## Documentation

**Primary reference: deftsolutions community-audited docs (MCP `serotonin-docs`).** The official Serotonin gitbook (`serotonin-1.gitbook.io`) has drifted — whole libraries missing, signatures wrong, crashers unflagged. The community reference at https://deftsolutions-dev.github.io/serotonin-api-docs/ is hand-audited against a live runtime (build `2e6461290a3541f5`): 17 libraries, 130 canonical functions, 282 aliases, every snippet pcall-probed. Crashers (e.g. `audio.PlaySound` non-WAV, `cheat.LoadString`, undocumented LocalPlayer fields) are flagged inline.

Use the `serotonin-docs` MCP tools for API questions:

| Tool | Use when |
|---|---|
| `mcp__serotonin-docs__list_pages` | Browse what libraries / pages exist |
| `mcp__serotonin-docs__read_page` | Pull a full page (e.g. `entity`, `draw`, `ui`) |
| `mcp__serotonin-docs__search_pages` | Keyword search across the whole reference |
| `mcp__serotonin-docs__get_function` | Resolve a specific function (canonical or alias) to its signature, examples, and crash flags |

For LLM context bundling: the full reference is also available as a single blob at https://deftsolutions-dev.github.io/serotonin-api-docs/llms-full.md.

**Resolution order for API questions:** `serotonin-docs` MCP → `.globals/environment.d.luau` (type stubs, least reliable for runtime). Where these disagree with observed runtime behavior, runtime wins.

## Type Definitions

[.globals/environment.d.luau](.globals/environment.d.luau) provides Luau types for `luau-lsp` autocomplete. Where stubs and runtime disagree, runtime wins.

## Coding Conventions

- `snake_case` for local variables and functions
- Pick one API casing style per script (PascalCase, camelCase, or snake_case) and stay consistent
- Colors: always `Color3` objects, never raw integers
- Alpha: integer 0-255
- `Color3.new(r, g, b)` takes 0-1; `Color3.fromRGB(r, g, b)` takes 0-255
- All `draw` calls must be inside an `onPaint` callback
- `ipairs` for arrays, `pairs` for dictionaries
- Prefer early returns over deep nesting
- `local` for all variables

## Language Constraints

These features do **not** exist in the runtime:

- `continue` keyword — use `goto label` / `::label::` instead (goto works)
- `+=`, `-=` compound assignment — write `x = x + 1`
- Type annotations — no Luau syntax at runtime
- String interpolation (`` `{}` ``) — use `string.format()` or `..` concatenation

## Runtime-Verified Behaviors

These behaviors have been confirmed in production scripts:

- `utility.GetMousePos()` returns `{[1]=x, [2]=y}` — access as `mpos[1]`, `mpos[2]`, not `.x`/`.y`
- `ui.getValue` on dropdowns returns **0-based** index — use `options[idx + 1]` to index into a Lua table.
- `ui.setValue` on dropdowns is **0-based** — pass `0` for the first item, `1` for the second, etc.
- `ui.newDropdown` 5th arg (default) is **1-based** — pass `1` for the first item, `2` for the second. This is the only place that differs: `getValue` and `setValue` are both 0-based; the 5th arg to `newDropdown` is 1-based.
- `ui.setValue` works at top-level after widget creation for setting defaults. For sliders, when the type stub flags the 6th arg (default) of `newSliderFloat` as a mismatch, omit the 6th arg and set the default via `ui.setValue` instead — runtime accepts it either way.
- `loadstring(str)()` works for dynamic code execution
- `ui.NewColorpicker(... inLine=true)` attaches to the **immediately preceding widget in declaration order** — declare each colorpicker directly after its paired widget, not at the end of the block
- **Checkbox + colorpicker pairs are lumped**: any checkbox (or dropdown) that gates a visual element is immediately followed by its colorpicker with `inLine=true`. This is the standard layout across Serotonin scripts and is how users expect the UI to read — do not group all pickers at the bottom.
- **Multiple colorpickers can be chained inline**: you can place as many `inLine=true` colorpickers in a row as needed — each attaches inline after the previous widget. Use this when a feature naturally has multiple related colors (e.g. a gradient's high and low colors both sit under their parent checkbox). Group pickers by what they control, not by widget type.
- **Hotkeys use `ui.newHotkey(tab, container, label, true)`**: the `true` 4th arg is `inLine` — attaches the widget inline on the same row as its preceding checkbox (runtime-verified). Declare it directly after its paired checkbox; a hotkey not paired with a checkbox may render incorrectly.
  - `ui.getValue(tab, container, label)` → `bool` (true while the bound key is held). For a simple held-state gate: `if ui.getValue(...) ~= true then return end`
  - For single-press / toggle triggers, use edge detection:
    ```lua
    local hk_prev = {}
    local function hotkey_clicked(label)
        local now  = ui.getValue(TAB, CONTAINER, label)
        local edge = now and not (hk_prev[label] or false)
        hk_prev[label] = now
        return edge
    end
    ```
  - `ui.getHotkey(tab, container, label)` → `{key, key_name, mode}` if you need the bound key name/code.
  - Set default binding with `ui.setValue(tab, container, label, vk_code)` (Windows VK code: `0x46` = F, `0x47` = G, `0x70` = F1, letters A-Z = `0x41..0x5A`).
  - Do not use dropdown + `keyboard.IsPressed` for keybinds.
- **Containers use `next = true` for side-by-side layout**: colorpickers inline on a checkbox (`inLine=true`) still work fine, but a full-width container still feels cramped. Pair your main settings container with a secondary "Info"/"Status" container using `next = true` so the tab isn't one giant column.

## Dynamic Game Data

Game data (team names, instance names, folder structure, object positions) can change between matches and server instances. Never hardcode or assume in-game state — always query dynamically at runtime:
- Player team: `pcall(function() player_team = tostring(lp.Team) end)` — returns the live team name as a string ("Home", "Away", etc.)
- Target goal: iterate `Goals:GetChildren()` and find the `Part`/`MeshPart` whose `.Name == player_team` — goals are named after the team that scores into them, so match the player's team name directly. Do not hardcode "Home"/"Away" string comparisons.
- Instance children: use `:FindFirstChild()` or `:GetChildren()` on live instances each time, not cached name assumptions
- Use the bridge (`players_full`, `tree`, `eval`) to verify actual instance names before writing any game-specific lookup

## Before Writing Any Script

**Always ask the user first:** "Do you have an existing utility/library for this?" before implementing from scratch. Building on top of a known-working base is always preferable to reinventing it.

**For movement/physics scripts — `instance.Position = value` is the correct mechanism.** Do not reach for `Velocity` writes or memory writes for movement. Instant teleport (a single position write) works fine in most games and is the default unless the user asks for smooth movement.

**Smooth tweening requires no external library.** Build it from first principles when needed:
- Timing: `utility.GetTickCount()` for elapsed ms
- Interpolation: `Vector3:Lerp(target, alpha)` 
- Easing: pure math functions (cubic, sine, etc.) applied to a 0→1 progress value
- Drive: spam-write the lerped position in `onUpdate` each frame until progress reaches 1

Never wait for the user to provide a tween implementation — the above pattern is sufficient and self-contained.

## Best Practices

- Nil-check before accessing nested properties (`game.LocalPlayer`, `.Character`, `:FindFirstChild()`)
- `entity.GetPlayers(true)` for enemies only
- Register `shutdown` callback for cleanup (`entity.ClearModels()`, etc.)
- Check `onScreen` boolean from `utility.WorldToScreen()` before drawing
- `pcall` for operations that may fail (memory access, file reads)
- **Treat new instances as read-only until physics writes are bridge-verified**: server-owned parts accept velocity writes locally but the server overrides them immediately, producing infinite momentum. Write a velocity via the bridge, wait ~1s, read it back — if it hasn't decayed, the part is server-owned and must not be written to.
- `draw.TextOutlined` over `draw.Text` for readability
- `draw.GetTextSize()` for centering text
- Localize hot math functions: `local sin, cos = math.sin, math.cos`
- Cache aggressively: text sizes, rotation matrices, part corners, memory reads
- Chunk heavy processing across frames to avoid drops

## Performance Patterns

- Pre-allocate tables and reuse buffers instead of creating new ones each frame
- Time-based cache invalidation for rotation matrices and transforms
- Chunked iteration for large instance scans (process N per frame, not all at once)
- Accumulator patterns for sub-pixel mouse movement
- Store `instance.Address` as a stable unique identifier for tracking
