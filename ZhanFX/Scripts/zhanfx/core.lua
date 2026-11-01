-- Pure Lua. No UObject, timer, filesystem, or UE4SS dependencies.
local C = require("zhanfx.constants")
local Core = {}
Core.__index = Core

function Core.new(options)
    return setmetatable({ config = options.config, emit = options.emit, log = options.log or function() end,
        sessions = {}, serial = 0, epoch = 0, context = nil, now = nil,
        stats = { started = 0, eligible = 0, rejected = 0, cancelled = 0, expired = 0 } }, Core)
end

function Core:reset(reason)
    self.sessions = {}
    self.epoch = self.epoch + 1
    self.log("reset", { reason = reason, epoch = self.epoch })
end

function Core:clock(context, now)
    if type(now) ~= "number" or now ~= now or now == math.huge or now == -math.huge or not context then
        if self.context ~= nil or next(self.sessions) then self:reset("no_world") end
        self.context = nil; self.now = nil; return false
    end
    if self.context ~= context or (self.now and now < self.now) then self:reset("context_or_clock_changed") end
    self.context, self.now = context, now
    return true
end

function Core:drop_ability(ability, reason)
    for key, s in pairs(self.sessions) do
        if s.ability == ability then
            self.sessions[key] = nil
            self.log("discard", { reason = reason, id = s.id })
        end
    end
end

function Core:start(e)
    if not self.config.Enabled or not self.context or e.executor ~= e.local_player then return false end
    self:drop_ability(e.ability, "ability_reactivated")
    if not self.config.Categories[e.kind] then return false end
    self.serial = self.serial + 1
    local added, count = false, 0
    for _ in pairs(self.sessions) do count = count + 1 end
    local seen = {}
    for _, target in ipairs(e.targets or {}) do
        if count >= C.MaxSessions then self.log("capacity", {}); break end
        if target.id and not seen[target.id] and target.id ~= e.local_player and
            target.boss == false and target.hostile == true and target.ai == true then
            seen[target.id] = true
            local id = tostring(self.epoch) .. ":" .. tostring(self.serial) .. ":" .. target.id
            self.sessions[id] = { id = id, ability = e.ability, executor = e.executor, target = target.id,
                kind = e.kind, handle = e.handle, started = self.now, epoch = self.epoch }
            self.stats.started = self.stats.started + 1
            count, added = count + 1, true
            self.log("start", { id = id, ability = e.ability, executor = e.executor,
                target = target.id, kind = e.kind, handle = e.handle })
        else
            self.stats.rejected = self.stats.rejected + 1
            self.log("target_rejected", { target = target.id, boss = target.boss, hostile = target.hostile, ai = target.ai })
        end
    end
    return added
end

function Core:damage(e)
    if not self.now then return end
    for _, s in pairs(self.sessions) do
        if s.target == e.target then
            local prior = s.damage
            s.damage = nil
            if e.taken == true and e.ability == s.ability and e.executor == s.executor then
                if e.preserve_lethal == true then
                    if prior and prior.lethal_transition then s.damage = prior end
                else
                    s.damage = { time = self.now, verified = true, lethal_transition = e.lethal_transition == true }
                end
            end
            self.log("damage", { id = s.id, source = e.ability, executor = e.executor,
                taken = e.taken, matched = s.damage ~= nil })
        end
    end
end

function Core:death(target)
    if not self.now then return end
    for _, s in pairs(self.sessions) do
        if s.target == target and not s.dead then
            s.dead = self.now
            self.log("death", { id = s.id, target = target })
        end
    end
end

function Core:finish(ability, cancelled)
    for id, s in pairs(self.sessions) do
        if s.ability == ability and not s.ended then
            if cancelled ~= false then
                self.stats.cancelled = self.stats.cancelled + 1
                self.sessions[id] = nil
                self.log("cancelled", { id = s.id, value = cancelled })
            else
                s.ended = self.now
                self.log("finished", { id = s.id })
            end
        end
    end
end

function Core:has_target(target)
    for _, s in pairs(self.sessions) do if s.target == target then return true end end
    return false
end

function Core:tick(validate)
    if not self.config.Enabled then self:reset("disabled"); return end
    if not self.now then return end
    local ready = {}
    for id, s in pairs(self.sessions) do
        if self.now - s.started > C.ActiveTTL or (s.ended and self.now - s.ended > C.EndGrace) then
            self.sessions[id] = nil; self.stats.expired = self.stats.expired + 1
            self.log("expired", { id = id })
        elseif (s.ended or (s.kind == "combat" and s.damage and s.damage.lethal_transition)) and
            s.dead and s.damage and s.damage.time >= s.started and
            (s.damage.lethal_transition or math.abs(s.damage.time - s.dead) <= C.AttributionWindow) then
            ready[#ready + 1] = s
        end
    end
    table.sort(ready, function(a, b) return a.id < b.id end)
    for _, s in ipairs(ready) do
        -- Consume BEFORE invoking display; blocked, probe-only, and failed requests never become a queue.
        self.sessions[s.id] = nil
        local ok, valid = pcall(validate, s)
        if ok and valid == true then
            self.stats.eligible = self.stats.eligible + 1
            local emitted, outcome = pcall(self.emit, s)
            self.log("eligible", { id = s.id, kind = s.kind,
                outcome = emitted and tostring(outcome) or "display_error" })
        else
            self.stats.rejected = self.stats.rejected + 1
            self.log("revalidation_failed", { id = s.id })
        end
    end
end

return Core
