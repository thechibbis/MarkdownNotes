local addonName, addon = ...

addon = addon or {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(_, event, loadedAddonName)
    if event == "ADDON_LOADED" and loadedAddonName == addonName then
        addon.store = addon.Storage.Create(MarkdownNotesDB, time)
        MarkdownNotesDB = addon.store:GetDatabase()
    elseif event == "PLAYER_LOGIN" then
        addon.renderer = addon.Renderer.Create()
        addon.overlay = addon.Overlay.Create(addon)
        addon.editor = addon.Editor.Create(addon)
        addon.manager = addon.NoteManager.Create(addon)
        addon.Commands.Register(addon)
        addon.overlay:RestoreVisible()
    end
end)

function addon:RefreshNote(noteId)
    if self.manager then
        self.manager:RefreshList()
        self.manager:RefreshPreview(noteId)
    end
    if self.overlay then
        self.overlay:Refresh(noteId)
    end
end

function addon:RefreshAll()
    if self.manager then
        self.manager:RefreshList()
        self.manager:RefreshPreview()
    end
    if self.overlay then
        self.overlay:RefreshAll()
    end
end
