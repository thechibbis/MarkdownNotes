local addonName, addon = ...

addon = addon or {}

local Editor = {}

local FRAME_NAME = "MarkdownNotesEditorFrame"
local FRAME_WIDTH = 720
local FRAME_HEIGHT = 500
local TITLE_BAR_HEIGHT = 32
local ACTION_HEIGHT = 24
local SOURCE_WIDTH = 330
local PREVIEW_WIDTH = 330
local CONTENT_HEIGHT = 370
local SOURCE_FONT = _G.ChatFontNormal or _G.GameFontHighlight

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

local function as_string(value)
    if value == nil then
        return ""
    end
    if type(value) == "string" then
        return value
    end
    return tostring(value)
end

local function trim(value)
    value = as_string(value)
    value = string.gsub(value, "^%s+", "")
    value = string.gsub(value, "%s+$", "")
    return value
end

local function create_button(parent, text, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, ACTION_HEIGHT)
    button:SetText(text)
    button:RegisterForClicks("AnyUp")
    return button
end

local function create_scroll_area(parent, width, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetSize(width, height)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    scroll:Show()
    content:Show()

    return scroll, content
end

local function create_frame(editor)
    local frame = CreateFrame("Frame", FRAME_NAME, UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.96)
    frame:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    titleBar:SetHeight(TITLE_BAR_HEIGHT)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
    heading:SetText("Markdown Editor")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetSize(24, 24)
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local titleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -48)
    titleLabel:SetText("Title")

    local title = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    title:SetSize(280, ACTION_HEIGHT)
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -44)
    title:SetAutoFocus(false)
    if title.SetTextInsets then
        title:SetTextInsets(6, 6, 0, 0)
    end
    if title.SetFontObject and SOURCE_FONT then
        title:SetFontObject(SOURCE_FONT)
    end

    local sourceLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sourceLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -78)
    sourceLabel:SetText("Markdown source")

    local previewLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 374, -78)
    previewLabel:SetText("Preview")

    local sourceScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    sourceScroll:SetSize(SOURCE_WIDTH, CONTENT_HEIGHT)
    sourceScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -96)

    local source = CreateFrame("EditBox", nil, sourceScroll)
    source:SetPoint("TOPLEFT", sourceScroll, "TOPLEFT", 6, -6)
    source:SetWidth(SOURCE_WIDTH - 24)
    source:SetHeight(CONTENT_HEIGHT - 12)
    source:SetMultiLine(true)
    source:SetAutoFocus(false)
    if source.SetFontObject and SOURCE_FONT then
        source:SetFontObject(SOURCE_FONT)
    end
    if source.SetTextInsets then
        source:SetTextInsets(4, 4, 4, 4)
    end
    if source.SetJustifyH then
        source:SetJustifyH("LEFT")
    end
    if source.SetJustifyV then
        source:SetJustifyV("TOP")
    end
    if source.SetWordWrap then
        source:SetWordWrap(true)
    end
    source:SetText("")
    sourceScroll:SetScrollChild(source)
    sourceScroll:Show()
    source:Show()

    local previewScroll, previewContent = create_scroll_area(frame, PREVIEW_WIDTH, CONTENT_HEIGHT)
    previewScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 368, -96)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 356, -96)
    divider:SetSize(1, CONTENT_HEIGHT)
    divider:SetColorTexture(0.35, 0.35, 0.35, 0.7)

    local saveButton = create_button(frame, "Save", 76)
    saveButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)

    local cancelButton = create_button(frame, "Cancel", 76)
    cancelButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 100, 12)

    local validation = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    validation:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 198, 18)
    validation:SetTextColor(1, 0.25, 0.25, 1)
    validation:SetText("")
    validation:Hide()

    editor.frame = frame
    editor.titleBar = titleBar
    editor.heading = heading
    editor.closeButton = closeButton
    editor.titleLabel = titleLabel
    editor.title = title
    editor.titleEditBox = title
    editor.sourceLabel = sourceLabel
    editor.sourceScroll = sourceScroll
    editor.source = source
    editor.sourceEditBox = source
    editor.previewLabel = previewLabel
    editor.previewScroll = previewScroll
    editor.previewContent = previewContent
    editor.divider = divider
    editor.saveButton = saveButton
    editor.cancelButton = cancelButton
    editor.validation = validation

    frame:Hide()
end

function Editor:ClearValidation()
    if self.validation then
        self.validation:SetText("")
        self.validation:Hide()
    end
end

function Editor:RefreshPreview()
    local addon = self.addon
    if not addon or not addon.Markdown or not addon.Markdown.Parse or not addon.renderer or not addon.renderer.Render then
        return
    end
    if self.previewScroll and self.previewScroll.IsShown and not self.previewScroll:IsShown() then
        return
    end

    local noteId = "draft"
    local checkedTasks = {}
    if self.draftNoteId and addon.store and addon.store.GetNote then
        noteId = self.draftNoteId
        local note = addon.store:GetNote(self.draftNoteId)
        if note then
            noteId = note.id or self.draftNoteId
            checkedTasks = note.checkedTasks or {}
        end
    end

    local source = ""
    if self.source and self.source.GetText then
        source = self.source:GetText() or ""
    end

    local rows = addon.Markdown.Parse(noteId, source, checkedTasks)
    addon.renderer:Render(self.previewContent, rows, function(taskKey, checked)
        if self.draftNoteId and addon.store and addon.store.SetTaskChecked then
            if addon.store:SetTaskChecked(self.draftNoteId, taskKey, checked) and addon.RefreshNote then
                addon:RefreshNote(self.draftNoteId)
            end
        end
    end)

    if self.previewScroll and self.previewScroll.UpdateScrollChildRect then
        self.previewScroll:UpdateScrollChildRect()
    end
end

function Editor:OpenNew()
    self.draftNoteId = nil
    self:ClearValidation()

    self.suppressTextChanged = true
    self.title:SetText("New note")
    self.source:SetText("")
    self.suppressTextChanged = false

    self.frame:Show()
    self.previewScroll:Show()
    self:RefreshPreview()
end

function Editor:Open(noteId)
    local addon = self.addon
    if not addon or not addon.store or not addon.store.GetNote then
        return
    end

    local note = addon.store:GetNote(noteId)
    if not note then
        return
    end

    self.draftNoteId = note.id or noteId
    self:ClearValidation()

    self.suppressTextChanged = true
    self.title:SetText(note.title or "")
    self.source:SetText(note.markdown or "")
    self.suppressTextChanged = false

    self.frame:Show()
    self.previewScroll:Show()
    self:RefreshPreview()
end

function Editor:Save()
    local title = trim(self.title:GetText())
    local source = self.source:GetText() or ""

    if title == "" then
        self.validation:SetText("Title is required.")
        self.validation:Show()
        return nil, "empty-title"
    end

    local addon = self.addon
    local note, err
    if self.draftNoteId then
        note, err = addon.store:UpdateNote(self.draftNoteId, title, source)
    else
        note, err = addon.store:CreateNote(title, source)
    end

    if note then
        self:Close()
        if addon.manager and addon.manager.Select then
            addon.manager:Select(note.id)
        end
        if addon.RefreshAll then
            addon:RefreshAll()
        end
        return note, nil
    end

    local message = "Unable to save note."
    if err == "empty-title" then
        message = "Title is required."
    elseif err == "missing-note" then
        message = "The note no longer exists."
    end
    self.validation:SetText(message)
    self.validation:Show()
    return nil, err
end

function Editor:Cancel()
    self:Close()
end

function Editor:Close()
    self.frame:Hide()
end

function Editor.Create(addon)
    local editor = setmetatable({
        addon = addon,
        draftNoteId = nil,
        suppressTextChanged = false,
    }, { __index = Editor })

    create_frame(editor)

    editor.title:SetScript("OnTextChanged", function()
        editor:ClearValidation()
        if not editor.suppressTextChanged then
            editor:RefreshPreview()
        end
    end)
    editor.source:SetScript("OnTextChanged", function()
        if editor.source.GetStringHeight and editor.source.SetHeight then
            editor.source:SetHeight(math.max(CONTENT_HEIGHT - 12, editor.source:GetStringHeight() + 8))
        end
        if editor.sourceScroll and editor.sourceScroll.UpdateScrollChildRect then
            editor.sourceScroll:UpdateScrollChildRect()
        end
        if not editor.suppressTextChanged then
            editor:RefreshPreview()
        end
    end)
    editor.saveButton:SetScript("OnClick", function()
        editor:Save()
    end)
    editor.cancelButton:SetScript("OnClick", function()
        editor:Cancel()
    end)
    editor.closeButton:SetScript("OnClick", function()
        editor:Close()
    end)

    return editor
end

addon.Editor = Editor
