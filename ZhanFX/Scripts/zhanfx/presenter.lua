local C = require("zhanfx.constants")
local Presenter = {}
Presenter.__index = Presenter

function Presenter.new(options)
    return setmetatable({ draw = options.draw, visible = options.visible, log = options.log or function() end,
        active = {}, reserved_until = nil, armed = {}, preview_seen = false, preview_closed = false,
        pending_origin = nil, original_until = nil, eligible = {}, stats = { shown = 0, merged = 0, failed = 0, probe = 0 } }, Presenter)
end

function Presenter:reset()
    self.active, self.armed, self.reserved_until, self.pending_origin, self.original_until = {}, {}, nil, nil, nil
    self.preview_seen, self.preview_closed, self.eligible = false, false, {}
end

function Presenter:activate(id, now)
    local pending = self.pending_origin and (not now or (self.reserved_until and now <= self.reserved_until))
    local origin = pending and self.pending_origin or "original"
    self.active[id] = origin
    if origin == "preview" then self.preview_seen = true end
    self.pending_origin, self.reserved_until, self.original_until = nil, nil, nil
    self.log("ui_activated", { id = id, origin = origin })
end
function Presenter:original_request(now)
    -- Cover the gap between the original streamed push and the actual Widget activation.
    for _, origin in pairs(self.active) do if origin == "original" then return end end
    self.pending_origin = nil -- interleaved original push makes pending preview ownership ambiguous
    self.original_until = now + C.PresentationSeconds + 0.5
end

function Presenter:deactivate(id)
    if self.active[id] == "preview" then self.preview_closed = true end
    self.active[id] = nil
    self.log("ui_deactivated", { id = id })
end

function Presenter:request(now, kind, preview)
    if self.reserved_until and now >= self.reserved_until then
        self.pending_origin, self.reserved_until = nil, nil
    end
    if not preview then
        self.eligible[kind] = (self.eligible[kind] or 0) + 1
        if not self.armed[kind] then self.stats.probe = self.stats.probe + 1; return "probe_only" end
    end
    local ok, visible = pcall(self.visible)
    if not ok or visible == nil then return "visibility_unknown" end
    if visible or next(self.active) or (self.reserved_until and now < self.reserved_until) or
        (self.original_until and now < self.original_until) then
        self.stats.merged = self.stats.merged + 1
        return "merged"
    end
    self.reserved_until = now + C.PresentationSeconds + 0.5
    self.pending_origin = preview and "preview" or "mod"
    local called, result = pcall(self.draw)
    if not called or result ~= true then
        self.pending_origin = nil
        self.stats.failed = self.stats.failed + 1
        return "draw_failed"
    end
    self.stats.shown = self.stats.shown + 1
    return preview and "preview_requested" or "shown"
end

function Presenter:arm(kind)
    if not self.preview_seen or not self.preview_closed then return false, "preview_activation_and_exit_required" end
    if not self.eligible[kind] or self.eligible[kind] < 1 then return false, "eligible_probe_sample_required" end
    self.armed[kind] = true
    return true, "armed_for_current_world_only"
end

function Presenter:disarm() self.armed = {} end

return Presenter
