local C = require("zhanfx.constants")
local UE = require("zhanfx.ue")
local Core = require("zhanfx.core")
local Presenter = require("zhanfx.presenter")
local Adapter = require("zhanfx.adapter")
local Notice = require("zhanfx.notice")
local I18n = require("zhanfx.i18n")
local Runtime = {}
Runtime.__index = Runtime

local function format_fields(fields)
    local keys, out = {}, {}
    for key in pairs(fields or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do out[#out + 1] = key .. "=" .. string.format("%q", tostring(fields[key])) end
    return table.concat(out, " ")
end

function Runtime.new(config)
    local self = setmetatable({ config = config, native_hooks = {}, blueprint_hooks = {}, caps = {},
        stopped = false, now = nil, context = nil, pc_record = nil, trace = false,
        ui_requested = false, errors = {}, hook_retry = 0, probe_world = nil }, Runtime)
    local function log(event, fields) self:log(event, fields) end
    self.notice = Notice.new(log)
    self.presenter = Presenter.new({ draw = function() return self:draw() end,
        visible = function() return self:visible() end, log = log })
    self.core = Core.new({ config = config, log = log, emit = function(s)
        if not self:ready() then return "hooks_not_ready" end
        return self.presenter:request(self.now, s.kind, false)
    end })
    self.adapter = Adapter.new({ core = self.core, config = config, log = log })
    return self
end
function Runtime:log(event, fields)
    local noisy = event == "damage" or event == "finish_broadcast_observed" or event == "target_rejected"
        or event == "execution_event_observed" or event == "execution_damage_probe"
        or event == "execution_damage_scope" or event == "execution_death_scope"
        or event == "take_damage_source"
        or event == "execution_damage_result"
    if noisy and not (self.trace or self.config.DebugLogging) then return end
    print("[ZhanFX] " .. event .. " t=" .. tostring(self.now or "none") .. " " .. format_fields(fields) .. "\n")
end
function Runtime:guard(label, callback)
    if self.stopped or not self.config.Enabled then return end
    local ok, err = pcall(callback)
    if not ok and not self.errors[label] then
        self.errors[label] = true; self:log("callback_error", { hook = label, error = tostring(err) })
        self.presenter:disarm()
        self.adapter.damage_stack = {}
        self.manual_probe = true
    end
end
function Runtime:hook(label, path, callback, blueprint, after)
    local hooks = blueprint and self.blueprint_hooks or self.native_hooks
    if hooks[label] then return true end
    if not UE.find(path) then return false end
    local function wrap(handler) return function(...)
        local args = table.pack(...)
        local prior_context, prior_adapter, prior_epoch = self.context, self.adapter.context, self.core.epoch
        self:guard(label, function()
            if not self:refresh_clock() then return end
            handler(table.unpack(args, 1, args.n))
        end)
        if prior_epoch == self.core.epoch then
            self.context = prior_context; self.adapter:set_context(prior_adapter)
        else
            self.context = self.context and { key = self.context.key } or nil
            self.adapter:set_context(nil)
        end
        -- Never forward a callback's return value to UE4SS: that would override gameplay results.
    end end
    local ok, pre, post
    -- Native callback slot 2 is PRE. Blueprint slot 2 is POST; slot 3 is ignored for Blueprints.
    ok, pre, post = pcall(RegisterHook, path, wrap(callback), after and wrap(after) or nil)
    if not ok or type(pre) ~= "number" or type(post) ~= "number" then return false end
    hooks[label] = { path = path, pre = pre, post = post }
    self.caps[label] = true
    self:log("hook_ready", { hook = label, path = path })
    return true
end
function Runtime:unbind(hooks)
    for label, h in pairs(hooks) do
        pcall(UnregisterHook, h.path, h.pre, h.post)
        hooks[label], self.caps[label] = nil, nil
    end
end
function Runtime:reset(reason)
    self.core:reset(reason); self.adapter:reset(); self.presenter:reset()
    self.notice:clear()
    self.errors = {}
    self:log("probe_required", { reason = reason })
end
function Runtime:local_context()
    local pc = UE.resolve(self.pc_record)
    if not pc and type(FindAllOf) == "function" then
        local ok, controllers = pcall(FindAllOf, "PlayerController")
        if ok and controllers then
            for _, candidate in ipairs(controllers) do
                if UE.call(candidate, "IsLocalController") == true then pc = candidate; break end
            end
        end
        self.pc_record = UE.record(pc)
    end
    if not pc or UE.call(pc, "IsLocalController") ~= true then return nil end
    local player = UE.field(pc, "Pawn")
    local player_record = UE.record(player)
    local world_record = UE.record(UE.call(pc, "GetWorld"))
    if not player_record or not world_record then return nil end
    local statics = UE.find("/Script/Engine.Default__GameplayStatics")
    local now = UE.call(statics, "GetTimeSeconds", player)
    if type(now) ~= "number" then return nil end
    return { player = player, player_record = player_record, controller = pc,
        world = world_record, key = world_record.id .. "|" .. player_record.id, time = now }
end
function Runtime:refresh_clock()
    local context = self:local_context()
    if not context then
        if self.context then self:reset("world_or_pawn_missing") end
        self.context = nil; self.now = nil; self.adapter:set_context(nil)
        self.core:clock(nil, nil); return false
    end
    local changed = not self.context or self.context.key ~= context.key or (self.now and context.time < self.now)
    if changed then
        self:reset("world_pawn_or_clock_changed")
        self.hook_retry = 0
    end
    self.context, self.now = context, context.time
    self.core:clock(context.key, context.time)
    self.adapter:set_context(context)
    -- Never retain these UObject wrappers across callbacks; tick clears context after work.
    local dead, reason = UE.has_tag(context.player, "CharacterState.Dead")
    local blocked = dead == true and "local_player_dead" or (dead == nil and reason or nil)
    if blocked ~= self.state_blocked then
        self.state_blocked = blocked
        self:log(blocked and "player_state_blocked" or "player_state_ready", { reason = blocked })
    end
    if dead ~= false then
        if next(self.core.sessions) or next(self.presenter.armed) then self:reset("local_player_dead_or_state_unknown") end
        return false
    end
    return true
end
function Runtime:ready()
    if not self.context or self.stopped or not self.config.Enabled then return false end
    if next(self.errors) then return false end
    for _, label in ipairs({ "timeline", "damage", "take_damage", "death", "end_combat", "white_on", "white_off", "red_on", "red_off", "push" }) do
        if not self.caps[label] then return false end
    end
    return true
end
function Runtime:visible()
    if type(FindAllOf) ~= "function" then return nil end
    for _, name in ipairs({ "W_BossDead_C", "W_BossDead_Red_C" }) do
        local ok, instances = pcall(FindAllOf, name)
        if not ok then return nil end
        for _, widget in ipairs(instances or {}) do
            if UE.valid(widget) then
                local activated = UE.call(widget, "IsActivated")
                if type(activated) ~= "boolean" then return nil end
                if activated then return true end
            end
        end
    end
    return false
end
function Runtime:draw()
    if not self:ready() then return false end
    local class = UE.find(C.HelperClass)
    local fn = UE.find(C.HelperFunction)
    local cdo = UE.call(class, "GetCDO")
    if not UE.valid(cdo) or not fn then return false end
    self.own_push_depth = (self.own_push_depth or 0) + 1
    local ok, err = pcall(function() cdo:CallFunction(fn, false, self.context.player) end)
    self.own_push_depth = self.own_push_depth - 1
    if not ok then self:log("ui_call_failed", { error = tostring(err) }); return false end
    return true
end
function Runtime:bootstrap()
    self:hook("take_damage", "/Script/SGameAttributes.AttributeComponent:TakeDamage",
        function(component, source) self.adapter:take_damage_begin(component, source) end, false,
        function(component) self.adapter:take_damage_end(component); self:flush_ready() end)
    self:hook("execution_damage_probe", "/Script/SGameCombatSystem.BulletAttackModule:DealDamageToAvatar",
        function(module, target) self.adapter:execution_damage_begin(module, target) end, false,
        function(module, target) self.adapter:execution_damage_end(module, target); self:flush_ready() end)
    self:hook("timeline", "/Script/LegoAbility.LegoAbility:PlayTimeline", function(ctx) self.adapter:start(ctx) end)
    self:hook("damage", "/Script/GameplayAbilities.AbilitySystemBlueprintLibrary:SendGameplayEventToActor",
        function(_, actor, tag, data) self.adapter:gameplay_event(actor, tag, data) end)
    -- Load only small, known base classes; never instantiate widgets or scan all actors.
    for _, path in ipairs({ C.CombatBase, C.SimpleBase, C.DeathClass, C.HelperClass, C.Widgets[1], C.Widgets[2] }) do UE.load(path) end
    self:hook("end_combat", C.CombatBase .. ":K2_OnEndAbility", function(ctx, cancelled) self.adapter:finish(ctx, cancelled) end, true)
    self:hook("end_simple", C.SimpleBase .. ":K2_OnEndAbility", function(ctx, cancelled) self.adapter:finish(ctx, cancelled) end, true)
    self:hook("death", C.DeathClass .. ":On Death", function(ctx)
        self.adapter:death(ctx)
        self:flush_ready()
    end, true)
    self:hook("push", C.HelperFunction, function(_, red)
        local own = (self.own_push_depth or 0) > 0
        if not own then self.presenter:original_request(self.now) end
        self:log("ui_push", { red = UE.unwrap(red), origin = own and "mod_or_preview" or "original" })
    end, true)
    for i, path in ipairs(C.Widgets) do
        local label = i == 1 and "white" or "red"
        self:hook(label .. "_on", path .. ":BP_OnActivated", function(ctx)
            local record = UE.record(UE.unwrap(ctx))
            if record then self.presenter:activate(record.id, self.now) end
        end, true)
        self:hook(label .. "_off", path .. ":BP_OnDeactivated", function(ctx)
            local record = UE.record(UE.unwrap(ctx))
            if record then self.presenter:deactivate(record.id) end
        end, true)
    end
end
function Runtime:flush_ready()
    self.core:tick(function(session) return self.adapter:validate(session) end)
end
function Runtime:try_auto_arm()
    if self.config.AutoEnableCombat ~= true or self.manual_probe or
        not self.config.Categories.combat or not self:ready() then return end
    if not self.presenter.armed.combat then
        self.presenter.armed.combat = true
        self:log("auto_armed", { kind = "combat", reason = "combat_enabled_and_ready" })
    end
end
function Runtime:tick()
    if self.stopped then return end
    self.notice:tick() -- OFF feedback must still expire while combat processing is disabled.
    self:guard("tick", function()
        if not self:refresh_clock() then return end
        if self.hook_retry <= self.now then self:bootstrap(); self.hook_retry = self.now + 1 end
        self:try_auto_arm()
        self:flush_ready()
        self.adapter:prune()
    end)
    self.context = self.context and { key = self.context.key } or nil
    self.adapter:set_context(nil) -- all UE object references are callback-local
end
function Runtime:inspect_damage()
    -- Enumerate only these known reflection classes, never actors or asset contents.
    local paths = { "/Script/SGameAttributes.AttributeUtils", "/Script/SGameAttributes.DamageCalculatorBase",
        "/Script/SGameAttributes.DamageTakenPayload", "/Script/SGameCombatSystem.BulletAttackModule",
        "/Script/SGameCombatSystem.BulletInterfaceBP", "/Script/SGameAttributes.DamagePreTakePayload",
        "/Script/SGameAttributes.AT_WaitReceiveDamage", "/Script/ProjectPBZ.AT_WaitReceiveDamage",
        "/Script/SGameAttributes.AttributeComponent", "/Script/SGameAttributes.DamageSourceInterface" }
    for _, path in ipairs(paths) do
        local class, count = UE.find(path), 0
        local ok, err = pcall(function()
            if not class then return end
            class:ForEachFunction(function(fn)
                local name = UE.call(fn, "GetFullName") or "unknown"
                if name:find("Damage") or name:find("Source") or name:find("Attack") or
                    name:find("Death") or name:find("Take") or name:find("Apply") then
                    count = count + 1
                    if count > 48 then return true end
                    local fields = {}
                    pcall(function() fn:ForEachProperty(function(property)
                        if #fields >= 24 then return true end
                        fields[#fields + 1] = UE.call(UE.call(property, "GetFName"), "ToString")
                            or UE.call(property, "GetFullName") or "unknown"
                    end) end)
                    self:log("damage_reflection", { function_path = name, fields = table.concat(fields, ",") })
                end
            end)
        end)
        self:log("damage_reflection_class", { path = path, found = class ~= nil, count = count,
            error = not ok and tostring(err) or nil })
    end
end
function Runtime:show_notice(context, key)
    local text, language, requested, reason, return_type = I18n.text(key, self.config.Language)
    self:log("notice_language", { language = language, requested = requested, reason = reason, return_type = return_type })
    self.notice:show(context, text)
end

function Runtime:command(params)
    if self.stopped then return false end
    local verb, kind = params[1] or "status", params[2] or "combat"
    if verb == "toggle" then
        local context = self:local_context()
        if not context then self:log("toggle_unavailable", { reason = "no_local_player" }); return true end
        if self.config.Enabled then
            self:command({"off"})
            self:show_notice(context, "disabled")
        else
            self.manual_probe = false
            self.config.Enabled = true
            self.config.AutoEnableCombat = true
            if self:refresh_clock() then self:bootstrap(); self:try_auto_arm() end
            self:show_notice(context, "enabled")
            self:log("enabled", { input = "Alt+F8" })
        end
        return true
    end
    if verb == "reload" then
        if type(RestartCurrentMod) ~= "function" then
            self:log("reload_unavailable", {}); return true
        end
        self:log("reload_requested", {})
        self:shutdown()
        RestartCurrentMod()
        return true
    end
    if verb == "off" then
        self.manual_probe = true
        self.config.Enabled = false; self:reset("command_disabled"); self:log("disabled", {}); return true
    end
    if verb == "on" then self.manual_probe = false; self.config.Enabled = true; self:log("probe_mode", {}); return true end
    if verb == "disarm" then self.manual_probe = true; self.presenter:disarm(); self:log("probe_mode", {}); return true end
    if verb == "status" then
        local missing = {}
        for _, name in ipairs({ "timeline", "damage", "take_damage", "death", "end_combat", "white_on", "white_off", "red_on", "red_off", "push" }) do
            if not self.caps[name] then missing[#missing + 1] = name end
        end
        self:log("status", { version = C.Version, enabled = self.config.Enabled, ready = self:ready(),
            armed = format_fields(self.presenter.armed), eligible = self.core.stats.eligible,
            displayed = self.presenter.stats.shown, merged = self.presenter.stats.merged,
            missing_hooks = table.concat(missing, ","), state_blocked = self.state_blocked }); return true
    end
    if not self.config.Enabled or not self:refresh_clock() then self:log("not_in_live_world", {}); return true end
    if verb == "inspect" then self:inspect_damage(); return true end
    if verb == "probe" then
        if self.config.Categories[kind] == nil then self:log("unsupported_category", { kind = kind }); return true end
        self.manual_probe = true
        self:reset("probe_category"); self.config.Categories[kind] = true; self.trace = true
        self:log("probe_category", { kind = kind }); return true
    end
    if verb == "preview" then
        self:bootstrap()
        self:log("preview", { result = self.presenter:request(self.now, "combat", true) }); return true
    end
    if verb == "arm" then
        if not self.config.Categories[kind] or not self:ready() or (kind == "simple" and not self.caps.end_simple) then
            self:log("arm_refused", { reason = "category_or_hooks_not_ready", kind = kind }); return true
        end
        local ok, reason = self.presenter:arm(kind)
        self:log(ok and "armed" or "arm_refused", { kind = kind, reason = reason }); return true
    end
    self:log("usage", { commands = "status | probe combat/simple/stealth/air | preview | arm <category> | disarm | off | on" })
    return true
end
function Runtime:dispatch(params)
    if self.stopped then return false end
    local ok, handled = pcall(function() return self:command(params or {}) end)
    if not ok then self.presenter:disarm(); self:log("command_error", { error = tostring(handled) }); handled = true end
    self.context = self.context and { key = self.context.key } or nil
    self.adapter:set_context(nil)
    return handled
end
function Runtime:start()
    self:log("startup", { version = C.Version, game = C.GameBuild,
        mode = "single_key_toggle",
        combat_feedback = "confirmed_execution_death" })
    if type(LoopInGameThreadWithDelay) ~= "function" or type(RegisterHook) ~= "function" then
        self:log("unsupported_runtime", { required = "UE4SS f885e8d2 delayed actions + RegisterHook" }); return false
    end
    self.timer = LoopInGameThreadWithDelay(C.PollMs, function() self:tick() end)
    if type(RegisterConsoleCommandHandler) == "function" then
        RegisterConsoleCommandHandler("zhanfx", function(_, params)
            return self:dispatch(params)
        end)
    end
    -- Key callbacks may run off-thread. Queue only plain command strings, never UObject wrappers.
    if type(RegisterKeyBind) == "function" and type(ExecuteInGameThread) == "function" and Key and ModifierKey then
        RegisterKeyBind(Key.F8, {ModifierKey.ALT}, function()
            if not self.stopped then ExecuteInGameThread(function() self:dispatch({"toggle"}) end) end
        end)
    end
    self:log("keybinds", { toggle = "Alt+F8", extra_hotkeys = false, enabled = self.config.Enabled })
    return true
end
function Runtime:shutdown()
    self.stopped = true
    if self.timer and type(CancelDelayedAction) == "function" then pcall(CancelDelayedAction, self.timer) end
    self:unbind(self.blueprint_hooks); self:unbind(self.native_hooks)
    self:reset("shutdown"); self.context = nil; self.adapter:set_context(nil)
end
return Runtime
