local addonName, addon = ...

addon = addon or {}

local Overlay = {}

local DEFAULT_WIDTH = 320
local DEFAULT_HEIGHT = 240
local MIN_WIDTH = 240
local MIN_HEIGHT = 120
local MAX_WIDTH = 800
local MAX_HEIGHT = 800
local TITLE_BAR_HEIGHT = 28
local BODY_INSET = 8
local BUTTON_HEIGHT = 22
local LOCK_BUTTON_WIDTH = 52
local UNPIN_BUTTON_WIDTH = 58
local RESIZE_HANDLE_SIZE = 16
local DEFAULT_OFFSET_STEP = 24

local VALID_ANCHOR_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = {
        left = 11,
        right = 12,
        top = 12,
        bottom = 11,
    },
}

local function is_number(value)
    return type(value) == "number"
end

local function clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function get_dimension(widget, methodName, fallback)
    if widget and type(widget[methodName]) == "function" then
        local value = widget[methodName](widget)
        if is_number(value) and value > 0 then
            return value
        end
    end
    return fallback
end

local function get_scale(widget, fallback)
    if widget and type(widget.GetEffectiveScale) == "function" then
        local value = widget:GetEffectiveScale()
        if is_number(value) and value > 0 then
            return value
        end
    end
    return fallback
end

local function horizontal_fraction(point)
    if type(point) ~= "string" then
        return 0.5
    end
    if string.find(point, "LEFT", 1, true) then
        return 0
    end
    if string.find(point, "RIGHT", 1, true) then
        return 1
    end
    return 0.5
end

local function vertical_fraction(point)
    if type(point) ~= "string" then
        return 0.5
    end
    if string.find(point, "BOTTOM", 1, true) then
        return 0
    end
    if string.find(point, "TOP", 1, true) then
        return 1
    end
    return 0.5
end

local function clamp_position(frame, point, relativePoint, x, y, width, height)
    local screenWidth = get_dimension(UIParent, "GetWidth", nil)
    local screenHeight = get_dimension(UIParent, "GetHeight", nil)
    if not screenWidth or not screenHeight then
        return x, y, false
    end

    local parentScale = get_scale(UIParent, 1)
    local frameScale = get_scale(frame, parentScale)
    local scale = frameScale / parentScale
    local scaledWidth = width * scale
    local scaledHeight = height * scale

    local relativeX = screenWidth * horizontal_fraction(relativePoint)
    local relativeY = screenHeight * vertical_fraction(relativePoint)
    local frameAnchorX = scaledWidth * horizontal_fraction(point)
    local frameAnchorY = scaledHeight * vertical_fraction(point)

    local left = relativeX + x - frameAnchorX
    local bottom = relativeY + y - frameAnchorY
    local maxLeft = math.max(0, screenWidth - scaledWidth)
    local maxBottom = math.max(0, screenHeight - scaledHeight)

    local clampedLeft = clamp(left, 0, maxLeft)
    local clampedBottom = clamp(bottom, 0, maxBottom)
    local clampedX = clampedLeft - relativeX + frameAnchorX
    local clampedY = clampedBottom - relativeY + frameAnchorY

    return clampedX, clampedY, clampedX ~= x or clampedY ~= y
end

local function default_layout(offset)
    offset = is_number(offset) and offset or 0
    return {
        point = "CENTER",
        relativePoint = "CENTER",
        x = offset,
        y = -offset,
        width = DEFAULT_WIDTH,
        height = DEFAULT_HEIGHT,
    }
end

local function create_button(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, BUTTON_HEIGHT)
    button:SetText(text)
    if button.RegisterForClicks then
        button:RegisterForClicks("AnyUp")
    end
    return button
end

local function update_body_width(frame)
    if not frame or not frame.bodyContent then
        return
    end

    local frameWidth = get_dimension(frame, "GetWidth", DEFAULT_WIDTH)
    local contentWidth = math.max(1, frameWidth - (BODY_INSET * 2))
    frame.bodyContent:SetWidth(contentWidth)
end

local function apply_lock_state(frame, locked)
    locked = locked == true
    frame.locked = locked

    if frame.SetMovable then
        frame:SetMovable(not locked)
    end
    if frame.SetResizable then
        frame:SetResizable(not locked)
    end
    if frame.resizeHandle and frame.resizeHandle.EnableMouse then
        frame.resizeHandle:EnableMouse(not locked)
    end
    if frame.lockButton and frame.lockButton.SetText then
        frame.lockButton:SetText(locked and "Unlock" or "Lock")
    end
end

local function save_frame_geometry(manager, noteId, frame)
    local store = manager.addon and manager.addon.store
    if not store or type(store.SaveOverlayGeometry) ~= "function" then
        return false
    end

    local point
    local relativePoint
    local x
    local y
    if type(frame.GetPoint) == "function" then
        point, _, relativePoint, x, y = frame:GetPoint(1)
    end

    local previous = frame.lastGeometry or {}
    point = type(point) == "string" and point or previous.point or "CENTER"
    relativePoint = type(relativePoint) == "string" and relativePoint or previous.relativePoint or "CENTER"
    x = is_number(x) and x or previous.x or 0
    y = is_number(y) and y or previous.y or 0

    local width = get_dimension(frame, "GetWidth", previous.width or DEFAULT_WIDTH)
    local height = get_dimension(frame, "GetHeight", previous.height or DEFAULT_HEIGHT)

    frame.lastGeometry = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
        width = width,
        height = height,
    }

    return store:SaveOverlayGeometry(noteId, point, relativePoint, x, y, width, height)
end

local function apply_geometry(manager, noteId, frame, layout)
    layout = type(layout) == "table" and layout or {}

    local point = VALID_ANCHOR_POINTS[layout.point] and layout.point or "CENTER"
    local relativePoint = VALID_ANCHOR_POINTS[layout.relativePoint] and layout.relativePoint or "CENTER"
    local x = is_number(layout.x) and layout.x or 0
    local y = is_number(layout.y) and layout.y or 0
    local width = is_number(layout.width) and layout.width or DEFAULT_WIDTH
    local height = is_number(layout.height) and layout.height or DEFAULT_HEIGHT

    width = clamp(width, MIN_WIDTH, MAX_WIDTH)
    height = clamp(height, MIN_HEIGHT, MAX_HEIGHT)
    local clampedX, clampedY, positionChanged = clamp_position(frame, point, relativePoint, x, y, width, height)

    frame.applyingLayout = true
    frame:ClearAllPoints()
    frame:SetSize(width, height)
    frame:SetPoint(point, UIParent, relativePoint, clampedX, clampedY)
    frame.applyingLayout = false

    frame.lastGeometry = {
        point = point,
        relativePoint = relativePoint,
        x = clampedX,
        y = clampedY,
        width = width,
        height = height,
    }

    update_body_width(frame)
    apply_lock_state(frame, layout.locked == true)

    if positionChanged then
        local store = manager.addon and manager.addon.store
        if store and type(store.SaveOverlayGeometry) == "function" then
            store:SaveOverlayGeometry(noteId, point, relativePoint, clampedX, clampedY, width, height)
        end
    end
end

local function create_frame(manager, noteId)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame.noteId = noteId
    frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    frame:SetPoint("CENTER")
    if frame.SetBackdrop then
        frame:SetBackdrop(BACKDROP)
    end
    if frame.SetBackdropColor then
        frame:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
    end
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    end
    if frame.SetFrameStrata then
        frame:SetFrameStrata("HIGH")
    end
    if frame.SetToplevel then
        frame:SetToplevel(true)
    end
    if frame.SetClampedToScreen then
        frame:SetClampedToScreen(true)
    end
    if frame.EnableMouse then
        frame:EnableMouse(true)
    end
    if frame.SetMovable then
        frame:SetMovable(true)
    end
    if frame.SetResizable then
        frame:SetResizable(true)
    end
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    end

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", BODY_INSET, -BODY_INSET)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -BODY_INSET, -BODY_INSET)
    titleBar:SetHeight(TITLE_BAR_HEIGHT)
    if titleBar.EnableMouse then
        titleBar:EnableMouse(true)
    end
    if titleBar.RegisterForDrag then
        titleBar:RegisterForDrag("LeftButton")
    end

    local lockButton = create_button(titleBar, "Lock", LOCK_BUTTON_WIDTH)
    lockButton:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", -(UNPIN_BUTTON_WIDTH + 4), 0)

    local unpinButton = create_button(titleBar, "Unpin", UNPIN_BUTTON_WIDTH)
    unpinButton:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", 0, 0)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", BODY_INSET + 2, -BODY_INSET - 6)
    title:SetPoint("TOPRIGHT", lockButton, "TOPLEFT", -4, 0)
    title:SetText("")

    local bodyScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    bodyScroll:SetSize(DEFAULT_WIDTH - (BODY_INSET * 2), DEFAULT_HEIGHT - TITLE_BAR_HEIGHT - (BODY_INSET * 2))
    bodyScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", BODY_INSET, -(TITLE_BAR_HEIGHT + BODY_INSET))
    bodyScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BODY_INSET, BODY_INSET)

    local bodyContent = CreateFrame("Frame", nil, bodyScroll)
    bodyContent:SetSize(DEFAULT_WIDTH - (BODY_INSET * 2), 1)
    bodyScroll:SetScrollChild(bodyContent)
    if bodyScroll.Show then
        bodyScroll:Show()
    end
    if bodyContent.Show then
        bodyContent:Show()
    end

    local resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(RESIZE_HANDLE_SIZE, RESIZE_HANDLE_SIZE)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    if resizeHandle.SetNormalTexture then
        resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    end
    if resizeHandle.SetHighlightTexture then
        resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    end

    frame.titleBar = titleBar
    frame.title = title
    frame.lockButton = lockButton
    frame.unpinButton = unpinButton
    frame.bodyScroll = bodyScroll
    frame.scroll = bodyScroll
    frame.bodyContent = bodyContent
    frame.content = bodyContent
    frame.resizeHandle = resizeHandle
    frame.locked = false

    titleBar:SetScript("OnDragStart", function()
        if not frame.locked then
            frame:StartMoving()
        end
    end)
    titleBar:SetScript("OnDragStop", function()
        if not frame.locked then
            frame:StopMovingOrSizing()
            save_frame_geometry(manager, noteId, frame)
        end
    end)

    lockButton:SetScript("OnClick", function()
        local locked = not frame.locked
        local store = manager.addon and manager.addon.store
        if store and type(store.SetOverlayLocked) == "function" and store:SetOverlayLocked(noteId, locked) then
            apply_lock_state(frame, locked)
        end
    end)

    unpinButton:SetScript("OnClick", function()
        manager:Unpin(noteId)
    end)

    frame:SetScript("OnSizeChanged", function()
        update_body_width(frame)
        if not frame.applyingLayout then
            save_frame_geometry(manager, noteId, frame)
            manager:Refresh(noteId)
        end
    end)

    resizeHandle:SetScript("OnMouseDown", function()
        if not frame.locked then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        if not frame.locked then
            frame:StopMovingOrSizing()
            save_frame_geometry(manager, noteId, frame)
        end
    end)

    frame:Hide()
    return frame
end

local function is_frame_shown(frame)
    if frame and type(frame.IsShown) == "function" then
        return frame:IsShown()
    end
    return frame ~= nil
end

local function count_active_frames(manager)
    local count = 0
    for _, frame in pairs(manager.framesByNoteId) do
        if is_frame_shown(frame) then
            count = count + 1
        end
    end
    return count
end

local function hide_and_remove_frame(manager, noteId)
    local frame = manager.framesByNoteId[noteId]
    if frame then
        frame.visible = false
        frame:Hide()
        manager.framesByNoteId[noteId] = nil
    end
end

local function show_frame(manager, noteId, layout)
    local frame = manager.framesByNoteId[noteId] or manager:createFrame(noteId)
    if not frame then
        return false
    end

    apply_geometry(manager, noteId, frame, layout)
    manager:Refresh(noteId)
    if manager.framesByNoteId[noteId] ~= frame then
        return false
    end

    frame.visible = true
    frame:Show()
    return true
end

function Overlay.Create(addon)
    return setmetatable({
        addon = addon,
        framesByNoteId = {},
    }, { __index = Overlay })
end

function Overlay:createFrame(noteId)
    local frame = self.framesByNoteId[noteId]
    if frame then
        return frame
    end

    frame = create_frame(self, noteId)
    self.framesByNoteId[noteId] = frame
    return frame
end

function Overlay:Pin(noteId)
    if noteId == nil then
        return false
    end

    local store = self.addon and self.addon.store
    if not store or type(store.GetNote) ~= "function" or type(store.PinOverlay) ~= "function" then
        return false
    end

    local note = store:GetNote(noteId)
    if not note then
        return false
    end

    local offset = count_active_frames(self) * DEFAULT_OFFSET_STEP
    local layout = store:PinOverlay(noteId, default_layout(offset))
    if not layout then
        return false
    end

    return show_frame(self, noteId, layout)
end

function Overlay:Unpin(noteId)
    local store = self.addon and self.addon.store
    local changed = false
    if store and type(store.SetOverlayVisible) == "function" then
        changed = store:SetOverlayVisible(noteId, false) == true
    end

    local frame = self.framesByNoteId[noteId]
    if frame then
        frame.visible = false
        frame:Hide()
    end

    return changed
end

function Overlay:UnpinAll()
    local noteIds = {}
    for noteId in pairs(self.framesByNoteId) do
        noteIds[#noteIds + 1] = noteId
    end

    for _, noteId in ipairs(noteIds) do
        self:Unpin(noteId)
    end
end

function Overlay:RestoreVisible()
    local store = self.addon and self.addon.store
    if not store or type(store.ListVisibleOverlays) ~= "function" then
        return
    end

    local visibleIds = {}
    local visible = store:ListVisibleOverlays() or {}
    for _, entry in ipairs(visible) do
        local noteId = type(entry) == "table" and entry.noteId or nil
        local layout = type(entry) == "table" and entry.layout or nil
        if noteId ~= nil and type(store.GetNote) == "function" and store:GetNote(noteId) then
            visibleIds[noteId] = true
            show_frame(self, noteId, layout)
        elseif noteId ~= nil then
            hide_and_remove_frame(self, noteId)
        end
    end

    for noteId, frame in pairs(self.framesByNoteId) do
        if not visibleIds[noteId] and is_frame_shown(frame) then
            frame.visible = false
            frame:Hide()
        end
    end
end

function Overlay:Refresh(noteId)
    local frame = self.framesByNoteId[noteId]
    if not frame then
        return
    end

    local store = self.addon and self.addon.store
    local note
    if store and type(store.GetNote) == "function" then
        note = store:GetNote(noteId)
    end
    if not note then
        hide_and_remove_frame(self, noteId)
        return
    end

    if frame.title and frame.title.SetText then
        frame.title:SetText(note.title or noteId)
    end
    update_body_width(frame)

    local markdown = self.addon and self.addon.Markdown
    local renderer = self.addon and self.addon.renderer
    if not markdown or type(markdown.Parse) ~= "function" or not renderer or type(renderer.Render) ~= "function" then
        return
    end

    local rows = markdown.Parse(note.id or noteId, note.markdown or "", note.checkedTasks)
    renderer:Render(frame.bodyContent, rows, function(taskKey, checked)
        local currentStore = self.addon and self.addon.store
        if currentStore and type(currentStore.SetTaskChecked) == "function" and currentStore:SetTaskChecked(noteId, taskKey, checked) then
            if type(self.addon.RefreshNote) == "function" then
                self.addon:RefreshNote(noteId)
            end
        end
    end)

    if frame.bodyScroll and type(frame.bodyScroll.UpdateScrollChildRect) == "function" then
        frame.bodyScroll:UpdateScrollChildRect()
    end
end

function Overlay:RefreshAll()
    local noteIds = {}
    for noteId in pairs(self.framesByNoteId) do
        noteIds[#noteIds + 1] = noteId
    end

    for _, noteId in ipairs(noteIds) do
        self:Refresh(noteId)
    end
end

function Overlay:Reset()
    local store = self.addon and self.addon.store
    if not store or type(store.ResetOverlays) ~= "function" then
        return
    end

    store:ResetOverlays()
    self:RestoreVisible()
end

addon.Overlay = Overlay
