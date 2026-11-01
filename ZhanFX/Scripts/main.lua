local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
    local dir = source:sub(2):match("^(.*[/\\])")
    if dir then package.path = dir .. "?.lua;" .. dir .. "?/init.lua;" .. package.path end
end
if _G.__ZhanFX then _G.__ZhanFX:shutdown() end
local app = require("zhanfx.runtime").new(require("config"))
_G.__ZhanFX = app
app:start()
