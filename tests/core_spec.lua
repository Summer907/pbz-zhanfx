local Core = require("zhanfx.core")
local Presenter = require("zhanfx.presenter")
local C = require("zhanfx.constants")
local cases, passed = {}, 0
local function test(name, fn) cases[#cases + 1] = { name, fn } end
local function eq(actual, expected) assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected)) end
local function fixture()
    local f = { shown = 0, cfg = { Enabled = true, Categories = { combat = true, simple = true, stealth = true, air = true } } }
    f.core = Core.new({ config = f.cfg, emit = function() f.shown = f.shown + 1; return "shown" end })
    f.core:clock("world:player", 1)
    function f:start(overrides)
        local event = { ability = "ability", executor = "player", local_player = "player", kind = "combat",
            targets = { { id = "enemy", boss = false, hostile = true, ai = true } } }
        for k, v in pairs(overrides or {}) do event[k] = v end
        return self.core:start(event)
    end
    function f:damage(overrides)
        local event = { target = "enemy", ability = "ability", executor = "player", taken = true }
        for k, v in pairs(overrides or {}) do event[k] = v end
        self.core:damage(event)
    end
    function f:tick(time, valid)
        self.core:clock("world:player", time or 1.05)
        self.core:tick(function() return valid ~= false end)
    end
    function f:complete() self:damage(); self.core:death("enemy"); self.core:finish("ability", false) end
    return f
end

test("death before normal end", function() local f=fixture(); f:start(); f:complete(); f:tick(); eq(f.shown,1) end)
test("end before death", function() local f=fixture(); f:start(); f.core:finish("ability",false); f.core:clock("world:player",1.2); f:damage(); f.core:death("enemy"); f:tick(1.25); eq(f.shown,1) end)
test("Taken notification after death in same frame", function() local f=fixture(); f:start(); f.core:death("enemy"); f:damage(); f.core:finish("ability",false); f:tick(); eq(f.shown,1) end)
test("never display just for normal end", function() local f=fixture(); f:start(); f:damage(); f.core:finish("ability",false); f:tick(); eq(f.shown,0) end)
test("never display just for death", function() local f=fixture(); f:start(); f:damage(); f.core:death("enemy"); f:tick(); eq(f.shown,0) end)
test("missing attribution blocks", function() local f=fixture(); f:start(); f.core:death("enemy"); f.core:finish("ability",false); f:tick(); eq(f.shown,0) end)
test("cancelled kill blocks", function() local f=fixture(); f:start(); f:damage(); f.core:death("enemy"); f.core:finish("ability",true); f:tick(); eq(f.shown,0) end)
test("unknown cancellation blocks", function() local f=fixture(); f:start(); f:damage(); f.core:death("enemy"); f.core:finish("ability",nil); f:tick(); eq(f.shown,0) end)
test("foreign ability cannot attribute", function() local f=fixture(); f:start(); f:damage({ability="other"}); f.core:death("enemy"); f.core:finish("ability",false); f:tick(); eq(f.shown,0) end)
test("foreign executor cannot attribute", function() local f=fixture(); f:start(); f:damage({executor="ally"}); f.core:death("enemy"); f.core:finish("ability",false); f:tick(); eq(f.shown,0) end)
test("unknown incoming hit invalidates prior hit", function() local f=fixture(); f:start(); f:damage(); f.core:damage({target="enemy",taken=false}); f.core:death("enemy"); f.core:finish("ability",false); f:tick(); eq(f.shown,0) end)
test("Pretake alone is not damage taken", function() local f=fixture(); f:start(); f:damage({taken=false}); f.core:death("enemy"); f.core:finish("ability",false); f:tick(); eq(f.shown,0) end)
test("old nonlethal damage expires attribution", function() local f=fixture(); f:start(); f:damage(); f.core:clock("world:player",1.5); f.core:death("enemy"); f.core:finish("ability",false); f:tick(1.55); eq(f.shown,0) end)
test("end grace expiry cannot trigger later", function() local f=fixture(); f:start(); f.core:finish("ability",false); f.core:clock("world:player",1+C.EndGrace+0.1); f:damage(); f.core:death("enemy"); f:tick(2.2); eq(f.shown,0) end)
test("uncompleted sessions expire", function() local f=fixture(); f:start(); f:tick(1+C.ActiveTTL+1); eq(next(f.core.sessions),nil) end)
test("world change clears pending", function() local f=fixture(); f:start(); f:complete(); f.core:clock("new-world:player",1); f.core:tick(function() return true end); eq(f.shown,0) end)
test("pawn change clears pending", function() local f=fixture(); f:start(); f:complete(); f.core:clock("world:new-player",1); f.core:tick(function() return true end); eq(f.shown,0) end)
test("backwards game clock clears pending", function() local f=fixture(); f:start(); f:complete(); f:tick(0.5); eq(f.shown,0) end)
test("paused game clock does not age sessions", function() local f=fixture(); f:start(); for _=1,100 do f:tick(1) end; assert(next(f.core.sessions)); f:complete(); f:tick(1); eq(f.shown,1) end)
test("missing world discards pending", function() local f=fixture(); f:start(); f:complete(); f.core:clock(nil,nil); eq(next(f.core.sessions),nil) end)
test("no-world polling does not reset every tick", function() local f=fixture(); f.core:clock(nil,nil); local n=f.core.epoch; for _=1,10 do f.core:clock(nil,nil) end; eq(f.core.epoch,n) end)
test("NaN clock rejected", function() local f=fixture(); eq(f.core:clock("x",0/0),false) end)
test("infinite clock rejected", function() local f=fixture(); eq(f.core:clock("x",math.huge),false) end)
test("Boss excluded", function() local f=fixture(); eq(f:start({targets={{id="boss",boss=true,hostile=true,ai=true}}}),false) end)
test("unknown Boss classification excluded", function() local f=fixture(); eq(f:start({targets={{id="x",hostile=true,ai=true}}}),false) end)
test("friendly excluded", function() local f=fixture(); eq(f:start({targets={{id="x",boss=false,hostile=false,ai=true}}}),false) end)
test("unknown faction excluded", function() local f=fixture(); eq(f:start({targets={{id="x",boss=false,ai=true}}}),false) end)
test("non-AI excluded", function() local f=fixture(); eq(f:start({targets={{id="x",boss=false,hostile=true,ai=false}}}),false) end)
test("self excluded", function() local f=fixture(); eq(f:start({targets={{id="player",boss=false,hostile=true,ai=true}}}),false) end)
test("nonlocal executor excluded", function() local f=fixture(); eq(f:start({executor="other"}),false) end)
test("disabled category excluded", function() local f=fixture(); f.cfg.Categories.simple=false; eq(f:start({kind="simple"}),false) end)
test("duplicate target snapshots deduplicated", function() local f=fixture(); local t={id="enemy",boss=false,hostile=true,ai=true}; f:start({targets={t,t}}); eq(f.core.stats.started,1) end)
test("duplicate death/end callbacks display once", function() local f=fixture(); f:start(); f:complete(); f:complete(); f:tick(); f:complete(); f:tick(1.1); eq(f.shown,1) end)
test("ability reactivation invalidates old death", function() local f=fixture(); f:start(); f:complete(); f:start(); f.core:finish("ability",false); f:tick(); eq(f.shown,0) end)
test("revalidate target still dead", function() local f=fixture(); f:start(); f:complete(); f:tick(1.05,false); eq(f.shown,0) end)
test("invalid object revalidation errors cannot display", function() local f=fixture(); f:start(); f:complete(); f.core:tick(function() error("GC") end); eq(f.shown,0) end)
test("display errors consumed without retry", function() local f=fixture(); f.core.emit=function() error("UI") end; f:start(); f:complete(); f:tick(); eq(next(f.core.sessions),nil) end)
test("disabling discards existing success", function() local f=fixture(); f:start(); f:complete(); f.cfg.Enabled=false; f:tick(); eq(f.shown,0); eq(next(f.core.sessions),nil) end)
test("multi-target only attributed death displays", function() local f=fixture(); f:start({kind="simple",targets={{id="enemy",boss=false,hostile=true,ai=true},{id="rear",boss=false,hostile=true,ai=true}}}); f:complete(); f.core:death("rear"); f:tick(); eq(f.shown,1) end)
test("bounded session capacity", function() local f=fixture(); for i=1,100 do f:start({ability="a"..i}) end; local n=0;for _ in pairs(f.core.sessions) do n=n+1 end;eq(n,C.MaxSessions) end)

local function ui_fixture()
    local f={calls=0,visible=false}
    f.ui=Presenter.new({visible=function() return f.visible end,draw=function() f.calls=f.calls+1;return true end})
    return f
end
test("UI defaults to probe only", function() local f=ui_fixture(); eq(f.ui:request(1,"combat",false),"probe_only");eq(f.calls,0) end)
test("arming requires actual preview lifecycle", function() local f=ui_fixture();f.ui:request(1,"combat",false);eq(f.ui:arm("combat"),false) end)
test("arming also requires eligible sample", function() local f=ui_fixture();f.ui:request(1,"combat",true);f.ui:activate("w");f.ui:deactivate("w");eq(f.ui:arm("combat"),false) end)
test("preview and sample permit current-world arm", function() local f=ui_fixture();f.ui:request(1,"combat",false);f.ui:request(1,"combat",true);f.ui:activate("w");f.ui:deactivate("w");eq(f.ui:arm("combat"),true) end)
test("original effect blocks new display", function() local f=ui_fixture();f.ui.armed.combat=true;f.ui:activate("boss");eq(f.ui:request(1,"combat",false),"merged");eq(f.calls,0) end)
test("visible instance catches missed activation", function() local f=ui_fixture();f.ui.armed.combat=true;f.visible=true;eq(f.ui:request(1,"combat",false),"merged") end)
test("unknown visibility blocks display", function() local f=ui_fixture();f.ui.armed.combat=true;f.ui.visible=function() return nil end;eq(f.ui:request(1,"combat",false),"visibility_unknown");eq(f.calls,0) end)
test("visibility query failure blocks display", function() local f=ui_fixture();f.ui.armed.combat=true;f.ui.visible=function() error("GC") end;eq(f.ui:request(1,"combat",false),"visibility_unknown") end)
test("continuous kills merge without extending reservation", function() local f=ui_fixture();f.ui.armed.combat=true;eq(f.ui:request(1,"combat",false),"shown");local t=f.ui.reserved_until;eq(f.ui:request(2,"combat",false),"merged");eq(f.ui.reserved_until,t);eq(f.calls,1) end)
test("merged kills never queue", function() local f=ui_fixture();f.ui.armed.combat=true;f.ui:request(1,"combat",false);f.ui:activate("w");f.ui:request(2,"combat",false);f.ui:deactivate("w");eq(f.calls,1);eq(f.ui:request(5,"combat",false),"shown");eq(f.calls,2) end)
test("failed invocation does not retry automatically", function() local f=ui_fixture();f.ui.armed.combat=true;f.ui.draw=function() error("call") end;eq(f.ui:request(1,"combat",false),"draw_failed");eq(f.ui:request(1.1,"combat",false),"merged") end)
test("world reset disarms and invalidates preview evidence", function() local f=ui_fixture();f.ui.armed.combat=true;f.ui.preview_seen=true;f.ui.preview_closed=true;f.ui:reset();eq(next(f.ui.armed),nil);eq(f.ui.preview_seen,false) end)
test("disarm leaves original UI state untouched", function() local f=ui_fixture();f.ui:activate("boss");f.ui.armed.combat=true;f.ui:disarm();eq(f.ui.active.boss,"original") end)
test("synchronous original push does not add a post-exit dead period",function()
    local f=ui_fixture();f.ui.armed.combat=true;f.ui:activate("boss",1);f.ui:original_request(1);f.ui:deactivate("boss");eq(f.ui:request(3.6,"combat",false),"shown")
end)

local results={}
for _,case in ipairs(cases) do
    local ok,err=pcall(case[2]);results[#results+1]={name=case[1],passed=ok,error=ok and nil or tostring(err)}
    if ok then passed=passed+1 end
end
return { suite="behavior",passed=passed,total=#cases,results=results }
