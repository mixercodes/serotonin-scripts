# serotonin-scripts

Finished Serotonin Lua scripts. Load directly in Serotonin's Scripting tab, or fetch remotely:

```lua
http.Get("https://raw.githubusercontent.com/mixercodes/serotonin-scripts/master/<script>.lua", {}, function(body)
    loadstring(body)()
end)
```

## Projects

- [stream-radar/](stream-radar/) — 3D web radar: `stream.lua` streams the live world over file IPC
  to an Electron + Three.js viewer — oriented map geometry, real meshes/textures, R6/R15 player
  skeletons, optional browser/LAN hosting. Multi-file; see its
  [installation guide](stream-radar/INSTALL.md).

## API reference

- https://serotonin-ref.vercel.app — runtime-verified, 14 libraries + 5 userdata types
