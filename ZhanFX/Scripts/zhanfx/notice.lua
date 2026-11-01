local UE = require("zhanfx.ue")
local Notice = {}
Notice.__index = Notice
local CLASS = "/Game/PBZContent/UI/InGame/SwitchUI/WB_TipsText.WB_TipsText_C"

function Notice.new(log) return setmetatable({ log = log }, Notice) end
function Notice:clear()
    local widget = UE.resolve(self.widget)
    if widget then UE.call(widget, "RemoveFromParent") end
    self.widget, self.owner, self.expires = nil, nil, nil
end
function Notice:show(context, text)
    self:clear()
    if not context then return false end
    local class = UE.load(CLASS)
    local library = UE.find("/Script/UMG.Default__WidgetBlueprintLibrary")
    if not class or not library or not UE.valid(context.controller) then
        self.log("notice_failed", { reason = "widget_class_or_controller" }); return false
    end
    local widget = UE.call(library, "Create", context.player, class, context.controller)
    if not UE.valid(widget) then self.log("notice_failed", { reason = "create_widget" }); return false end
    local ok, err = pcall(function()
        local value = FText(text)
        widget:AddToViewport(10000)
        widget["SetText"](widget, value)
        widget:SetVisibility(3) -- HitTestInvisible: never capture game input.
    end)
    if not ok then
        UE.call(widget, "RemoveFromParent")
        self.log("notice_failed", { reason = tostring(err) }); return false
    end
    self.widget, self.owner = UE.record(widget), context.player_record
    local statics = UE.find("/Script/Engine.Default__GameplayStatics")
    local now = UE.call(statics, "GetRealTimeSeconds", context.player)
    if not self.widget or type(now) ~= "number" then self:clear(); return false end
    self.expires = now + 2.5
    self.log("notice_shown", { text = text })
    return true
end
function Notice:tick()
    if not self.widget then return end
    local owner = UE.resolve(self.owner)
    if not owner then self:clear(); return end
    local statics = UE.find("/Script/Engine.Default__GameplayStatics")
    local now = UE.call(statics, "GetRealTimeSeconds", owner)
    if type(now) ~= "number" or now >= self.expires then self:clear() end
end
return Notice
