local I18n = require("zhanfx.i18n")
local Fake = require("fake_engine")
local Runtime = require("zhanfx.runtime")
local cases = {}
local function test(name, fn) cases[#cases + 1] = {name, fn} end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function fixture()
    local f = Fake.new(); f:install()
    f.app = Runtime.new({Enabled=false, AutoEnableCombat=true, Language="auto", Categories={combat=true}})
    assert(f.app:start()); f.app:tick()
    return f
end
local function toggle(f) f.keys.F8(); f:drain(); return f.notices[#f.notices].text end

local expected = {
    {"en-US", "en"}, {"zh-CN", "zh-hans"}, {"zh-TW", "zh-hant"},
    {"fr-FR", "fr"}, {"de-DE", "de"}, {"es-ES", "es-es"}, {"es-419", "es-419"},
    {"ru-RU", "ru"}, {"ja-JP", "ja"}, {"pt-BR", "pt-br"}, {"pt-PT", "pt-pt"},
    {"ko-KR", "ko"}, {"it-IT", "it"}, {"th-TH", "th"}, {"vi-VN", "vi"},
}
test("shipped configuration preserves player defaults", function()
    local config = require("config")
    eq(config.Language, "auto"); eq(config.Enabled, false); eq(config.AutoEnableCombat, true)
    eq(config.Categories.combat, true)
    eq(config.Categories.simple, false); eq(config.Categories.stealth, false); eq(config.Categories.air, false)
end)
test("renamed main entry replaces only its own previous runtime", function()
    local f = Fake.new(); f:install()
    local stopped = false
    _G.__ZhanFX = {shutdown=function() stopped = true end}
    require("main")
    assert(stopped); eq(_G.__ZhanFX.config.Enabled, false)
    eq(_G.__ZhanFX.config.Language, "auto")
    _G.__ZhanFX:shutdown(); _G.__ZhanFX = nil
end)
test("exactly fifteen complete UTF-8 catalogs", function()
    local count = 0
    for _, messages in pairs(I18n.messages) do
        count = count + 1
        for _, key in ipairs({"enabled", "disabled"}) do
            local text = messages[key]
            assert(type(text) == "string" and #text > 6 and text:find("ZhanFX", 1, true))
            assert(utf8.len(text)); assert(not text:find(utf8.char(0xfffd), 1, true))
        end
        assert(messages.enabled ~= messages.disabled)
    end
    eq(count, 15)
end)
for _, item in ipairs(expected) do
    local tag, locale = item[1], item[2]
    test("game-thread ON/OFF for " .. tag, function()
        local f = fixture(); f.language = tag
        eq(f.language_reads, 0)
        f.keys.F8(); eq(f.language_reads, 0); f:drain()
        eq(f.notices[1].text, I18n.messages[locale].enabled)
        eq(f.app.config.Enabled, true); eq(f.app.presenter.armed.combat, true)
        eq(toggle(f), I18n.messages[locale].disabled); eq(f.app.config.Enabled, false)
        eq(f.language_reads, 2); eq(#f.registrations, 12)
        f.app:tick(); eq(f.language_reads, 2)
    end)
end
test("BCP47 script, region, case, underscore and base matching", function()
    for tag, locale in pairs({
        [" ZH_hAnT_tw "]="zh-hant", ["zh-Hans-TW"]="zh-hans", ["zh-Hant-CN"]="zh-hant",
        ["zh-HK"]="zh-hant", ["zh-MO"]="zh-hant", ["zh-SG"]="zh-hans", zh="zh-hans",
        ["es-MX"]="es-419", ["es-AR"]="es-419", es="es-es", pt="pt-pt",
        ["pt_Latn_BR"]="pt-br", ["en-GB"]="en", ["fr-CA"]="fr",
        ["zh-CN-u-rg-twzzzz"]="zh-hans", ["zh-x-hant"]="zh-hans",
    }) do eq(I18n.resolve(tag), locale) end
end)
test("unknown or malformed tags fall back to English", function()
    for _, tag in ipairs({false, 123, {}, "", " ", "xx-ZZ", "en--US", "-zh", "zh-", "zh!", string.rep("a", 65)}) do
        eq(I18n.resolve(tag), "en"); eq(I18n.text("enabled", tag), "ZhanFX enabled")
    end
end)
test("language change is read on next notice without refreshing old widget", function()
    local f = fixture(); eq(toggle(f), "ZhanFX 已开启")
    local first = f.notices[1]; f.language = "ja-JP"
    eq(first.text, "ZhanFX 已开启")
    eq(toggle(f), "ZhanFX 無効"); eq(first.on_screen, false)
end)
test("manual override skips engine query", function()
    local f = fixture(); f.app.config.Language = "zh-Hant"
    eq(toggle(f), "ZhanFX 已開啟"); eq(f.language_reads, 0)
end)
test("missing API does not stop enabling or disabling", function()
    local f = fixture(); f.objects["/Script/Engine.Default__KismetInternationalizationLibrary"] = nil
    eq(toggle(f), "ZhanFX enabled"); eq(f.app.presenter.armed.combat, true)
    eq(toggle(f), "ZhanFX disabled"); eq(f.app.config.Enabled, false)
    local _, _, _, reason = I18n.text("enabled", "auto")
    eq(reason, "language_library_missing")
end)
test("throwing API is isolated from the switch", function()
    local f = fixture()
    f.objects["/Script/Engine.Default__KismetInternationalizationLibrary"].GetCurrentLanguage = function() error("missing binding") end
    eq(toggle(f), "ZhanFX enabled"); eq(next(f.app.errors), nil)
    local message, _, _, reason = I18n.text("disabled", "auto")
    eq(message, "ZhanFX disabled"); eq(reason, "language_call_failed")
end)

test("FString return is converted before language matching", function()
    local f = fixture()
    local conversions = 0
    f.language = {ToString=function() conversions = conversions + 1; return "zh-Hans" end}
    eq(toggle(f), "ZhanFX 已开启"); eq(toggle(f), "ZhanFX 已关闭")
    eq(conversions, 2); eq(f.language_reads, 2)
    local _, selected, requested, reason, return_type = I18n.text("enabled", "auto")
    eq(selected, "zh-hans"); eq(requested, "zh-Hans"); eq(reason, "exact"); eq(return_type, "table")
end)

test("converted FString follows language changes and does not use tostring", function()
    local f = fixture(); local tag = "zh-CN"
    f.language = setmetatable({ToString=function() return tag end}, {__tostring=function() error("wrapper address is not a language") end})
    eq(toggle(f), "ZhanFX 已开启")
    tag = "zh-Hant"; eq(toggle(f), "ZhanFX 已關閉")
    tag = "ja-JP"; eq(toggle(f), "ZhanFX 有効")
end)

test("FString conversion errors cannot stop the switch", function()
    local f = fixture()
    f.language = {ToString=function() error("conversion unavailable") end}
    eq(toggle(f), "ZhanFX enabled"); eq(f.app.presenter.armed.combat, true)
    eq(toggle(f), "ZhanFX disabled"); eq(next(f.app.errors), nil)
    local _, _, _, reason, return_type = I18n.text("enabled", "auto")
    eq(reason, "language_string_conversion_failed"); eq(return_type, "table")
end)

test("invalid and empty FString values have distinct failure reasons", function()
    local f = fixture()
    for _, value in ipairs({false, {}, 42}) do
        f.language = {ToString=function() return value end}
        local text, _, _, reason = I18n.text("enabled", "auto")
        eq(text, "ZhanFX enabled"); eq(reason, "language_return_type_invalid")
    end
    f.language = {ToString=function() return " " end}
    local _, _, _, reason = I18n.text("disabled", "auto")
    eq(reason, "language_empty")
end)

test("RemoteUnrealParam containing FString is unwrapped and converted", function()
    local f = fixture()
    f.language = f:remote({ToString=function() return "zh-Hans-CN" end})
    eq(toggle(f), "ZhanFX 已开启")
end)

test("manual override never invokes FString conversion", function()
    local f = fixture(); f.app.config.Language = "zh-Hant"
    f.language = {ToString=function() error("must not be queried") end}
    eq(toggle(f), "ZhanFX 已開啟"); eq(f.language_reads, 0)
end)
test("invalid engine return and unsupported game language fall back", function()
    local f = fixture()
    for _, value in ipairs({false, {}, 42, "", "xx-ZZ"}) do
        f.language = value; eq(I18n.text("enabled", "auto"), "ZhanFX enabled")
    end
    f.language = nil; eq(I18n.text("disabled", "auto"), "ZhanFX disabled")
end)
test("a missing catalog key uses English", function()
    local old = I18n.messages.fr.disabled; I18n.messages.fr.disabled = nil
    local text, _, _, reason = I18n.text("disabled", "fr")
    I18n.messages.fr.disabled = old
    eq(text, "ZhanFX disabled"); eq(reason, "missing_translation")
end)
test("translated notice still expires when feedback is OFF and game time paused", function()
    local f = fixture(); f.language = "th-TH"; f.real_clock = 1
    toggle(f); toggle(f); local widget = f.notices[2]
    f.real_clock = 4; f.app:tick(); eq(widget.on_screen, false); eq(f.clock, 1)
end)

local results, passed = {}, 0
for _, case in ipairs(cases) do
    local ok, err = pcall(case[2])
    results[#results + 1] = {name=case[1], passed=ok, error=not ok and tostring(err) or nil}
    if ok then passed = passed + 1 end
end
return {suite="i18n", passed=passed, total=#cases, results=results}
