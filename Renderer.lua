local addonName, addon = ...

addon = addon or {}

local Renderer = {}

local POOL_FIELD = "__MarkdownNotesRendererPool"
local DEFAULT_LINE_HEIGHT = 16
local INDENT_WIDTH = 16
local MARKER_WIDTH = 20
local CHECKBOX_SIZE = 20
local CHECKBOX_GAP = 4
local SEPARATOR_HEIGHT = 8
local SPACER_HEIGHT = 8

local COLORS = {
    bold = { 1.00, 0.82, 0.25, 1.00 },
    italic = { 0.70, 0.70, 0.70, 1.00 },
    code = { 0.55, 0.85, 1.00, 1.00 },
    link = { 0.35, 0.75, 1.00, 1.00 },
    hint = { 0.60, 0.60, 0.60, 1.00 },
    marker = { 0.75, 0.75, 0.75, 1.00 },
    normal = { 1.00, 1.00, 1.00, 1.00 },
}

local HEADING_STYLES = {
    [1] = { font = "GameFontNormalLarge", color = { 1.00, 0.82, 0.25, 1.00 } },
    [2] = { font = "GameFontNormal", color = { 1.00, 0.95, 0.70, 1.00 } },
    [3] = { font = "GameFontHighlight", color = { 0.90, 0.90, 0.90, 1.00 } },
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

local function color_markup(color)
    return string.format("|c%02x%02x%02x%02x", math.floor((color[4] or 1) * 255), math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255))
end

local function wrap_markup(color, text)
    return color_markup(color) .. text .. "|r"
end

function Renderer.EscapeText(text)
    local escaped = string.gsub(as_string(text), "|", "||")
    return escaped
end

function Renderer.BuildInlineMarkup(segments)
    if type(segments) ~= "table" then
        return ""
    end

    local parts = {}
    for _, segment in ipairs(segments) do
        if type(segment) == "table" then
            local kind = segment.kind
            local text = Renderer.EscapeText(segment.text)

            if kind == "bold" then
                parts[#parts + 1] = wrap_markup(COLORS.bold, text)
            elseif kind == "italic" then
                parts[#parts + 1] = wrap_markup(COLORS.italic, text)
            elseif kind == "code" then
                parts[#parts + 1] = wrap_markup(COLORS.code, text)
            elseif kind == "link" then
                local destination = Renderer.EscapeText(segment.url)
                parts[#parts + 1] = wrap_markup(COLORS.link, text)
                if destination ~= "" then
                    parts[#parts + 1] = " " .. wrap_markup(COLORS.hint, "[" .. destination .. "]")
                end
            else
                parts[#parts + 1] = text
            end
        end
    end

    return table.concat(parts)
end

local function set_color(fontString, color)
    if fontString.SetTextColor then
        fontString:SetTextColor(color[1], color[2], color[3], color[4])
    end
end

local function reset_font_string(fontString)
    if not fontString then
        return
    end
    fontString:Hide()
    fontString:ClearAllPoints()
    fontString:SetText("")
    fontString:SetWidth(0)
    fontString:SetHeight(0)
end

local function reset_row(row)
    row.frame:Hide()
    row.frame:ClearAllPoints()
    row.frame:SetHeight(0)
    row.frame:SetWidth(0)
    reset_font_string(row.label)
    reset_font_string(row.marker)

    if row.checkButton then
        row.checkButton:Hide()
        row.checkButton:ClearAllPoints()
        row.checkButton:SetScript("OnClick", nil)
    end

    if row.separator then
        row.separator:Hide()
        row.separator:ClearAllPoints()
        row.separator:SetWidth(0)
        row.separator:SetHeight(0)
    end
end

local function create_row(parent)
    local frame = CreateFrame("Frame", nil, parent)
    local row = {
        frame = frame,
        label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"),
        marker = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight"),
    }

    row.label:SetJustifyH("LEFT")
    row.label:SetJustifyV("TOP")
    row.label:SetWordWrap(true)
    row.marker:SetJustifyH("RIGHT")
    row.marker:SetJustifyV("TOP")
    row.marker:SetWordWrap(false)
    reset_row(row)
    return row
end

local function ensure_pool(parent)
    local pool = parent[POOL_FIELD]
    if not pool then
        pool = { rows = {} }
        parent[POOL_FIELD] = pool
    end
    return pool
end

local function ensure_row(pool, parent, index)
    local row = pool.rows[index]
    if not row then
        row = create_row(parent)
        pool.rows[index] = row
    end
    return row
end

local function ensure_task_button(row)
    if not row.checkButton then
        row.checkButton = CreateFrame("CheckButton", nil, row.frame, "UICheckButtonTemplate")
        row.checkButton:SetSize(CHECKBOX_SIZE, CHECKBOX_SIZE)
        row.checkButton:RegisterForClicks("AnyUp")
    end
    return row.checkButton
end

local function ensure_separator(row)
    if not row.separator then
        row.separator = row.frame:CreateTexture(nil, "ARTWORK")
    end
    return row.separator
end

local function content_width(parent)
    local width = parent:GetWidth()
    if type(width) ~= "number" or width < 1 then
        return 1
    end
    return width
end

local function measured_text_height(fontString)
    local height = fontString:GetStringHeight()
    if type(height) ~= "number" or height < 1 then
        return DEFAULT_LINE_HEIGHT
    end
    return height
end

local function resolve_font_object(fontObject)
    if type(fontObject) == "string" and _G[fontObject] then
        return _G[fontObject]
    end
    return fontObject
end

local function configure_label(fontString, rowFrame, width, offset, text, fontObject, color)
    fontString:ClearAllPoints()
    fontString:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", offset, 0)
    fontString:SetWidth(math.max(1, width - offset))
    fontString:SetWordWrap(true)
    fontString:SetJustifyH("LEFT")
    fontString:SetJustifyV("TOP")
    if fontObject and fontString.SetFontObject then
        fontString:SetFontObject(resolve_font_object(fontObject))
    end
    set_color(fontString, color or COLORS.normal)
    fontString:SetText(text)
    local height = measured_text_height(fontString)
    fontString:SetHeight(height)
    fontString:Show()
    return height
end

local function configure_marker(marker, rowFrame, offset, markerText)
    marker:ClearAllPoints()
    marker:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", offset, 0)
    marker:SetWidth(MARKER_WIDTH)
    marker:SetHeight(DEFAULT_LINE_HEIGHT)
    marker:SetWordWrap(false)
    marker:SetJustifyH("RIGHT")
    marker:SetJustifyV("TOP")
    marker:SetTextColor(COLORS.marker[1], COLORS.marker[2], COLORS.marker[3], COLORS.marker[4])
    marker:SetText(markerText)
    marker:Show()
end

local function render_text_row(row, parentWidth, text, offset, fontObject, color)
    row.frame:SetWidth(parentWidth)
    local height = configure_label(row.label, row.frame, parentWidth, offset, text, fontObject, color)
    row.frame:SetHeight(height)
    row.frame:Show()
    return height
end

local function render_list_row(row, parentWidth, indent, markerText, text)
    local indentOffset = math.max(0, tonumber(indent) or 0) * INDENT_WIDTH
    configure_marker(row.marker, row.frame, indentOffset, markerText)
    return render_text_row(row, parentWidth, text, indentOffset + MARKER_WIDTH, "GameFontHighlight", nil)
end

local function render_task_row(row, parentWidth, indent, taskKey, checked, text, onTaskClick)
    local indentOffset = math.max(0, tonumber(indent) or 0) * INDENT_WIDTH
    local checkButton = ensure_task_button(row)

    row.frame:SetWidth(parentWidth)
    checkButton:ClearAllPoints()
    checkButton:SetPoint("TOPLEFT", row.frame, "TOPLEFT", indentOffset, 0)
    checkButton:SetChecked(checked == true)

    local labelOffset = indentOffset + CHECKBOX_SIZE + CHECKBOX_GAP
    local height = configure_label(row.label, row.frame, parentWidth, labelOffset, text, "GameFontHighlight", nil)
    row.frame:SetHeight(math.max(height, CHECKBOX_SIZE))

    checkButton:SetScript("OnClick", function(button)
        if onTaskClick then
            onTaskClick(taskKey, button:GetChecked())
        end
    end)
    checkButton:Show()
    row.frame:Show()
    return math.max(height, CHECKBOX_SIZE)
end

local function render_separator_row(row, parentWidth)
    local separator = ensure_separator(row)
    row.frame:SetWidth(parentWidth)
    row.frame:SetHeight(SEPARATOR_HEIGHT)
    separator:ClearAllPoints()
    separator:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, -math.floor(SEPARATOR_HEIGHT / 2))
    separator:SetWidth(parentWidth)
    separator:SetHeight(1)
    separator:SetColorTexture(0.50, 0.50, 0.50, 0.65)
    separator:Show()
    row.frame:Show()
    return SEPARATOR_HEIGHT
end

local function render_spacer_row(row, parentWidth)
    row.frame:SetWidth(parentWidth)
    row.frame:SetHeight(SPACER_HEIGHT)
    row.frame:Show()
    return SPACER_HEIGHT
end

local function render_row(rowObject, row, parentWidth, onTaskClick)
    local kind = type(rowObject) == "table" and rowObject.kind or ""

    if kind == "heading" then
        local style = HEADING_STYLES[tonumber(rowObject.level) or 1] or HEADING_STYLES[3]
        return render_text_row(row, parentWidth, Renderer.BuildInlineMarkup(rowObject.segments), 0, style.font, style.color)
    elseif kind == "paragraph" then
        return render_text_row(row, parentWidth, Renderer.BuildInlineMarkup(rowObject.segments), 0, "GameFontHighlight", nil)
    elseif kind == "bullet" then
        return render_list_row(row, parentWidth, rowObject.indent, "•", Renderer.BuildInlineMarkup(rowObject.segments))
    elseif kind == "ordered" then
        return render_list_row(row, parentWidth, rowObject.indent, tostring(rowObject.number or "") .. ".", Renderer.BuildInlineMarkup(rowObject.segments))
    elseif kind == "task" then
        return render_task_row(row, parentWidth, rowObject.indent, rowObject.taskKey, rowObject.checked, Renderer.BuildInlineMarkup(rowObject.segments), onTaskClick)
    elseif kind == "code" then
        return render_text_row(row, parentWidth, Renderer.BuildInlineMarkup(rowObject.segments), 0, "GameFontHighlightSmall", COLORS.code)
    elseif kind == "separator" then
        return render_separator_row(row, parentWidth)
    elseif kind == "spacer" then
        return render_spacer_row(row, parentWidth)
    end

    return render_text_row(row, parentWidth, "", 0, "GameFontHighlight", nil)
end

function Renderer.Create()
    return setmetatable({}, { __index = Renderer })
end

function Renderer.Clear(_, parent)
    if not parent then
        return
    end

    local pool = parent[POOL_FIELD]
    if pool then
        for _, row in ipairs(pool.rows) do
            reset_row(row)
        end
    end
    parent:SetHeight(0)
end

function Renderer.Render(_, parent, rows, onTaskClick)
    if not parent then
        return
    end

    local pool = ensure_pool(parent)
    local parentWidth = content_width(parent)
    local rowCount = type(rows) == "table" and #rows or 0

    for _, row in ipairs(pool.rows) do
        reset_row(row)
    end

    local top = 0
    for index = 1, rowCount do
        local row = ensure_row(pool, parent, index)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -top)
        local height = render_row(rows[index], row, parentWidth, onTaskClick)
        top = top + height
    end

    for index = rowCount + 1, #pool.rows do
        reset_row(pool.rows[index])
    end

    parent:SetHeight(top)
end

addon.Renderer = Renderer
