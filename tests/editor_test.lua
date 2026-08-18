return function(addon, Test)
    local function new_widget(objectType, name, parent, template)
        local widget = {
            objectType = objectType,
            name = name,
            parent = parent,
            template = template,
            width = 0,
            height = 0,
            shown = false,
            scripts = {},
            children = {},
            text = "",
            calls = {},
        }

        function widget:GetObjectType()
            return self.objectType
        end

        function widget:SetSize(width, height)
            self.width = width
            self.height = height
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

        function widget:ClearAllPoints()
            self.point = nil
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
            self.mouseEnabled = value
        end

        function widget:SetMovable(value)
            self.movable = value
        end

        function widget:RegisterForDrag(...)
            self.dragButtons = { ... }
        end

        function widget:StartMoving()
            self.moving = true
        end

        function widget:StopMovingOrSizing()
            self.moving = false
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

        function widget:SetText(value)
            self.text = value or ""
            self.calls.setText = (self.calls.setText or 0) + 1
            if self.scripts.OnTextChanged then
                self.scripts.OnTextChanged(self)
            end
        end

        function widget:GetText()
            return self.text
        end

        function widget:GetNumLines()
            if self.text == "" then
                return 1
            end

            local lineCount = 1
            for _ in string.gmatch(self.text, "\n") do
                lineCount = lineCount + 1
            end
            return lineCount
        end

        function widget:SetMultiLine(value)
            self.multiLine = value
        end

        function widget:SetAutoFocus(value)
            self.autoFocus = value
        end

        function widget:SetFontObject(value)
            self.fontObject = value
        end

        function widget:SetTextInsets(...)
            self.textInsets = { ... }
        end

        function widget:SetJustifyH(value)
            self.justifyH = value
        end

        function widget:SetJustifyV(value)
            self.justifyV = value
        end

        function widget:SetWordWrap(value)
            self.wordWrap = value
        end

        function widget:SetScrollChild(child)
            self.scrollChild = child
        end

        function widget:UpdateScrollChildRect()
            self.calls.updateScrollChildRect = (self.calls.updateScrollChildRect or 0) + 1
        end

        function widget:RegisterForClicks(...)
            self.registeredClicks = { ... }
        end

        function widget:SetEnabled(value)
            self.enabled = value
        end

        function widget:CreateFontString(childName, drawLayer, fontObject)
            local child = new_widget("FontString", childName, self, fontObject)
            child.drawLayer = drawLayer
            self.children[#self.children + 1] = child
            return child
        end

        function widget:CreateTexture(childName, drawLayer)
            local child = new_widget("Texture", childName, self)
            child.drawLayer = drawLayer
            self.children[#self.children + 1] = child
            return child
        end

        function widget:SetColorTexture(...)
            self.colorTexture = { ... }
        end

        function widget:SetTextColor(...)
            self.textColor = { ... }
        end

        return widget
    end

    local previousCreateFrame = _G.CreateFrame
    local previousUIParent = _G.UIParent
    local previousChatFontNormal = _G.ChatFontNormal
    local previousGameFontHighlight = _G.GameFontHighlight

    _G.UIParent = new_widget("Frame", "UIParent")
    _G.UIParent:SetSize(1024, 768)
    _G.ChatFontNormal = "ChatFontNormal"
    _G.GameFontHighlight = "GameFontHighlight"
    _G.CreateFrame = function(objectType, name, parent, template)
        local widget = new_widget(objectType, name, parent, template)
        if parent and parent.children then
            parent.children[#parent.children + 1] = widget
        end
        return widget
    end

    local loadAddonFile = dofile("tests/load_module.lua")
    loadAddonFile("Editor.lua", addon)

    local function new_runtime()
        local store = addon.Storage.Create({}, function() return 100 end)
        local renderCalls = {}
        local events = {}
        local renderer = {}
        local manager = {}

        function renderer:Render(parent, rows, onTaskClick)
            renderCalls[#renderCalls + 1] = {
                parent = parent,
                rows = rows,
                onTaskClick = onTaskClick,
            }
        end

        function manager:Select(noteId)
            self.selectedId = noteId
            events[#events + 1] = "select:" .. noteId
        end

        local runtime = {
            Markdown = addon.Markdown,
            store = store,
            renderer = renderer,
            manager = manager,
        }

        function runtime:RefreshNote(noteId)
            events[#events + 1] = "refreshNote:" .. noteId
        end

        function runtime:RefreshAll()
            events[#events + 1] = "refreshAll"
        end

        return runtime, store, renderCalls, events, manager
    end

    Test.run("Editor constructs the fixed frame and fields", function()
        local runtime = new_runtime()
        local editor = addon.Editor.Create(runtime)

        Test.equal("editor frame name", editor.frame.name, "MarkdownNotesEditorFrame")
        Test.equal("editor width", editor.frame:GetWidth(), 720)
        Test.equal("editor height", editor.frame:GetHeight(), 500)
        Test.equal("editor template", editor.frame.template, "BackdropTemplate")
        Test.equal("editor initially hidden", editor.frame:IsShown(), false)
        Test.equal("source is multiline", editor.source.multiLine, true)
        Test.equal("source does not autofocus", editor.source.autoFocus, false)
        Test.equal("source has no unsupported string-height method", editor.source.GetStringHeight, nil)
        Test.truthy("source exposes supported line count", editor.source.GetNumLines ~= nil)
    end)

    Test.run("Editor grows the source child beyond the viewport", function()
        local runtime = new_runtime()
        local editor = addon.Editor.Create(runtime)
        local lines = {}
        for index = 1, 40 do
            lines[index] = "line " .. tostring(index)
        end

        editor:OpenNew()
        editor.source:SetText(table.concat(lines, "\n"))

        Test.truthy("long source grows child height", editor.source:GetHeight() > editor.sourceScroll:GetHeight())
    end)

    Test.run("Editor keeps preview task state local until Save", function()
        local runtime, store, renderCalls, events = new_runtime()
        local editor = addon.Editor.Create(runtime)

        editor:OpenNew()
        editor.title:SetText("Draft")
        editor.source:SetText("- [ ] Draft task")
        local beforeClickRenders = #renderCalls
        renderCalls[#renderCalls].onTaskClick("draft:draft task:1", true)

        Test.equal("new draft preview state is local", editor.previewCheckedTasks["draft:draft task:1"], true)
        Test.equal("draft task click rerenders preview", #renderCalls, beforeClickRenders + 1)
        Test.equal("draft task click does not write storage", #store:ListNotes(), 0)
        Test.equal("draft task click does not refresh saved consumers", #events, 0)

        editor:Cancel()
        Test.equal("cancel leaves draft storage empty", #store:ListNotes(), 0)
    end)

    Test.run("Editor cancels existing preview state without storage mutation", function()
        local runtime, store, renderCalls = new_runtime()
        local editor = addon.Editor.Create(runtime)
        local note = store:CreateNote("Existing", "- [ ] Existing task")
        local taskKey = note.id .. ":existing task:1"

        editor:Open(note.id)
        Test.equal("existing state starts unchecked", editor.previewCheckedTasks[taskKey], nil)
        renderCalls[#renderCalls].onTaskClick(taskKey, true)

        Test.equal("existing preview state is local", editor.previewCheckedTasks[taskKey], true)
        Test.equal("existing task is not stored before save", store:IsTaskChecked(note.id, taskKey), false)
        editor:Close()
        Test.equal("close preserves saved unchecked state", store:IsTaskChecked(note.id, taskKey), false)
    end)

    Test.run("Editor saves local task state for new and existing notes", function()
        local runtime, store, renderCalls, events, manager = new_runtime()
        local editor = addon.Editor.Create(runtime)

        editor:OpenNew()
        editor.title:SetText("Created")
        editor.source:SetText("- [ ] New task")
        renderCalls[#renderCalls].onTaskClick("draft:new task:1", true)
        Test.equal("new task state stays local before create", editor.previewCheckedTasks["draft:new task:1"], true)
        editor:Save()

        local created = store:ListNotes()[1]
        local createdTaskKey = created.id .. ":new task:1"
        Test.equal("new task state saves after create", store:IsTaskChecked(created.id, createdTaskKey), true)
        Test.equal("new save selects note", manager.selectedId, created.id)
        Test.equal("new save refreshes all", events[#events], "refreshAll")

        local existing = store:CreateNote("Update me", "- [ ] Updated task")
        local existingTaskKey = existing.id .. ":updated task:1"
        editor:Open(existing.id)
        renderCalls[#renderCalls].onTaskClick(existingTaskKey, true)
        Test.equal("existing task remains local before update", store:IsTaskChecked(existing.id, existingTaskKey), false)
        editor:Save()

        Test.equal("existing task state saves after update", store:IsTaskChecked(existing.id, existingTaskKey), true)
        Test.equal("update save selects note", manager.selectedId, existing.id)
        Test.equal("update save refreshes all", events[#events], "refreshAll")
    end)

    _G.CreateFrame = previousCreateFrame
    _G.UIParent = previousUIParent
    _G.ChatFontNormal = previousChatFontNormal
    _G.GameFontHighlight = previousGameFontHighlight
end
