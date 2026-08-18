local addonName, addon = ...

addon = addon or {}

local NoteManager = {}

local FRAME_NAME = "MarkdownNotesManagerFrame"
local FRAME_WIDTH = 640
local FRAME_HEIGHT = 420
local TITLE_BAR_HEIGHT = 32
local ACTION_HEIGHT = 24
local LIST_WIDTH = 190
local PREVIEW_WIDTH = 400
local CONTENT_HEIGHT = 332
local ROW_HEIGHT = 26
local FILTER_WIDTH = 180
local DELETE_DIALOG_NAME = "MARKDOWN_NOTES_CONFIRM_DELETE"

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

    return scroll, content
end

local function set_enabled(button, enabled)
    if button and button.SetEnabled then
        button:SetEnabled(enabled == true)
    end
end

local function register_delete_dialog(manager)
    if type(StaticPopupDialogs) ~= "table" then
        return
    end

    StaticPopupDialogs[DELETE_DIALOG_NAME] = {
        text = "Delete note \"%s\"?",
        button1 = "Delete",
        button2 = "Cancel",
        OnAccept = function(dialog, data)
            manager:ConfirmDelete(data or (dialog and dialog.data))
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

local function create_frame(manager)
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

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)
    title:SetText("Markdown Notes")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetSize(24, 24)
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local newButton = create_button(frame, "New", 54)
    newButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -44)

    local editButton = create_button(frame, "Edit", 54)
    editButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 70, -44)

    local deleteButton = create_button(frame, "Delete", 64)
    deleteButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 128, -44)

    local pinButton = create_button(frame, "Pin", 54)
    pinButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 196, -44)

    local unpinButton = create_button(frame, "Unpin", 64)
    unpinButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 254, -44)

    local titleFilter = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    titleFilter:SetSize(FILTER_WIDTH, ACTION_HEIGHT)
    titleFilter:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -44)
    titleFilter:SetAutoFocus(false)
    if titleFilter.SetTextInsets then
        titleFilter:SetTextInsets(6, 6, 0, 0)
    end
    titleFilter:SetText("")

    local listHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -72)
    listHeader:SetText("Notes")

    local previewHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 216, -72)
    previewHeader:SetText("Preview")

    local listScroll, listContent = create_scroll_area(frame, LIST_WIDTH, CONTENT_HEIGHT)
    listScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -88)

    local previewScroll, previewContent = create_scroll_area(frame, PREVIEW_WIDTH, CONTENT_HEIGHT)
    previewScroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 216, -88)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 208, -88)
    divider:SetSize(1, CONTENT_HEIGHT)
    divider:SetColorTexture(0.35, 0.35, 0.35, 0.7)

    manager.frame = frame
    manager.titleBar = titleBar
    manager.title = title
    manager.closeButton = closeButton
    manager.newButton = newButton
    manager.editButton = editButton
    manager.deleteButton = deleteButton
    manager.pinButton = pinButton
    manager.unpinButton = unpinButton
    manager.titleFilter = titleFilter
    manager.filter = titleFilter
    manager.listHeader = listHeader
    manager.previewHeader = previewHeader
    manager.listScroll = listScroll
    manager.listContent = listContent
    manager.previewScroll = previewScroll
    manager.previewContent = previewContent
    manager.divider = divider
end

function NoteManager:ClearPreview()
    local addon = self.addon
    if addon.renderer and addon.renderer.Clear then
        addon.renderer:Clear(self.previewContent)
    end
    if self.previewScroll and self.previewScroll.UpdateScrollChildRect then
        self.previewScroll:UpdateScrollChildRect()
    end
end

function NoteManager:UpdateActionStates()
    local addon = self.addon
    local hasSelection = false
    if self.selectedId and addon.store and addon.store.GetNote then
        hasSelection = addon.store:GetNote(self.selectedId) ~= nil
    end

    if not hasSelection then
        self.selectedId = nil
    end

    set_enabled(self.editButton, hasSelection)
    set_enabled(self.deleteButton, hasSelection)
    set_enabled(self.pinButton, hasSelection)
    set_enabled(self.unpinButton, hasSelection)
end

function NoteManager:UpdateRowSelection()
    for _, row in ipairs(self.listRows) do
        if row.noteId then
            local selected = row.noteId == self.selectedId
            row.selected = selected
            if row.SetAlpha then
                row:SetAlpha(selected and 1 or 0.85)
            end
        end
    end
end

local function ensure_list_row(manager, index)
    local row = manager.listRows[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, manager.listContent, "UIPanelButtonTemplate")
    row:SetSize(LIST_WIDTH, ROW_HEIGHT)
    row:RegisterForClicks("AnyUp")
    row:SetScript("OnClick", function(button)
        manager:Select(button.noteId)
    end)
    manager.listRows[index] = row
    return row
end

function NoteManager:RefreshList()
    local addon = self.addon
    local filterText = ""
    if self.titleFilter and self.titleFilter.GetText then
        filterText = self.titleFilter:GetText() or ""
    end

    local notes = {}
    if addon.store and addon.store.ListNotes then
        notes = addon.store:ListNotes(filterText) or {}
    end

    local selectedInResult = false
    for index, note in ipairs(notes) do
        local row = ensure_list_row(self, index)
        row.noteId = note.id
        row:SetText(note.title or "")
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.listContent, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        row:SetSize(LIST_WIDTH, ROW_HEIGHT)
        row:Show()

        if note.id == self.selectedId then
            selectedInResult = true
        end
    end

    for index = #notes + 1, #self.listRows do
        local row = self.listRows[index]
        row.noteId = nil
        row:Hide()
    end

    self.listContent:SetHeight(math.max(1, #notes * ROW_HEIGHT))
    if self.listScroll and self.listScroll.UpdateScrollChildRect then
        self.listScroll:UpdateScrollChildRect()
    end

    if self.selectedId == nil or not selectedInResult then
        self.selectedId = nil
    end
    self:UpdateActionStates()
    self:UpdateRowSelection()

    if not self.selectedId then
        self:ClearPreview()
    end
end

function NoteManager:RefreshPreview(noteId)
    local addon = self.addon
    local selectedId = noteId or self.selectedId
    if not selectedId or not addon.store or not addon.store.GetNote then
        self:ClearPreview()
        return
    end

    local note = addon.store:GetNote(selectedId)
    if not note then
        if self.selectedId == selectedId then
            self.selectedId = nil
            self:UpdateActionStates()
            self:UpdateRowSelection()
        end
        self:ClearPreview()
        return
    end

    local rows = addon.Markdown.Parse(note.id, note.markdown, note.checkedTasks)
    addon.renderer:Render(self.previewContent, rows, function(taskKey, checked)
        if addon.store:SetTaskChecked(note.id, taskKey, checked) then
            addon:RefreshNote(note.id)
        end
    end)

    if self.previewScroll and self.previewScroll.UpdateScrollChildRect then
        self.previewScroll:UpdateScrollChildRect()
    end
end

function NoteManager:Select(noteId)
    local addon = self.addon
    local note
    if addon.store and addon.store.GetNote then
        note = addon.store:GetNote(noteId)
    end

    if not note then
        self.selectedId = nil
        self:UpdateActionStates()
        self:UpdateRowSelection()
        self:ClearPreview()
        return
    end

    self.selectedId = note.id or noteId
    self:UpdateActionStates()
    self:UpdateRowSelection()
    self:RefreshPreview(self.selectedId)
end

function NoteManager:Open()
    self:RefreshList()
    self.frame:Show()
end

function NoteManager:Close()
    self.frame:Hide()
end

function NoteManager:Toggle()
    if self.frame:IsShown() then
        self:Close()
    else
        self:Open()
    end
end

function NoteManager:RequestDelete()
    local addon = self.addon
    local noteId = self.selectedId
    if not noteId or not addon.store or not addon.store.GetNote then
        return
    end

    local note = addon.store:GetNote(noteId)
    if not note then
        self:Select(nil)
        return
    end

    if StaticPopup_Show then
        StaticPopup_Show(DELETE_DIALOG_NAME, note.title or "", nil, noteId)
    end
end

function NoteManager:ConfirmDelete(noteId)
    local addon = self.addon
    noteId = noteId or self.selectedId
    if not noteId or not addon.store or not addon.store.DeleteNote then
        return
    end

    if addon.store:DeleteNote(noteId) then
        if self.selectedId == noteId then
            self.selectedId = nil
        end
        self:UpdateActionStates()
        self:UpdateRowSelection()
        addon:RefreshAll()
    end
end

function NoteManager:PinSelected()
    local addon = self.addon
    if self.selectedId and addon.overlay and addon.overlay.Pin then
        addon.overlay:Pin(self.selectedId)
    end
end

function NoteManager:UnpinSelected()
    local addon = self.addon
    if self.selectedId and addon.overlay and addon.overlay.Unpin then
        addon.overlay:Unpin(self.selectedId)
    end
end

function NoteManager.Create(addon)
    local manager = setmetatable({
        addon = addon,
        selectedId = nil,
        listRows = {},
    }, { __index = NoteManager })

    create_frame(manager)

    manager.closeButton:SetScript("OnClick", function()
        manager:Close()
    end)
    manager.newButton:SetScript("OnClick", function()
        addon.editor:OpenNew()
    end)
    manager.editButton:SetScript("OnClick", function()
        if manager.selectedId then
            addon.editor:Open(manager.selectedId)
        end
    end)
    manager.deleteButton:SetScript("OnClick", function()
        manager:RequestDelete()
    end)
    manager.pinButton:SetScript("OnClick", function()
        manager:PinSelected()
    end)
    manager.unpinButton:SetScript("OnClick", function()
        manager:UnpinSelected()
    end)
    manager.titleFilter:SetScript("OnTextChanged", function()
        manager:RefreshList()
    end)

    register_delete_dialog(manager)
    manager.frame:Hide()
    manager:UpdateActionStates()
    manager:RefreshList()

    return manager
end

addon.NoteManager = NoteManager
