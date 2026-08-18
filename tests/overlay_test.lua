return function(addon, Test)
    local function new_widget(objectType, parent, template)
        local widget = {
            objectType = objectType,
            parent = parent,
            template = template,
            width = 0,
            height = 0,
            shown = false,
            scripts = {},
            children = {},
            calls = {},
        }

        function widget:GetObjectType()
            return self.objectType
        end

        function widget:SetSize(width, height)
            self.width = width
            self.height = height
            if self.scripts.OnSizeChanged then
                self.scripts.OnSizeChanged(self, width, height)
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

        function widget:EnableMouse(value)
            self.mouseEnabled = value
        end

        function widget:RegisterForDrag(...)
            self.dragButtons = { ... }
        end

        function widget:RegisterForClicks(...)
            self.registeredClicks = { ... }
        end

        function widget:SetMovable(value)
            self.movable = value
        end

        function widget:SetResizable(value)
            self.resizable = value
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

        function widget:SetText(value)
            self.text = value or ""
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

        function widget:GetEffectiveScale()
            return 1
        end

        function widget:CreateFontString()
            local child = new_widget("FontString", self)
            self.children[#self.children + 1] = child
            return child
        end

        return widget
    end

    local function with_fake_widgets(callback)
        local previousCreateFrame = _G.CreateFrame
        local previousUIParent = _G.UIParent
        local created = {}

        _G.UIParent = new_widget("Frame", nil)
        _G.UIParent:SetSize(1024, 768)
        _G.CreateFrame = function(objectType, _, parent, template)
            local widget = new_widget(objectType, parent, template)
            created[#created + 1] = widget
            if parent and parent.children then
                parent.children[#parent.children + 1] = widget
            end
            return widget
        end

        local success, message = pcall(function()
            callback(created, _G.UIParent)
        end)

        _G.CreateFrame = previousCreateFrame
        _G.UIParent = previousUIParent

        if not success then
            error(message, 0)
        end
    end

    Test.run("Overlay persists native note windows and checklist state", function()
        with_fake_widgets(function(created, fakeUIParent)
            local store = addon.Storage.Create({}, function() return 100 end)
            local firstNote = store:CreateNote("First", "- [ ] First task")
            local secondNote = store:CreateNote("Second", "second")
            local renderCalls = {}
            local refreshes = {}
            local runtime = {
                store = store,
                Markdown = addon.Markdown,
                renderer = {},
            }

            function runtime.renderer:Render(content, rows, callback)
                renderCalls[#renderCalls + 1] = {
                    content = content,
                    rows = rows,
                    callback = callback,
                }
            end

            function runtime:RefreshNote(noteId)
                refreshes[#refreshes + 1] = noteId
            end

            local manager = addon.Overlay.Create(runtime)
            Test.truthy("pin first note", manager:Pin(firstNote.id))
            Test.truthy("pin second note", manager:Pin(secondNote.id))

            local firstFrame = manager.framesByNoteId[firstNote.id]
            local secondFrame = manager.framesByNoteId[secondNote.id]
            Test.truthy("one root frame per note", firstFrame ~= secondFrame)
            local rootFrameCount = 0
            for _, widget in ipairs(created) do
                if widget.parent == fakeUIParent and widget.template == "BackdropTemplate" then
                    rootFrameCount = rootFrameCount + 1
                end
            end
            Test.equal("two root overlay frames", rootFrameCount, 2)
            Test.equal("first default width", firstFrame:GetWidth(), 320)
            Test.equal("first default height", firstFrame:GetHeight(), 240)
            Test.equal("second default width", secondFrame:GetWidth(), 320)
            Test.equal("second default height", secondFrame:GetHeight(), 240)
            Test.equal("first frame parent", firstFrame.parent, fakeUIParent)
            Test.equal("BackdropTemplate", firstFrame.template, "BackdropTemplate")
            Test.equal("visible non-dialog strata", firstFrame.frameStrata, "HIGH")
            Test.equal("minimum resize width", firstFrame.resizeBounds[1], 240)
            Test.equal("minimum resize height", firstFrame.resizeBounds[2], 120)
            Test.equal("maximum resize width", firstFrame.resizeBounds[3], 800)
            Test.equal("maximum resize height", firstFrame.resizeBounds[4], 800)

            local firstLayout = store:GetDatabase().overlays.byNoteId[firstNote.id]
            local secondLayout = store:GetDatabase().overlays.byNoteId[secondNote.id]
            Test.equal("first default point", firstLayout.point, "CENTER")
            Test.equal("first default relative point", firstLayout.relativePoint, "CENTER")
            Test.truthy("default offsets differ", firstLayout.x ~= secondLayout.x or firstLayout.y ~= secondLayout.y)
            Test.equal("first body render", #renderCalls[1].rows, 1)
            Test.equal("second body render", #renderCalls[2].rows, 1)
            Test.equal("renderer receives first content", renderCalls[1].content, firstFrame.bodyContent)

            local sourceBefore = store:GetNote(firstNote.id).markdown
            local firstTaskKey = firstNote.id .. ":first task:1"
            firstFrame.lockButton:GetScript("OnClick")(firstFrame.lockButton)
            Test.equal("locked state", firstFrame.locked, true)
            Test.equal("locked movement", firstFrame.movable, false)
            Test.equal("locked resizing", firstFrame.resizable, false)
            Test.equal("locked resize input", firstFrame.resizeHandle.mouseEnabled, false)
            local sizingCalls = firstFrame.calls.startSizing or 0
            firstFrame.resizeHandle:GetScript("OnMouseDown")(firstFrame.resizeHandle)
            Test.equal("locked resize does not start", firstFrame.calls.startSizing or 0, sizingCalls)

            renderCalls[1].callback(firstTaskKey, true)
            Test.equal("checked task stored", store:IsTaskChecked(firstNote.id, firstTaskKey), true)
            Test.equal("other note task state isolated", store:IsTaskChecked(secondNote.id, firstTaskKey), false)
            Test.equal("checklist source unchanged", store:GetNote(firstNote.id).markdown, sourceBefore)
            Test.equal("task refresh callback", refreshes[1], firstNote.id)

            firstFrame.lockButton:GetScript("OnClick")(firstFrame.lockButton)
            Test.equal("unlocked state", firstFrame.locked, false)
            Test.equal("unlocked movement", firstFrame.movable, true)
            Test.equal("unlocked resizing", firstFrame.resizable, true)
            Test.equal("unlocked resize input", firstFrame.resizeHandle.mouseEnabled, true)

            firstFrame:SetPoint("TOPLEFT", fakeUIParent, "TOPLEFT", 40, -40)
            firstFrame.titleBar:GetScript("OnDragStart")(firstFrame.titleBar)
            firstFrame.titleBar:GetScript("OnDragStop")(firstFrame.titleBar)
            firstLayout = store:GetDatabase().overlays.byNoteId[firstNote.id]
            Test.equal("drag point persisted", firstLayout.point, "TOPLEFT")
            Test.equal("drag relative point persisted", firstLayout.relativePoint, "TOPLEFT")
            Test.equal("drag x persisted", firstLayout.x, 40)
            Test.equal("drag y persisted", firstLayout.y, -40)
            Test.truthy("drag started", (firstFrame.calls.startMoving or 0) > 0)
            Test.truthy("drag stopped", (firstFrame.calls.stopMovingOrSizing or 0) > 0)

            firstFrame.resizeHandle:GetScript("OnMouseDown")(firstFrame.resizeHandle)
            Test.equal("resize anchor", firstFrame.sizingAnchor, "BOTTOMRIGHT")
            firstFrame.resizeHandle:GetScript("OnMouseUp")(firstFrame.resizeHandle)
            firstFrame:SetSize(400, 300)
            firstLayout = store:GetDatabase().overlays.byNoteId[firstNote.id]
            Test.equal("resize width persisted", firstLayout.width, 400)
            Test.equal("resize height persisted", firstLayout.height, 300)

            Test.truthy("unpin retains geometry", manager:Unpin(firstNote.id))
            Test.equal("unpin hides frame", firstFrame:IsShown(), false)
            Test.truthy("repin succeeds", manager:Pin(firstNote.id))
            Test.equal("repin reuses frame", manager.framesByNoteId[firstNote.id], firstFrame)
            Test.equal("repin restores width", firstFrame:GetWidth(), 400)
            Test.equal("repin restores height", firstFrame:GetHeight(), 300)

            store:SaveOverlayGeometry(secondNote.id, "CENTER", "CENTER", 9999, 9999, 320, 240)
            Test.truthy("offscreen repin unpin", manager:Unpin(secondNote.id))
            Test.truthy("offscreen repin", manager:Pin(secondNote.id))
            secondLayout = store:GetDatabase().overlays.byNoteId[secondNote.id]
            Test.equal("offscreen x clamped", secondLayout.x, 352)
            Test.equal("offscreen y clamped", secondLayout.y, 264)

            secondFrame.lockButton:GetScript("OnClick")(secondFrame.lockButton)
            Test.equal("second lock persisted", store:GetDatabase().overlays.byNoteId[secondNote.id].locked, true)
            manager:Reset()
            firstLayout = store:GetDatabase().overlays.byNoteId[firstNote.id]
            secondLayout = store:GetDatabase().overlays.byNoteId[secondNote.id]
            Test.equal("reset first x", firstLayout.x, 0)
            Test.equal("reset first y", firstLayout.y, 0)
            Test.equal("reset first width", firstLayout.width, 320)
            Test.equal("reset first height", firstLayout.height, 240)
            Test.equal("reset preserves visible first", firstFrame:IsShown(), true)
            Test.equal("reset preserves visible second", secondFrame:IsShown(), true)
            Test.equal("reset preserves second lock", secondLayout.locked, true)
            Test.equal("reset applies second lock", secondFrame.locked, true)

            manager:UnpinAll()
            Test.equal("UnpinAll hides first", firstFrame:IsShown(), false)
            Test.equal("UnpinAll hides second", secondFrame:IsShown(), false)
            Test.equal("UnpinAll clears first visibility", store:GetDatabase().overlays.byNoteId[firstNote.id].visible, false)
            Test.equal("UnpinAll clears second visibility", store:GetDatabase().overlays.byNoteId[secondNote.id].visible, false)

            store:DeleteNote(firstNote.id)
            manager:Refresh(firstNote.id)
            Test.equal("stale frame removed", manager.framesByNoteId[firstNote.id], nil)
            Test.equal("stale frame hidden", firstFrame:IsShown(), false)
        end)
    end)
end
