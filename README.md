# serotonin-scripts

Finished Serotonin Lua scripts. Load directly in Serotonin's Scripting tab, or fetch remotely:

```lua
http.Get("https://raw.githubusercontent.com/mixercodes/serotonin-scripts/master/<script>.lua", {}, function(body)
    loadstring(body)()
end)
```

## API reference

- https://serotonin-ref.vercel.app — runtime-verified, 14 libraries + 5 userdata types
