return function(addon, Test, loadAddonFile)
    local function new_widget(objectType, parent, template)
        local widget = {
            objectType = objectType,
            parent = parent,
            template = template,
            width = 0,
            height = 0,
            shown = false,
            enabled = true,
            alpha = 1,
            movable = false,
            resizable = false,
            mouseEnabled = false,
            scripts = {},
            children = {},
            calls = {},
            text = "",
            checked = false,
        }

        function widget:GetObjectType()
            return self.objectType
        end

        function widget:SetSize(width, height)
            self.width = width
            self.height = height
            local callback = self.scripts.OnSizeChanged
            if callback then
                callback(self, width, height)
            end
        end

        function widget:SetWidth(width)
            self.width = width
        end

        function widget:GetWidth()
            return self.width
        end

        function widget:SetHeight(height)
            self.height = height
        end

        function widget:GetHeight()
            return self.height
        end

        function widget:SetPoint(...)
            self.point = { ... }
        end

        function widget:GetPoint()
            if not self.point then
                return nil
            end
            return self.point[1], self.point[2], self.point[3], self.point[4], self.point[5]
        end

        function widget:ClearAllPoints()
            self.point = nil
        end

        function widget:Show()
            self.shown = true
        end

        function widget:Hide()
            self.shown = false
        end

        function widget:IsShown()
            return self.shown
        end

        function widget:SetScript(scriptType, callback)
            self.scripts[scriptType] = callback
        end

        function widget:GetScript(scriptType)
            return self.scripts[scriptType]
        end

        function widget:RegisterEvent()
        end

        function widget:RegisterForDrag(...)
            self.dragButtons = { ... }
        end

        function widget:RegisterForClicks(...)
            self.registeredClicks = { ... }
        end

        function widget:SetText(value)
            self.text = value or ""
        end

        function widget:GetText()
            return self.text
        end

        function widget:SetEnabled(value)
            self.enabled = value == true
        end

        function widget:IsEnabled()
            return self.enabled
        end

        function widget:SetAlpha(value)
            self.alpha = value
        end

        function widget:SetAutoFocus(value)
            self.autoFocus = value
        end

        function widget:SetTextInsets(...)
            self.textInsets = { ... }
        end

        function widget:SetBackdrop(value)
            self.backdrop = value
        end

        function widget:SetBackdropColor(...)
            self.backdropColor = { ... }
        end

        function widget:SetBackdropBorderColor(...)
            self.backdropBorderColor = { ... }
        end

        function widget:SetFrameStrata(value)
            self.frameStrata = value
        end

        function widget:SetToplevel(value)
            self.toplevel = value
        end

        function widget:SetClampedToScreen(value)
            self.clampedToScreen = value
        end

        function widget:EnableMouse(value)
            self.mouseEnabled = value == true
        end

        function widget:SetMovable(value)
            self.movable = value == true
        end

        function widget:SetResizable(value)
            self.resizable = value == true
        end

        function widget:SetResizeBounds(...)
            self.resizeBounds = { ... }
        end

        function widget:StartMoving()
            self.calls.startMoving = (self.calls.startMoving or 0) + 1
        end

        function widget:StartSizing(anchor)
            self.calls.startSizing = (self.calls.startSizing or 0) + 1
            self.sizingAnchor = anchor
        end

        function widget:StopMovingOrSizing()
            self.calls.stopMovingOrSizing = (self.calls.stopMovingOrSizing or 0) + 1
        end

        function widget:SetScrollChild(child)
            self.scrollChild = child
        end

        function widget:UpdateScrollChildRect()
            self.calls.updateScrollChildRect = (self.calls.updateScrollChildRect or 0) + 1
        end

        function widget:SetNormalTexture(value)
            self.normalTexture = value
        end

        function widget:SetHighlightTexture(value)
            self.highlightTexture = value
        end

        function widget:SetChecked(value)
            self.checked = value == true
        end

        function widget:GetChecked()
            return self.checked == true
        end

        function widget:SetWordWrap(value)
            self.wordWrap = value
        end

        function widget:SetJustifyH(value)
            self.justifyH = value
        end

        function widget:SetJustifyV(value)
            self.justifyV = value
        end

        function widget:SetFontObject(value)
            self.fontObject = value
        end

        function widget:SetTextColor(...)
            self.textColor = { ... }
        end

        function widget:SetColorTexture(...)
            self.colorTexture = { ... }
        end

        function widget:GetStringHeight()
            local charactersPerLine = math.max(1, math.floor(math.max(1, self.width) / 6))
            local lineCount = math.max(1, math.ceil(#self.text / charactersPerLine))
            local explicitLines = 1
            for _ in string.gmatch(self.text, "\n") do
                explicitLines = explicitLines + 1
            end
            return math.max(lineCount, explicitLines) * 10
        end

        function widget:GetEffectiveScale()
            return 1
        end

        function widget:CreateFontString()
            local child = new_widget("FontString", self)
            self.children[#self.children + 1] = child
            return child
        end

        function widget:CreateTexture()
            local child = new_widget("Texture", self)
            self.children[#self.children + 1] = child
            return child
        end

        return widget
    end

    local function with_fake_widgets(callback)
        local previousCreateFrame = _G.CreateFrame
        local previousUIParent = _G.UIParent
        local previousStaticPopupDialogs = _G.StaticPopupDialogs
        local previousStaticPopupShow = _G.StaticPopup_Show
        local created = {}

        _G.UIParent = new_widget("Frame", nil)
        _G.UIParent:SetSize(1024, 768)
        _G.StaticPopupDialogs = {}
        _G.StaticPopup_Show = nil
        _G.CreateFrame = function(objectType, _, parent, template)
            local widget = new_widget(objectType, parent, template)
            created[#created + 1] = widget
            if parent and parent.children then
                parent.children[#parent.children + 1] = widget
            end
            return widget
        end

        local ok, message = pcall(function()
            callback(created, _G.UIParent)
        end)

        _G.CreateFrame = previousCreateFrame
        _G.UIParent = previousUIParent
        _G.StaticPopupDialogs = previousStaticPopupDialogs
        _G.StaticPopup_Show = previousStaticPopupShow

        if not ok then
            error(message, 0)
        end
    end

    local function new_renderer_spy()
        local renderer = {
            renders = {},
        }

        function renderer:Clear(parent)
            self.clearedParent = parent
        end

        function renderer:Render(content, rows, onTaskClick)
            self.renders[#self.renders + 1] = {
                content = content,
                rows = rows,
                onTaskClick = onTaskClick,
            }
        end

        return renderer
    end

    local unsafeTitle = "|cffff0000Raid|r |TInterface\\Icons\\INV_Misc_QuestionMark:16|t |Hitem:1|hLink|h"

    Test.run("NoteManager escapes titles in list rows", function()
        with_fake_widgets(function()
            local store = addon.Storage.Create({}, function() return 100 end)
            local note = store:CreateNote(unsafeTitle, "body")
            local runtime = {
                store = store,
                Markdown = addon.Markdown,
                renderer = new_renderer_spy(),
            }

            local manager = addon.NoteManager.Create(runtime)

            Test.equal("escaped manager list title", manager.listRows[1].text, addon.Renderer.EscapeText(note.title))
        end)
    end)

    Test.run("NoteManager escapes titles passed to delete confirmation", function()
        with_fake_widgets(function()
            local shownArguments
            _G.StaticPopup_Show = function(...)
                shownArguments = { ... }
            end

            local store = addon.Storage.Create({}, function() return 100 end)
            local note = store:CreateNote(unsafeTitle, "body")
            local runtime = {
                store = store,
                Markdown = addon.Markdown,
                renderer = new_renderer_spy(),
            }

            local manager = addon.NoteManager.Create(runtime)
            manager:Select(note.id)
            manager:RequestDelete()

            Test.equal("confirmation dialog name", shownArguments[1], "MARKDOWN_NOTES_CONFIRM_DELETE")
            Test.equal("escaped confirmation title", shownArguments[2], addon.Renderer.EscapeText(note.title))
            Test.equal("confirmation note id", shownArguments[4], note.id)
        end)
    end)

    Test.run("Overlay escapes its title bar text", function()
        with_fake_widgets(function()
            local store = addon.Storage.Create({}, function() return 100 end)
            local note = store:CreateNote(unsafeTitle, "body")
            local runtime = {
                store = store,
                Markdown = addon.Markdown,
                renderer = new_renderer_spy(),
            }

            local overlays = addon.Overlay.Create(runtime)
            Test.truthy("pin note", overlays:Pin(note.id))

            local frame = overlays.framesByNoteId[note.id]
            Test.equal("escaped overlay title", frame.title.text, addon.Renderer.EscapeText(note.title))
        end)
    end)

    Test.run("RefreshNote keeps manager preview aligned with selected note", function()
        with_fake_widgets(function()

            local store = addon.Storage.Create({}, function() return 100 end)
            local selectedNote = store:CreateNote("Selected", "selected body")
            local overlayNote = store:CreateNote("Overlay", "- [ ] overlay task")
            local renderer = new_renderer_spy()
            local runtime = {
                store = store,
                Markdown = addon.Markdown,
                renderer = renderer,
            }
            loadAddonFile("Core.lua", runtime)

            runtime.manager = addon.NoteManager.Create(runtime)
            runtime.overlay = addon.Overlay.Create(runtime)
            runtime.manager:Select(selectedNote.id)
            Test.equal("initial selection", runtime.manager.selectedId, selectedNote.id)
            Test.equal("initial preview body", renderer.renders[#renderer.renders].rows[1].segments[1].text, "selected body")

            Test.truthy("pin unselected overlay note", runtime.overlay:Pin(overlayNote.id))
            local overlayFrame = runtime.overlay.framesByNoteId[overlayNote.id]
            local overlayRender
            for index = #renderer.renders, 1, -1 do
                if renderer.renders[index].content == overlayFrame.bodyContent then
                    overlayRender = renderer.renders[index]
                    break
                end
            end
            Test.truthy("overlay render callback exists", overlayRender ~= nil)

            local taskKey = overlayNote.id .. ":overlay task:1"
            overlayRender.onTaskClick(taskKey, true)

            Test.equal("selection remains aligned", runtime.manager.selectedId, selectedNote.id)
            Test.equal("edit action remains enabled", runtime.manager.editButton.enabled, true)
            Test.equal("delete action remains enabled", runtime.manager.deleteButton.enabled, true)
            Test.equal("pin action remains enabled", runtime.manager.pinButton.enabled, true)
            Test.equal("unpin action remains enabled", runtime.manager.unpinButton.enabled, true)

            local managerPreview
            local refreshedOverlay
            for index = #renderer.renders, 1, -1 do
                if not managerPreview and renderer.renders[index].content == runtime.manager.previewContent then
                    managerPreview = renderer.renders[index]
                end
                if not refreshedOverlay and renderer.renders[index].content == overlayFrame.bodyContent then
                    refreshedOverlay = renderer.renders[index]
                end
                if managerPreview and refreshedOverlay then
                    break
                end
            end

            Test.truthy("manager preview was refreshed", managerPreview ~= nil)
            Test.equal("manager preview remains selected", managerPreview.rows[1].segments[1].text, "selected body")
            Test.equal("overlay task state saved", store:IsTaskChecked(overlayNote.id, taskKey), true)
            Test.truthy("affected overlay was refreshed", refreshedOverlay ~= nil)
            Test.equal("affected overlay shows checked task", refreshedOverlay.rows[1].checked, true)
        end)
    end)
end
