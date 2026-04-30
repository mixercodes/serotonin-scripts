http.Get("https://raw.githubusercontent.com/mixercodes/serotonin-scripts/master/localplayer_esp.lua", {}, function(body)
    loadstring(body)()
end)
