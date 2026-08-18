return function(addon, Test)
    Test.run("Renderer escapes WoW markup characters", function()
        local escaped = addon.Renderer.EscapeText("literal | text")
        Test.equal("escaped pipe", escaped, "literal || text")
    end)

    Test.run("Renderer maps inline segments to safe markup", function()
        local markup = addon.Renderer.BuildInlineMarkup({
            { kind = "text", text = "A " },
            { kind = "bold", text = "bold" },
            { kind = "text", text = " " },
            { kind = "code", text = "x|y" },
        })
        Test.truthy("contains text", string.find(markup, "A ", 1, true) ~= nil)
        Test.truthy("contains bold text", string.find(markup, "bold", 1, true) ~= nil)
        Test.truthy("escapes code pipe", string.find(markup, "x||y", 1, true) ~= nil)
    end)

    Test.run("Renderer keeps inline styles and link hints safe", function()
        local markup = addon.Renderer.BuildInlineMarkup({
            { kind = "italic", text = "soft|text" },
            { kind = "link", text = "read|this", url = "https://example.com/?q=|cffff0000bad|r" },
        })
        Test.truthy("italic text is escaped", string.find(markup, "soft||text", 1, true) ~= nil)
        Test.truthy("link label is escaped", string.find(markup, "read||this", 1, true) ~= nil)
        Test.truthy("link destination is escaped", string.find(markup, "https://example.com/?q=||cffff0000bad||r", 1, true) ~= nil)
        Test.truthy("link destination is displayed", string.find(markup, "https://example.com", 1, true) ~= nil)
    end)

    local function new_widget(objectType, parent, width)
        local widget = {
            objectType = objectType,
            parent = parent,
            width = width or 0,
            height = 0,
            shown = false,
            scripts = {},
            children = {},
            calls = {},
            text = "",
            checked = false,
        }

        function widget:GetObjectType()
            return self.objectType
        end

        function widget:SetSize(newWidth, newHeight)
            self:SetWidth(newWidth)
            self:SetHeight(newHeight)
        end

        function widget:SetWidth(newWidth)
            self.width = newWidth
            self.calls.setWidth = (self.calls.setWidth or 0) + 1
        end

        function widget:GetWidth()
            return self.width
        end

        function widget:SetHeight(newHeight)
            self.height = newHeight
            self.calls.setHeight = (self.calls.setHeight or 0) + 1
        end

        function widget:GetHeight()
            return self.height
        end

        function widget:SetPoint(...)
            self.point = { ... }
            self.calls.setPoint = (self.calls.setPoint or 0) + 1
        end

        function widget:ClearAllPoints()
            self.point = nil
            self.calls.clearAllPoints = (self.calls.clearAllPoints or 0) + 1
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
            self.calls.setScript = (self.calls.setScript or 0) + 1
        end

        function widget:GetScript(scriptType)
            return self.scripts[scriptType]
        end

        function widget:CreateFontString()
            local fontString = new_widget("FontString", self, 0)
            fontString.kind = "fontString"
            self.children[#self.children + 1] = fontString
            return fontString
        end

        function widget:CreateTexture()
            local texture = new_widget("Texture", self, 0)
            texture.kind = "texture"
            self.children[#self.children + 1] = texture
            return texture
        end

        function widget:SetText(value)
            self.text = value or ""
            self.calls.setText = (self.calls.setText or 0) + 1
        end

        function widget:GetStringHeight()
            self.calls.getStringHeight = (self.calls.getStringHeight or 0) + 1
            local charactersPerLine = math.max(1, math.floor(self.width / 6))
            local lineCount = math.max(1, math.ceil(#self.text / charactersPerLine))
            local explicitLines = 1
            for _ in string.gmatch(self.text, "\n") do
                explicitLines = explicitLines + 1
            end
            return math.max(lineCount, explicitLines) * 10
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

        function widget:SetDrawLayer(...)
            self.drawLayer = { ... }
        end

        function widget:SetChecked(value)
            self.checkedAtSet = value == true
            self.checked = value == true
            self.calls.setChecked = (self.calls.setChecked or 0) + 1
            if self.scripts.OnClick then
                self.checkedScriptWasInstalled = true
            end
        end

        function widget:GetChecked()
            return self.checked == true
        end

        function widget:RegisterForClicks(...)
            self.registeredClicks = { ... }
        end

        function widget:Click()
            self.checked = not self.checked
            if self.scripts.OnClick then
                self.scripts.OnClick(self)
            end
        end

        return widget
    end

    local function install_fake_widgets()
        local previousCreateFrame = _G.CreateFrame
        local created = {}

        _G.CreateFrame = function(objectType, _, parent)
            local widget = new_widget(objectType, parent, parent and parent:GetWidth() or 0)
            created[#created + 1] = widget
            if parent and parent.children then
                parent.children[#parent.children + 1] = widget
            end
            return widget
        end

        return created, function()
            _G.CreateFrame = previousCreateFrame
        end
    end

    Test.run("Renderer reuses native rows and sizes wrapped content", function()
        local created, restore = install_fake_widgets()
        local parent = new_widget("Frame", nil, 120)
        local renderer = addon.Renderer.Create()
        local callbackCalls = {}
        local rows = {
            { kind = "heading", level = 1, segments = { { kind = "text", text = "Heading" } } },
            { kind = "paragraph", segments = { { kind = "text", text = "A deliberately long paragraph that should wrap." } } },
            { kind = "bullet", indent = 1, segments = { { kind = "text", text = "Bullet" } } },
            { kind = "ordered", indent = 0, number = 3, segments = { { kind = "text", text = "Ordered" } } },
            { kind = "task", indent = 0, taskKey = "note-1:task:1", checked = true, segments = { { kind = "text", text = "Task" } } },
            { kind = "code", segments = { { kind = "text", text = "x | y" } } },
            { kind = "separator", segments = {} },
            { kind = "spacer", segments = {} },
        }

        renderer:Render(parent, rows, function(taskKey, checked)
            callbackCalls[#callbackCalls + 1] = { taskKey = taskKey, checked = checked }
        end)

        Test.truthy("content has height", parent:GetHeight() > 0)
        Test.truthy("content width is used", parent.__MarkdownNotesRendererPool.rows[1].frame:GetWidth() == 120)
        Test.truthy("wrapped text is measured", parent.__MarkdownNotesRendererPool.rows[2].label.calls.getStringHeight > 0)
        Test.truthy("label wraps", parent.__MarkdownNotesRendererPool.rows[2].label.wordWrap == true)
        Test.truthy("native frame rows created", #parent.__MarkdownNotesRendererPool.rows == #rows)
        Test.truthy("native check button created", #created > #rows)

        local taskButton
        for _, widget in ipairs(created) do
            if widget:GetObjectType() == "CheckButton" then
                taskButton = widget
                break
            end
        end
        Test.truthy("task button exists", taskButton ~= nil)
        Test.equal("checked before click script", taskButton.checkedAtSet, true)
        Test.equal("click script installed after checked", taskButton.checkedScriptWasInstalled, nil)
        taskButton:Click()
        Test.equal("task callback key", callbackCalls[1].taskKey, "note-1:task:1")
        Test.equal("task callback checked", callbackCalls[1].checked, false)

        local frameCount = #created
        renderer:Render(parent, { rows[1] }, function() end)
        Test.equal("row pool reused", #created, frameCount)
        Test.equal("unused row hidden", parent.__MarkdownNotesRendererPool.rows[2].frame:IsShown(), false)

        renderer:Clear(parent)
        Test.equal("clear resets content height", parent:GetHeight(), 0)
        Test.equal("clear hides first row", parent.__MarkdownNotesRendererPool.rows[1].frame:IsShown(), false)
        restore()
    end)

    Test.run("Renderer resets pooled text colors on reuse", function()
        local _, restore = install_fake_widgets()
        local parent = new_widget("Frame", nil, 160)
        local renderer = addon.Renderer.Create()

        renderer:Render(parent, {
            { kind = "code", segments = { { kind = "text", text = "code" } } },
        })
        renderer:Render(parent, {
            { kind = "paragraph", segments = { { kind = "text", text = "normal" } } },
        })

        local color = parent.__MarkdownNotesRendererPool.rows[1].label.textColor
        Test.equal("normal text red", color[1], 1)
        Test.equal("normal text green", color[2], 1)
        Test.equal("normal text blue", color[3], 1)
    end)
end
