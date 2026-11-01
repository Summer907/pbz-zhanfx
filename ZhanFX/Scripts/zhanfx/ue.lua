-- Read-only reflection helpers. Never retain RemoteUnrealParam / UScriptStruct values.
local UE = {}
function UE.unwrap(value)
    if type(value) ~= "userdata" and type(value) ~= "table" then return value end
    local ok, get = pcall(function() return value.get end)
    if ok and type(get) == "function" then
        local read, unwrapped = pcall(get, value)
        if read then return unwrapped end
    end
    return value
end
function UE.field(object, name)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[name] end)
    if ok then return UE.unwrap(value) end
end
function UE.call(object, name, ...)
    if object == nil then return nil end
    local args = table.pack(...)
    local ok, value = pcall(function() return object[name](object, table.unpack(args, 1, args.n)) end)
    if ok then return UE.unwrap(value) end
end
function UE.valid(object) return object ~= nil and UE.call(object, "IsValid") == true end
function UE.find(path)
    if type(StaticFindObject) ~= "function" then return nil end
    local ok, object = pcall(StaticFindObject, path)
    if ok and UE.valid(object) then return object end
end
function UE.load(path)
    local object = UE.find(path)
    if object then return object end
    if type(LoadAsset) == "function" then pcall(LoadAsset, path) end
    return UE.find(path)
end
function UE.record(object)
    if not UE.valid(object) then return nil end
    local full, address = UE.call(object, "GetFullName"), UE.call(object, "GetAddress")
    if type(full) ~= "string" or type(address) ~= "number" then return nil end
    local path = full:match("^%S+ (.+)$")
    if not path then return nil end
    return { id = full .. "@" .. tostring(address), path = path, full = full, address = address }
end
function UE.resolve(record)
    if not record then return nil end
    local object = UE.find(record.path)
    if object and UE.call(object, "GetAddress") == record.address and UE.call(object, "GetFullName") == record.full then return object end
end
function UE.isa(object, path) return UE.call(object, "IsA", path) end
function UE.tag(value)
    value = UE.unwrap(value)
    if type(value) == "string" then return value end
    local name = UE.field(value, "TagName")
    if type(name) == "string" then return name end
    return UE.call(name, "ToString")
end
function UE.has_tag(actor, tag)
    local library = UE.find("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
    if not library then return nil, "ability_system_library_missing" end
    local got, asc = pcall(function() return library:GetAbilitySystemComponent(actor) end)
    if not got then return nil, "ability_system_lookup: " .. tostring(asc) end
    asc = UE.unwrap(asc)
    if not UE.valid(asc) then return nil, "ability_system_component_invalid" end
    local ok, name = pcall(FName, tag)
    if not ok then return nil, "fname_constructor: " .. tostring(name) end
    local called, value = pcall(function() return asc:HasMatchingGameplayTag({ TagName = name }) end)
    if not called then return nil, "tag_query: " .. tostring(value) end
    value = UE.unwrap(value)
    if type(value) == "boolean" then return value end
    return nil, "tag_query_return_type: " .. type(value)
end
function UE.hostile(target, player)
    local utils = UE.find("/Script/SGameCombatSystem.Default__FactionUtils")
    local attitude = UE.call(utils, "GetFactionRelation", target, player)
    if type(attitude) == "number" then return attitude == 2 end -- AIModule.ETeamAttitude::Hostile
end
function UE.health(actor)
    local library = UE.find("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary")
    local asc = UE.call(library, "GetAbilitySystemComponent", actor)
    local attributes = UE.field(asc, "SpawnedAttributes")
    if not attributes then return nil end
    local result, count = nil, 0
    local ok = pcall(function() attributes:ForEach(function(_, element)
        count = count + 1
        if count > 32 then return end
        local set = UE.unwrap(element)
        if UE.isa(set, "/Script/CharacterBasics.BasicAttributeSet") == true then
            local value = UE.field(UE.field(set, "Health"), "CurrentValue")
            if type(value) == "number" and value == value and math.abs(value) < math.huge then result = value end
        end
    end) end)
    if ok then return result end
end
function UE.is_ai(target)
    local controller = UE.call(target, "GetController")
    if not UE.valid(controller) then controller = UE.field(target, "Controller") end
    return UE.isa(controller, "/Script/AIModule.AIController")
end
function UE.death_component(target, class_path)
    local class = UE.find(class_path)
    if not class then return nil end
    local component = UE.call(target, "GetComponentByClass", class)
    if UE.valid(component) then return component end
end
return UE
