# CLAUDE.md

Instructions for Claude Code when working in this repository.

## AI Setup

This repo is configured for use with [Claude Code](https://claude.ai/code) (Anthropic's CLI) as the primary AI assistant. The setup consists of three layers:

**1. This file (CLAUDE.md)**
Loaded automatically by Claude Code on every session. Contains workflow rules, runtime-verified behaviors, coding conventions, and gotchas. Claude follows these over its defaults.

**2. MCP servers**
Two MCP servers extend Claude's capabilities beyond file editing:

- `serotonin-ref` - serves the Serotonin API reference (17 libraries, 130 functions, runtime-verified). Claude queries this before writing any API call instead of guessing. Hosted HTTP MCP at `https://serotonin-ref.vercel.app/api/mcp`.
- `serotonin` - file-based IPC bridge to the live running Roblox game via `agent.lua`. Lets Claude dump the instance tree, run lightweight Lua, inspect instances, read/write UI values, and verify game state while writing scripts. File-based IPC — no HTTP overhead.

The `serotonin` server is at [mixercodes/mcp-serotonin-v2](https://github.com/mixercodes/mcp-serotonin-v2). The `serotonin-ref` server is hosted at `https://serotonin-ref.vercel.app/api/mcp` — no local install needed.

MCP config lives in `.mcp.json` at the repo root. To use the agent, load `C:/Serotonin/mcp-serotonin-v2/lua/agent.lua` directly from the MCP repo in Serotonin before starting a Claude session.

**3. Type stubs (`.globals/environment.d.luau`)**
Luau type definitions for luau-lsp autocomplete. Claude uses these as a secondary reference - runtime behavior always wins over the stubs when they conflict.

### Using Claude Code here

```bash
# From the repo root:
claude
```

Claude will pick up CLAUDE.md automatically. For live game queries, make sure Serotonin is running with `agent.lua` loaded first. Claude will ping it to confirm the connection before making live game queries.

## No Guessing API Syntax

Never guess Serotonin API signatures. Before writing any API call, look it up via the `serotonin-ref` MCP — use `list_functions` to discover what a library offers, then `lookup` to pull the exact signature. Serotonin's API regularly differs from Roblox executor conventions, standard Lua, and other scripting platforms.

## Maintenance Rules

CLAUDE.md is for: workflow, conventions, runtime corrections to stubs, and things no other file captures.
CLAUDE.md is **not** for: type signatures or method lists (→ `.globals/environment.d.luau`), generic Lua advice, or **game-specific content** (instance names, item names, game mechanics from a specific Roblox game). Game-specific observations belong in comments in the relevant script, not here.
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

## Live Game State (MCP agent)

The `serotonin` MCP server at `C:/Serotonin/mcp-serotonin-v2/` exposes **live** data from the running game when `agent.lua` is loaded in Serotonin. Uses file-based IPC — no WebSocket, no crash risk. Use it to ground script writing in the actual game state instead of guessing instance names.

| Tool | Use when |
|---|---|
| `ping` | Verify agent is live |
| `eval` | Run a lightweight Lua expression; returns JSON-serialized result |
| `dump_workspace` | Full Workspace tree dump, chunked across frames (safe for large games) |
| `dump_subtree` | Dump a specific subtree (e.g. ReplicatedStorage, a single model) — faster and smaller than a full workspace dump |
| `list_dumps` | List saved dump files, newest first |
| `read_dump` | Page through a dump file by line offset |
| `grep_dump` | Regex-search a dump for instance names, classes, or value flags |
| `inspect` | Properties + children of a specific instance by Lua path |
| `inspect_service` | Top-level children of a Roblox service (Players, ReplicatedStorage, etc.) |
| `find_by_class` | Find all instances of a given ClassName within a root (capped at 100) |
| `players` | Player list with live positions; includes local player (`is_local: true`) |
| `get_bones` | R6/R15 bone positions + screen projections for a specific player; auto-detects rig type; works on local player too |
| `screen_info` | Window dimensions, camera world position, mouse position |
| `world_to_screen` | Project a world-space Vector3 to screen coordinates |
| `get_attributes` | All attributes on a specific instance by Lua path (invisible to dumps) |
| `get_ui` / `set_ui` | Read or write a Serotonin UI widget value |

**When to use it**: before writing anything mode-specific (ESP, aimbot, entity queries), run `dump_workspace` then `grep_dump` to confirm the instance layout. When a user reports "the script doesn't see X", use `inspect` or `grep_dump` to find it in the live tree.

**When *not* to use it**: API reference questions. The agent doesn't know Serotonin's Lua API shape — use the `serotonin-ref` MCP for that.

**`eval` is for lightweight queries only.** Do not use it for heavy recursive work — use `dump_workspace` for tree traversal. Simple expressions like `return game.PlaceId` or `return entity.GetPlayers(true)` are fine.

### Investigation decision table

Use this to pick the right tool the first time. `grep_dump` is always the search step — never use Python or external tools to search dump output.

| Looking for… | Do this |
|---|---|
| **Player action/state flags** (is X stealing, blocking, guarding, etc.) | `get_attributes` on the character (`game.Workspace:FindFirstChild(name)`) and on the Player object in the Players service. Also check the `Humanoid` and `HumanoidRootPart` for attributes. Attributes are the standard carrier for per-player boolean state and are invisible to dumps. |
| **Local player's flags** | `get_attributes` on `game.Workspace:FindFirstChild(entity.GetLocalPlayer().Name)` |
| **Instance names / tree structure** in Workspace | `dump_workspace` → `grep_dump` with a keyword regex |
| **Something inside a specific large service** (ReplicatedStorage, ServerStorage, etc.) | `dump_subtree` on that service → `grep_dump`. **Never use `eval` with recursive Lua to scan a service** — it produces output too large to process. |
| **Properties of one known instance** | `inspect` with the full Lua path (e.g. `game.Workspace.Game.Ball`) |
| **Top-level children of a service** | `inspect_service` (e.g. Players, ReplicatedStorage) |
| **All instances of a type** | `find_by_class` — faster than a full dump when you just need one ClassName |
| **Whether a player holds an item** | `eval` → `char:FindFirstChildOfClass("Tool")` — tools appear as children of the character when held |
| **Bone positions / ESP data for a player** | `get_bones` — auto-detects R15 vs R6, works on local player too |
| **Screen dimensions or camera position** | `screen_info` |

**Attributes are invisible to dumps.** `grep_dump` only sees instance names and classes — it cannot find data stored as instance attributes. If you grep a dump and find nothing, check `GetAttributes()` on the relevant instance via `eval` before concluding the data isn't there.

**`GetAttributes()` format in Serotonin's sandbox**: returns an array of tables, not a flat dict. Each entry is `{Name = "...", TypeName = "bool"/"int"/etc., Value = ...}`. Iterate with `pairs` and check `attr.Name` and `attr.Value`.

**`draw.*` alpha is 0–255 at runtime — the serotonin-docs reference is wrong about this.** The docs page states *"Alpha (where supported) is a separate trailing `0..1` argument"* and shows examples with `alpha = 1`, `0.85`, `0.7`. That description does not match the runtime: the engine treats the argument as a 0–255 byte, so passing `1` renders at 1/255 opacity (effectively invisible) and passing `0.85` at under 1%. Use `255` for fully opaque, `0` for transparent, and integer values in between for partial opacity. Applies to every draw call: `Rect`, `RectFilled`, `Line`, `Text`, `TextOutlined`, `Circle`, `Polyline`, `ConvexPolyFilled`, `Gradient`, etc. Confirmed by `blue_lock_rivals.lua` using `180` and `90` for visually distinct opacity levels (both would clamp to 1.0 if the range were truly 0..1), and `localplayer_esp.lua` using `200`/`255`.

**`p.IsVisible` requires a Visible Only check active in Serotonin** — with none enabled (ESP, Aimbot, or Triggerbot), returns `false` for all players. Enable at least one Visible Only check for valid wall-check results.

**`HumanoidRootPart.CFrame` returns `nil` for non-local players** — confirmed via eval. `LookVector`, `RightVector`, and `GetComponents()` are all inaccessible. To get a player's facing direction, track their position delta across ticks: cache the last non-zero movement vector and use it as the facing direction (works even when they stop, since the last direction persists).

**Gotchas verified via agent eval**:
- `game.GetService` uses dot syntax: `game.GetService("Players")`, not `game:GetService(...)`. The Lua `game` is a sandbox proxy table, not an Instance userdata.
- `entity.GetPlayers()` returns userdata (not indices as older docs claim). Access fields as `p.Name`, call bone methods as `p:GetBonePosition("HumanoidRootPart")`.
- `entity.GetPlayers(false)` **excludes the local player**. Use `entity.GetLocalPlayer()` to get the local player entity. `game.GetService("Players").LocalPlayer` is nil in Serotonin's sandbox — never use it.
- `entity.Position` is often stale (stays at `(0,0,0)` in FFA modes). Use `p:GetBonePosition("HumanoidRootPart")` for the live value.
- **Entity cache only tracks bone positions for enemies, not teammates.** `p:GetBonePosition()` returns `(0,0,0)` for non-enemy players even when they're alive and moving. `p.BoundingBox` is also empty for teammates. Fall back to workspace for teammate positions: `game.Workspace:FindFirstChild(p.Name):FindFirstChild("HumanoidRootPart").Position`. Confirmed via eval: all 4 teammates had `hrp_zero=true` from entity but valid positions from workspace.
- **R15 vs R6 bones**: R15 characters use `UpperTorso`/`LowerTorso`/`LeftUpperArm` etc. instead of `Torso`/`Left Arm` etc. The `get_bones` MCP tool auto-detects rig type by checking for `UpperTorso` in the character. When writing ESP manually, do the same check.
- **`GetBonePosition` can return nil** — despite docs stating it returns `Vector3(0,0,0)` for missing bones, it has been observed returning nil in production (confirmed: caused `attempt to index local 'b' (a nil value)` on line accessing `.X`). Always guard with `if not b then` before indexing. Zero-vector check is still needed separately for bones that exist but have no valid position.
- Valid `memory.Read` / `memory.Write` types: see `MemoryType` in `.globals/environment.d.luau`.
- **Agent observations are only valid for the current game state.** Never draw conclusions from data collected outside the game state being debugged — instance structure and value semantics can differ significantly between states.
- **Always verify the Lua `type()` of a value before writing comparisons against it.** A `BoolValue.Value` may be exposed as a number in Serotonin's sandbox — `op.Value == true` silently fails if the value is numeric.
- **`_G` is nil in Serotonin's sandbox** — use bare globals directly: `_ESP_LOADED = true`, not `_G._ESP_LOADED = true`. The `_G` table does not exist.
- **`cheat.register` cannot be called from inside `pcall`** — raises `"Cannot register callback outside of a script's main execution block."` When executing a script via `eval`+`loadstring`, call `fn()` directly, not `pcall(fn)`.
- **`file.read` sandbox root is `files/`, not `scripts/`** — scripts live in `C:/Serotonin/scripts/` which is outside the sandbox. Use absolute paths: `file.read("C:/Serotonin/scripts/myscript.lua")`.
- **No `cheat.Unregister` — to "unload" via eval, set Enable to false and clear the guard flag.** Callbacks cannot be removed once registered. The practical pattern: `ui.setValue(TAB, CON, "Enable", false); _SCRIPT_LOADED = nil` — callbacks still fire but return immediately, and the script can be re-run fresh.

## Documentation

**Primary reference: serotonin-ref (MCP `serotonin-ref`).** The official Serotonin gitbook (`serotonin-1.gitbook.io`) has drifted from the runtime — use it as a fallback only. The reference at https://serotonin-ref.vercel.app is runtime-verified: 17 libraries, 130 functions, crashers flagged inline.

Use the `serotonin-ref` MCP tools for API questions:

| Tool | Use when |
|---|---|
| `mcp__serotonin-ref__list_functions` | Explore what functions a library has before looking anything up — start here |
| `mcp__serotonin-ref__lookup` | Pull one function by dotted name while writing code (`draw.Text`, `entity.GetPlayers`) |
| `mcp__serotonin-ref__get_function` | Same as lookup with separate `library`/`name` params |
| `mcp__serotonin-ref__search_pages` | Keyword search when you don't know which library a concept lives in |
| `mcp__serotonin-ref__read_page` | Pull a full page — only when you need all prose and examples |
| `mcp__serotonin-ref__list_pages` | Browse the full page inventory |

**Preferred workflow:** `list_functions(library)` → `lookup(library.Function)`. Avoid `read_page` unless you need the full prose — it's much larger than a `lookup` result.

**Resolution order for API questions:** `serotonin-ref` MCP → `.globals/environment.d.luau` (type stubs, least reliable). Where these disagree with observed runtime behavior, runtime wins.

**Docs before agent — always.** When wondering whether a Serotonin API feature exists (a utility function, a file method, a draw call, anything), search `serotonin-docs` first. Do not reach for the `eval` tool to probe what's available — the agent doesn't know Serotonin's Lua API shape and probing it is slow and unreliable for capability discovery. Only use the agent to verify *runtime behavior* of something the docs already describe, or to inspect live game state. Example failure mode: spending multiple eval round-trips discovering `os.date`/`DateTime` are unavailable, when `utility.GetSystemTime()` and `utility.GetTimestamp()` were in the docs the whole time.

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
- `ui.getValue` on dropdowns returns **0-based** index — `0` = first item, `1` = second item, etc. Use `options[idx + 1]` to index into a Lua table.
- `ui.setValue` on dropdowns is **0-based** — pass `0` for the first item, `1` for the second, etc.
- `ui.newDropdown` 5th arg (default) is also **0-based**. All three (getValue, setValue, 5th arg default) are consistently 0-based. (Previously documented as 1-based — confirmed incorrect via live test; 1-based conversion broke dropdown logic in production.)
- `ui.setValue` works at top-level after widget creation for setting defaults. For sliders, when the type stub flags the 6th arg (default) of `newSliderFloat` as a mismatch, omit the 6th arg and set the default via `ui.setValue` instead — runtime accepts it either way.
- `loadstring(str)()` works for dynamic code execution
- **`ui.NewColorpicker` full signature is `(tab, container, label, defaultColor, inLine)`** — the 4th arg is the default color as `{r=, g=, b=, a=}` and the 5th arg is `true` for inline. Confirmed in `blue_lock_rivals.lua` and `localplayer_esp.lua`: `ui.NewColorpicker(TAB, CON, "Box Color", {r=255, g=80, b=80, a=255}, true)`. Passing only 3 args creates the picker without a default or inline. Passing `{inLine=true}` or bare `true` as the 4th arg does NOT produce inline — the correct form puts the default color 4th and `true` 5th. Attaches inline to the **immediately preceding widget in declaration order** — declare each colorpicker directly after its paired widget, not at the end of the block.
- **Checkbox + colorpicker pairs are lumped**: any checkbox (or dropdown) that gates a visual element is immediately followed by its colorpicker with `inLine=true`. This is the standard layout across Serotonin scripts and is how users expect the UI to read — do not group all pickers at the bottom.
- **Multiple colorpickers can be chained inline**: you can place as many `inLine=true` colorpickers in a row as needed — each attaches inline after the previous widget. Use this when a feature naturally has multiple related colors (e.g. a gradient's high and low colors both sit under their parent checkbox). Group pickers by what they control, not by widget type.
- **Each checkbox owns its colorpicker**: a checkbox that has an associated color is declared as `{checkbox} {colorpicker inline}`, and any sub-checkbox (e.g. a fill toggle) follows as `{sub-checkbox} {its own colorpicker inline}`. The inline colorpicker's visibility always matches its own checkbox's visibility — never gated further on whether the checkbox is checked. Other controls (sliders, dropdowns, text toggles) come after the color-bearing rows.
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
- **When a master Enable checkbox is off, every sub-widget in its container must be hidden.** This includes the hotkey, all sliders, nested checkboxes, and colorpickers. Set their initial visibility to `false` at script load via `ui.SetVisibility`, then show them in the dedicated visibility `onUpdate` only when the master checkbox is true. Nested conditions (e.g. a sub-checkbox revealing a slider) are chained on top: `local sub_on = enabled and ui.getValue(tab, con, "Sub Feature")`. Example:
  ```lua
  -- at load
  ui.SetVisibility(tab, con, "Hotkey",    false)
  ui.SetVisibility(tab, con, "Slider",    false)
  ui.SetVisibility(tab, con, "Sub Check", false)
  ui.SetVisibility(tab, con, "Sub Slider",false)
  -- visibility onUpdate
  cheat.register("onUpdate", function()
      local on     = ui.getValue(tab, con, "Enable")
      local sub_on = on and ui.getValue(tab, con, "Sub Check")
      ui.SetVisibility(tab, con, "Hotkey",     on)
      ui.SetVisibility(tab, con, "Slider",     on)
      ui.SetVisibility(tab, con, "Sub Check",  on)
      ui.SetVisibility(tab, con, "Sub Slider", sub_on)
  end)
  ```
- **Widget visibility must be driven by checkbox/dropdown values, never hotkey hold state.** A hotkey's `getValue` returns `true` only while the key is physically held — wiring `SetVisibility` to it causes the widget to flicker in and out every ~5ms. Use a `NewCheckbox` as the visibility gate; the hotkey (if needed) is a separate widget for triggering the action.
- **Visibility updates belong in a dedicated `onUpdate`, separate from game logic.** One callback reads all toggle values and calls `SetVisibility`; another handles the actual feature. This matches the `blue_lock_rivals.lua` pattern and keeps the two concerns from interfering.
- **Always use the string-triple `(tab, container, "Label")` form for `getValue` and `SetVisibility` when managing visibility.** Numeric refs work for reading widget state in game logic, but visibility management reads the same widgets from a different callback — string-triple is unambiguous and matches how BLR is written. Example:
  ```lua
  -- dedicated visibility callback
  cheat.register("onUpdate", function()
      local variance_on = ui.getValue(tab, con, "Perfect Chance")
      ui.SetVisibility(tab, con, "Variance (ms)", variance_on)
  end)
  ```
- **Tab and container IDs must be opaque keys, never the same as their display labels.** `ui.newTab(id, label)` and `ui.newContainer(tab, id, label, opts)` take a separate internal ID and a display label. Using the same string for both causes the Serotonin UI to render the tab twice. Use a short script-prefixed key as the ID and pass the human-readable name as the label:
  ```lua
  local TAB  = "myscript_tab"
  local CON  = "myscript_main"
  local CON2 = "myscript_info"

  ui.newTab(TAB, "My Script")
  ui.newContainer(TAB, CON,  "Settings", {autosize = true})
  ui.newContainer(TAB, CON2, "Info",     {autosize = true, next = true})
  ```
  This is the primary pattern used across all scripts. IDs are stable internal handles; labels are what the user sees.
- **Containers use `next = true` for side-by-side layout**: colorpickers inline on a checkbox (`inLine=true`) still work fine, but a full-width container still feels cramped. Pair your main settings container with a secondary "Info"/"Status" container using `next = true` so the tab isn't one giant column.
- **`autosize = true` sizes the container to fit its contents.** Pass it in the options table: `ui.newContainer(tab, con, "Label", { autosize = true })`. Combine with `next = true` for a side-by-side autosize layout: `{ autosize = true, next = true }`.

## Dynamic Game Data

Scripts run across varied contexts: different server instances of the same game (different players, match state, positions), or entirely different Roblox games if the script is universal. **Never hardcode or assume in-game state** — always query dynamically at runtime.

**Universal scripts** must degrade gracefully when expected instances are absent. Guard every lookup with `FindFirstChild` and `pcall`. **Game-specific scripts** still query state at runtime — even within one game, instance names, folder structure, and values differ between servers and match states.

- Player team: `pcall(function() player_team = tostring(lp.Team) end)` — returns the live team name as a string ("Home", "Away", etc.)
- Target goal: iterate `Goals:GetChildren()` and find the `Part`/`MeshPart` whose `.Name == player_team` — goals are named after the team that scores into them, so match the player's team name directly. Do not hardcode "Home"/"Away" string comparisons.
- Instance children: use `:FindFirstChild()` or `:GetChildren()` on live instances each time, not cached name assumptions
- Use `dump_workspace` + `grep_dump`, or `inspect`, to verify actual instance names before writing any game-specific lookup

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

- Nil-check before accessing nested properties (`.Character`, `:FindFirstChild()`)
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
- **One workspace lookup per player per frame, not per operation.** `game.Workspace:FindFirstChild(name)` inside `onPaint` is cheap in isolation but becomes a significant frame-time sink when called per-bone in a skeleton loop across many players (e.g. 10 bones × 2 per pair × 16 players × 60fps). Look up the character once at the top of the player loop and pass it to all helpers that need it. Enemies can skip the lookup entirely since the entity cache covers them — only non-enemies need the workspace path.
- **Entity cache covers enemies; workspace covers teammates.** For any feature that must handle both, the fast path is: try entity first (`p:GetBonePosition`, `p.BoundingBox`), fall back to workspace only when entity returns a zero-vector or empty table. Gate the workspace lookup on `not p.IsEnemy` so enemies never pay the cost.
