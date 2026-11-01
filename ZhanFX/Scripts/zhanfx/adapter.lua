local C = require("zhanfx.constants")
local UE = require("zhanfx.ue")
local Adapter = {}
Adapter.__index = Adapter

function Adapter.new(options)
    return setmetatable({ core = options.core, config = options.config, log = options.log,
        context = nil, actors = {}, abilities = {}, runs = {}, death_components = {},
        local_player = nil, observed_events = {}, observed_count = 0, damage_stack = {} }, Adapter)
end
function Adapter:reset()
    self.actors, self.abilities, self.runs, self.death_components = {}, {}, {}, {}
    self.observed_events, self.observed_count = {}, 0
    self.damage_stack = {}
end
function Adapter:set_context(context) self.context = context; self.local_player = context and context.player_record.id end
function Adapter:kind(ability)
    for _, kind in ipairs({ "shachi", "grab", "air", "stealth", "combat" }) do
        for _, path in ipairs(C.Classes[kind]) do
            if UE.isa(ability, path) == true then return kind end
        end
    end
    if UE.isa(ability, C.SimpleBase) == true then return "simple" end
    -- Unknown subclasses are diagnostic only; never infer from a substring in the class name.
    return nil
end
function Adapter:snapshot_target(target)
    local record = UE.record(target)
    if not record or not self.context then return nil end
    local boss = UE.has_tag(target, "CharacterType.AI.Boss")
    local shared = UE.has_tag(target, "CharacterType.AI.SharedHealthPoolMember")
    if shared ~= false then boss = shared == true and true or nil end
    local component = UE.death_component(target, C.DeathClass)
    local component_record = UE.record(component)
    if not component_record or UE.call(component, "Is Dead") ~= false then
        self.log("target_state_unknown_or_already_dead", { target = record.id }); return nil
    end
    self.actors[record.id] = record
    self.death_components[record.id] = component_record
    return { id = record.id, boss = boss, hostile = UE.hostile(target, self.context.player), ai = UE.is_ai(target) }
end
function Adapter:start(raw)
    if not self.context or not self.config.Enabled then return end
    local ability = UE.unwrap(raw)
    local ability_record = UE.record(ability)
    if not ability_record then return end
    local kind = self:kind(ability)
    if not kind or kind == "shachi" or kind == "grab" then return end
    local executor = UE.call(ability, "GetAvatarActorFromActorInfo")
    local executor_record = UE.record(executor)
    if not executor_record or executor_record.id ~= self.local_player then return end
    local info = UE.field(ability, "Execution Info")
    if kind ~= "simple" and UE.field(info, "IsTarget") ~= false then
        self.log("identity_unknown", { kind = kind, ability = ability_record.id }); return
    end
    local handle_value = UE.field(UE.field(info, "ExecutionHandle"), "Handle")
    local existing = self.runs[ability_record.id]
    if existing and existing.active and existing.handle == handle_value then return end
    local targets, seen = {}, {}
    local function add(target)
        local snapshot = self:snapshot_target(target)
        if snapshot and not seen[snapshot.id] then targets[#targets + 1] = snapshot; seen[snapshot.id] = true end
    end
    if kind == "simple" then
        add(UE.field(ability, "ExecutionTarget"))
        add(UE.field(ability, "NearestForwardEnemy"))
        add(UE.field(ability, "NearestBackwardEnemy"))
    else
        local info_executor = UE.record(UE.field(info, "Executor"))
        if not info_executor or info_executor.id ~= executor_record.id then return end
        add(UE.field(info, "Target"))
    end
    self.abilities[ability_record.id] = ability_record
    local started = self.core:start({ ability = ability_record.id, executor = executor_record.id,
        local_player = self.local_player, targets = targets, kind = kind, handle = handle_value })
    if started then self.runs[ability_record.id] = { active = true, handle = handle_value, kind = kind } end
end
function Adapter:finish(raw, raw_cancelled)
    local record = UE.record(UE.unwrap(raw))
    if not record or not self.runs[record.id] then return end
    self.core:finish(record.id, UE.unwrap(raw_cancelled))
    self.runs[record.id].active = false
end
function Adapter:death(raw)
    local component = UE.unwrap(raw)
    if UE.call(component, "Is Dead") ~= true then return end
    local target = UE.call(component, "GetOwner")
    local record = UE.record(target)
    if not record or not self.core:has_target(record.id) then return end
    local frame = self.damage_stack[#self.damage_stack]
    if frame and frame.target == record.id and frame.epoch == self.core.epoch then frame.died = true end
    self.log("execution_death_scope", { target = record.id, depth = #self.damage_stack,
        in_target_call = frame and frame.target == record.id or false })
    self.death_components[record.id] = UE.record(component)
    self.core:death(record.id)
end
function Adapter:gameplay_event(raw_actor, raw_tag, raw_data)
    local tag = UE.tag(raw_tag)
    -- Diagnose the existing entry point only. Bound output and retain plain strings only.
    local receiver = UE.record(UE.unwrap(raw_actor))
    if receiver and next(self.core.sessions) and
        (self.core:has_target(receiver.id) or receiver.id == self.local_player) then
        local key = receiver.id .. "|" .. tostring(tag)
        if not self.observed_events[key] and self.observed_count < 24 then
            self.observed_events[key] = true
            self.observed_count = self.observed_count + 1
            local data = UE.unwrap(raw_data)
            local payload = UE.record(UE.field(data, "OptionalObject"))
            local secondary = UE.record(UE.field(data, "OptionalObject2"))
            self.log("execution_event_observed", { receiver = receiver.id, tag = tag or "unreadable",
                payload = payload and payload.full, secondary = secondary and secondary.full,
                payload_tag = UE.tag(UE.field(data, "EventTag")) })
        end
    end
    if tag ~= "GameplayEvent.Damage.Pretake" and tag ~= "GameplayEvent.Damage.Taken" and
        tag ~= "GameplayEvent.Execution.Finish" then return end
    if not receiver or not self.core:has_target(receiver.id) then return end
    if tag == "GameplayEvent.Execution.Finish" then
        self.log("finish_broadcast_observed", { receiver = receiver.id }); return -- deliberately NOT success
    end
    local payload = UE.field(UE.unwrap(raw_data), "OptionalObject")
    local payload_target = UE.record(UE.field(payload, "TargetActor"))
    local source = UE.call(payload, "GetDamageSourceAbility")
    local source_record = UE.record(source)
    local source_actor = UE.record(UE.call(source, "GetAvatarActorFromActorInfo"))
    -- Unresolved / differently-addressed payloads still invalidate previous attribution.
    local verified = payload_target and payload_target.id == receiver.id
    self.core:damage({ target = receiver.id, taken = verified and tag == "GameplayEvent.Damage.Taken",
        ability = verified and source_record and source_record.id or nil,
        executor = verified and source_actor and source_actor.id or nil })
end
function Adapter:validate(session)
    if not self.context or session.executor ~= self.local_player then return false end
    local target = UE.resolve(self.actors[session.target])
    local component = UE.resolve(self.death_components[session.target])
    if not target or not component or UE.call(component, "Is Dead") ~= true then return false end
    return UE.has_tag(target, "CharacterType.AI.Boss") == false and
        UE.has_tag(target, "CharacterType.AI.SharedHealthPoolMember") == false and
        UE.hostile(target, self.context.player) == true
end
function Adapter:execution_damage_probe(raw_module, raw_target)
    local target = UE.record(UE.unwrap(raw_target))
    if not target or not self.core:has_target(target.id) then return end
    local module = UE.unwrap(raw_module)
    local bullet = UE.field(module, "Bullet")
    local source = UE.call(bullet, "GetSourceAbility")
    local source_record = UE.record(source)
    local executor = UE.record(UE.call(source, "GetAvatarActorFromActorInfo"))
    local matched = false
    for _, session in pairs(self.core.sessions) do
        if session.target == target.id and source_record and source_record.id == session.ability and
            executor and executor.id == session.executor then matched = true end
    end
    self.log("execution_damage_probe", { target = target.id, bullet = (UE.record(bullet) or {}).full,
        source = source_record and source_record.id, executor = executor and executor.id,
        matched = matched, dead_before = UE.call(UE.resolve(self.death_components[target.id]), "Is Dead") })
    -- Diagnostic evidence only: a damage attempt alone is never credited as a kill.
end
function Adapter:execution_damage_begin(raw_module, raw_target)
    local module = UE.unwrap(raw_module)
    local module_record = UE.record(module)
    local target = UE.record(UE.unwrap(raw_target))
    local frame = { module = module_record and module_record.id, target = target and target.id,
        epoch = self.core.epoch }
    for _, parent in ipairs(self.damage_stack) do
        if target and parent.target == target.id then parent.contaminated = true end
    end
    self.damage_stack[#self.damage_stack + 1] = frame
    if not target or not self.core:has_target(target.id) then return end
    self:execution_damage_probe(raw_module, raw_target)
    local bullet = UE.field(module, "Bullet")
    local execution_bullet = UE.isa(bullet, "/PBZCombatAsset/Prototypes/Bullet/Bullets/BP_PBZ_ExecutionBullet.BP_PBZ_ExecutionBullet_C")
    self.log("execution_damage_scope", { phase = "pre", target = target.id,
        execution_bullet = execution_bullet, depth = #self.damage_stack })
    if execution_bullet ~= true then self.core:damage({ target = target.id }); return end
    local source = UE.call(bullet, "GetSourceAbility")
    local source_record = UE.record(source)
    local executor = UE.record(UE.call(source, "GetAvatarActorFromActorInfo"))
    frame.ability = source_record and source_record.id
    frame.executor = executor and executor.id
    frame.alive = UE.call(UE.resolve(self.death_components[target.id]), "Is Dead") == false
    frame.health_before = UE.health(UE.unwrap(raw_target))
    self.core:damage({ target = target.id, ability = frame.ability, executor = frame.executor,
        taken = frame.alive and type(frame.health_before) == "number" and frame.health_before <= 0,
        preserve_lethal = true })
end
function Adapter:execution_damage_end(raw_module, raw_target)
    local frame = table.remove(self.damage_stack)
    local module, target = UE.record(UE.unwrap(raw_module)), UE.record(UE.unwrap(raw_target))
    if target and self.core:has_target(target.id) then
        self.log("execution_damage_scope", { phase = "post", target = target.id,
            frame_present = frame ~= nil, alive_before = frame and frame.alive,
            death_observed = frame and frame.died, depth = #self.damage_stack,
            module_matches = frame and module and frame.module == module.id,
            target_matches = frame and frame.target == target.id })
    end
    if not frame or not module or not target or frame.module ~= module.id or frame.target ~= target.id or
        frame.epoch ~= self.core.epoch then self.damage_stack = {}; return end
    local health_after = UE.health(UE.unwrap(raw_target))
    local lethal_transition = type(frame.health_before) == "number" and frame.health_before > 0 and
        type(health_after) == "number" and health_after <= 0
    self.log("execution_damage_result", { target = target.id, health_before = frame.health_before,
        health_after = health_after, lethal_transition = lethal_transition, contaminated = frame.contaminated or false })
    if not frame.alive or frame.contaminated or not frame.ability or not frame.executor then return end
    if type(frame.health_before) == "number" and frame.health_before <= 0 then
        self.core:damage({ target = target.id, ability = frame.ability, executor = frame.executor,
            taken = type(health_after) == "number" and health_after <= 0, preserve_lethal = true })
        return
    end
    if not lethal_transition and not (frame.died and UE.call(UE.resolve(self.death_components[target.id]), "Is Dead") == true) then return end
    self.core:damage({ target = target.id, taken = true, ability = frame.ability, executor = frame.executor,
        lethal_transition = lethal_transition })
    self.log("execution_damage_return", { target = target.id, source = frame.ability,
        died_in_call = frame.died or false, lethal_transition = lethal_transition })
end
function Adapter:take_damage_begin(raw_component, raw_source)
    local component = UE.unwrap(raw_component)
    local component_record = UE.record(component)
    local target_object = UE.call(component, "GetOwner")
    local target = UE.record(target_object)
    local frame = { module = component_record and component_record.id, target = target and target.id,
        epoch = self.core.epoch }
    for _, parent in ipairs(self.damage_stack) do
        if target and parent.target == target.id then parent.contaminated = true end
    end
    self.damage_stack[#self.damage_stack + 1] = frame
    if not target or not self.core:has_target(target.id) then return end
    local source = UE.unwrap(raw_source)
    local ability = UE.call(source, "GetDamageSourceAbility")
    local ability_record = UE.record(ability)
    local executor = UE.record(UE.call(ability, "GetAvatarActorFromActorInfo"))
    frame.ability = ability_record and ability_record.id
    frame.executor = executor and executor.id
    frame.alive = UE.call(UE.resolve(self.death_components[target.id]), "Is Dead") == false
    frame.health_before = UE.health(target_object)
    self.core:damage({ target = target.id, ability = frame.ability, executor = frame.executor,
        taken = frame.alive and type(frame.health_before) == "number" and frame.health_before <= 0,
        preserve_lethal = true })
    self.log("take_damage_source", { target = target.id, source_type = type(source),
        source = (UE.record(source) or {}).full, ability = frame.ability, executor = frame.executor,
        alive_before = frame.alive, depth = #self.damage_stack })
end
function Adapter:take_damage_end(raw_component)
    local component = UE.unwrap(raw_component)
    self:execution_damage_end(component, UE.call(component, "GetOwner"))
end
function Adapter:prune()
    local wanted_actors, wanted_abilities = {}, {}
    for _, s in pairs(self.core.sessions) do wanted_actors[s.target] = true; wanted_abilities[s.ability] = true end
    for id in pairs(self.actors) do if not wanted_actors[id] then self.actors[id] = nil; self.death_components[id] = nil end end
    for id in pairs(self.abilities) do if not wanted_abilities[id] then self.abilities[id] = nil; self.runs[id] = nil end end
end
return Adapter
