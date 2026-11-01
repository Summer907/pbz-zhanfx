-- Only Mod toggle notices are translated. Never change the game's language.
local UE = require("zhanfx.ue")
local I18n = {}

I18n.messages = {
    ["en"] = { enabled = "ZhanFX enabled", disabled = "ZhanFX disabled" },
    ["zh-hans"] = { enabled = "ZhanFX 已开启", disabled = "ZhanFX 已关闭" },
    ["zh-hant"] = { enabled = "ZhanFX 已開啟", disabled = "ZhanFX 已關閉" },
    ["fr"] = { enabled = "ZhanFX activé", disabled = "ZhanFX désactivé" },
    ["de"] = { enabled = "ZhanFX aktiviert", disabled = "ZhanFX deaktiviert" },
    ["es-es"] = { enabled = "ZhanFX activado", disabled = "ZhanFX desactivado" },
    ["es-419"] = { enabled = "ZhanFX activado", disabled = "ZhanFX desactivado" },
    ["ru"] = { enabled = "ZhanFX включён", disabled = "ZhanFX выключен" },
    ["ja"] = { enabled = "ZhanFX 有効", disabled = "ZhanFX 無効" },
    ["pt-br"] = { enabled = "ZhanFX ativado", disabled = "ZhanFX desativado" },
    ["pt-pt"] = { enabled = "ZhanFX ativado", disabled = "ZhanFX desativado" },
    ["ko"] = { enabled = "ZhanFX 켜짐", disabled = "ZhanFX 꺼짐" },
    ["it"] = { enabled = "ZhanFX attivato", disabled = "ZhanFX disattivato" },
    ["th"] = { enabled = "เปิดใช้งาน ZhanFX แล้ว", disabled = "ปิดใช้งาน ZhanFX แล้ว" },
    ["vi"] = { enabled = "Đã bật ZhanFX", disabled = "Đã tắt ZhanFX" },
}

local base = {
    en = "en", zh = "zh-hans", fr = "fr", de = "de", es = "es-es",
    ru = "ru", ja = "ja", pt = "pt-pt", ko = "ko", it = "it", th = "th", vi = "vi",
}
local latin_spanish = {
    ["419"] = true, ar = true, bo = true, cl = true, co = true, cr = true,
    cu = true, ["do"] = true, ec = true, sv = true, gt = true, hn = true,
    mx = true, ni = true, pa = true, py = true, pe = true, pr = true, uy = true, ve = true,
}

local function normalize(tag)
    if type(tag) ~= "string" or #tag > 64 then return nil end
    tag = tag:match("^%s*(.-)%s*$"):gsub("_", "-"):lower()
    if tag == "" or tag:find("[^a-z0-9%-]") or tag:find("%-%-") or
        tag:sub(1, 1) == "-" or tag:sub(-1) == "-" then return nil end
    return tag
end

function I18n.resolve(tag)
    local normalized = normalize(tag)
    if not normalized then return "en", "invalid_language" end
    if I18n.messages[normalized] then return normalized, "exact" end
    local parts = {}
    for part in normalized:gmatch("[^%-]+") do parts[#parts + 1] = part end
    local language, script, region = parts[1]
    -- Ignore extension/private-use subtags when choosing the script/region.
    for i = 2, #parts do
        local part = parts[i]
        if #part == 1 then break end
        if #part == 4 and part:match("^%a+$") and not script then script = part end
        if ((#part == 2 and part:match("^%a+$")) or
            (#part == 3 and part:match("^%d+$"))) and not region then region = part end
    end
    if language == "zh" then
        if script == "hant" then return "zh-hant", "script" end
        if script == "hans" then return "zh-hans", "script" end
        if region == "tw" or region == "hk" or region == "mo" then return "zh-hant", "region" end
    elseif language == "es" and latin_spanish[region] then
        return "es-419", "region"
    elseif language == "pt" and region == "br" then
        return "pt-br", "region"
    end
    return base[language] or "en", base[language] and "base_language" or "unsupported_language"
end

local function game_language()
    local library = UE.find("/Script/Engine.Default__KismetInternationalizationLibrary")
    if not library then return nil, "language_library_missing", "unavailable" end
    local ok, value = pcall(function() return UE.unwrap(library:GetCurrentLanguage()) end)
    if not ok then return nil, "language_call_failed", "unavailable" end
    local return_type = type(value)
    if return_type == "userdata" or return_type == "table" then
        -- UE4SS exposes FString as an object, not a Lua string. Convert it here,
        -- within the game-thread callback; tostring(value) would give a wrapper address.
        local converted, text = pcall(function() return value:ToString() end)
        if not converted then return nil, "language_string_conversion_failed", return_type end
        value = text
    end
    if type(value) ~= "string" then return nil, "language_return_type_invalid", return_type end
    if value:match("^%s*$") then return nil, "language_empty", return_type end
    return value, nil, return_type
end

function I18n.text(key, language)
    local requested, reason, return_type = language, nil, type(language)
    if language == nil or normalize(language) == "auto" then
        requested, reason, return_type = game_language()
    end
    local selected, match_reason = I18n.resolve(requested)
    local entry = I18n.messages[selected]
    local message = entry and entry[key]
    if type(message) ~= "string" or message == "" then
        message = I18n.messages.en[key] or "ZhanFX"
        reason = "missing_translation"
    end
    return message, selected, type(requested) == "string" and requested or "unavailable", reason or match_reason, return_type
end

return I18n
