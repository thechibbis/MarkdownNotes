local addonName, addon = ...

addon = addon or {}

local Markdown = {}

local function trim(value)
    return (string.gsub(string.gsub(value, "^%s+", ""), "%s+$", ""))
end

local function normalize_source(source)
    if source == nil then
        source = ""
    elseif type(source) ~= "string" then
        source = tostring(source)
    end

    source = string.gsub(source, "\r\n", "\n")
    source = string.gsub(source, "\r", "\n")
    return source
end

local function split_lines(source)
    local lines = {}
    if source == "" then
        return lines
    end

    local start = 1
    local length = #source
    while start <= length do
        local newline = string.find(source, "\n", start, true)
        if newline then
            lines[#lines + 1] = string.sub(source, start, newline - 1)
            start = newline + 1
        else
            lines[#lines + 1] = string.sub(source, start)
            break
        end
    end

    return lines
end

local function append_text(segments, text)
    if text == "" then
        return
    end

    local previous = segments[#segments]
    if previous and previous.kind == "text" then
        previous.text = previous.text .. text
    else
        segments[#segments + 1] = {
            kind = "text",
            text = text,
        }
    end
end

local function append_inline_segment(segments, kind, text, url)
    local segment = {
        kind = kind,
        text = text,
    }
    if url ~= nil then
        segment.url = url
    end
    segments[#segments + 1] = segment
end

local function find_single_delimiter(text, delimiter, start)
    local position = start
    while true do
        local found = string.find(text, delimiter, position, true)
        if not found then
            return nil
        end

        local before = string.sub(text, found - 1, found - 1)
        local after = string.sub(text, found + 1, found + 1)
        if before ~= delimiter and after ~= delimiter then
            return found
        end
        position = found + 1
    end
end

local function find_strong_delimiter(text, delimiter, start)
    local position = string.find(text, delimiter, start, true)
    while position do
        if position > start then
            return position
        end
        position = string.find(text, delimiter, position + 1, true)
    end
    return nil
end

local function parse_inline(text)
    local segments = {}
    local position = 1
    local length = #text

    while position <= length do
        local current = string.sub(text, position, position)
        local double = string.sub(text, position, position + 1)

        if current == "`" then
            local closing = string.find(text, "`", position + 1, true)
            if closing then
                append_inline_segment(segments, "code", string.sub(text, position + 1, closing - 1))
                position = closing + 1
            else
                append_text(segments, current)
                position = position + 1
            end
        elseif current == "[" then
            local precededByImageMarker = string.sub(text, position - 1, position - 1) == "!"
            local labelEnd = string.find(text, "]", position + 1, true)
            local urlStart
            local urlEnd
            if not precededByImageMarker and labelEnd and labelEnd > position + 1 and trim(string.sub(text, position + 1, labelEnd - 1)) ~= "" and string.sub(text, labelEnd + 1, labelEnd + 1) == "(" then
                urlStart = labelEnd + 2
                urlEnd = string.find(text, ")", urlStart, true)
            end

            if urlEnd and urlEnd > urlStart then
                append_inline_segment(
                    segments,
                    "link",
                    string.sub(text, position + 1, labelEnd - 1),
                    string.sub(text, urlStart, urlEnd - 1)
                )
                position = urlEnd + 1
            else
                append_text(segments, current)
                position = position + 1
            end
        elseif double == "**" or double == "__" then
            local closing = find_strong_delimiter(text, double, position + 2)
            if closing then
                append_inline_segment(segments, "bold", string.sub(text, position + 2, closing - 1))
                position = closing + 2
            else
                append_text(segments, double)
                position = position + 2
            end
        elseif current == "*" or current == "_" then
            local closing = find_single_delimiter(text, current, position + 1)
            if closing then
                append_inline_segment(segments, "italic", string.sub(text, position + 1, closing - 1))
                position = closing + 1
            else
                append_text(segments, current)
                position = position + 1
            end
        else
            append_text(segments, current)
            position = position + 1
        end
    end

    return segments
end

local function parse_heading(line)
    local hashes, text = string.match(line, "^%s*(#+)%s+(.+)$")
    if not hashes or #hashes > 3 then
        return nil
    end

    text = trim(text)
    text = string.gsub(text, "%s+#+%s*$", "")
    text = trim(text)

    return {
        kind = "heading",
        level = #hashes,
        segments = parse_inline(text),
    }
end

local function parse_task(line)
    local leading, checkedMarker, text = string.match(
        line,
        "^(%s*)[-*]%s+%[([ xX])%]%s+(.+)$"
    )
    if not leading then
        return nil
    end

    text = trim(text)
    if text == "" then
        return nil
    end

    return {
        indent = #leading,
        checkedMarker = checkedMarker ~= " ",
        text = text,
    }
end

local function is_malformed_task(line)
    local leading = string.match(line, "^(%s*)[-*]%s*%[[ xX]%](.*)$")
    return leading ~= nil
end

local function parse_bullet(line)
    local leading, marker, remainder = string.match(line, "^(%s*)([-*])(.*)$")
    if not leading then
        return nil
    end

    if remainder ~= "" and not string.match(remainder, "^%s+") then
        return nil
    end

    return {
        indent = #leading,
        text = trim(remainder),
    }
end

local function parse_ordered(line)
    local leading, number, remainder = string.match(line, "^(%s*)(%d+)%.(.*)$")
    if not leading then
        return nil
    end

    if remainder ~= "" and not string.match(remainder, "^%s+") then
        return nil
    end

    return {
        indent = #leading,
        number = tonumber(number),
        text = trim(remainder),
    }
end

local function is_separator(line)
    local text = trim(line)
    return string.match(text, "^%-%-%-+$") ~= nil
end

local function is_blank(line)
    return string.match(line, "^%s*$") ~= nil
end

local function is_fence(line)
    return trim(line) == "```"
end

local function task_key(noteId, normalized, occurrence)
    return tostring(noteId or "") .. ":" .. normalized .. ":" .. tostring(occurrence)
end

local function normalize_task_label(label)
    label = trim(label)
    label = string.gsub(label, "%s+", " ")
    return string.lower(label)
end

function Markdown.Parse(noteId, source, checkedTasks)
    source = normalize_source(source)
    local lines = split_lines(source)
    local rows = {}
    local taskOccurrences = {}
    local paragraphLines = {}
    local inFence = false

    if type(checkedTasks) ~= "table" then
        checkedTasks = {}
    end

    local function flush_paragraph()
        if #paragraphLines == 0 then
            return
        end

        rows[#rows + 1] = {
            kind = "paragraph",
            segments = parse_inline(table.concat(paragraphLines, "\n")),
        }
        paragraphLines = {}
    end

    for _, line in ipairs(lines) do
        if inFence then
            if is_fence(line) then
                inFence = false
            else
                rows[#rows + 1] = {
                    kind = "code",
                    segments = {
                        {
                            kind = "text",
                            text = line,
                        },
                    },
                }
            end
        elseif is_fence(line) then
            flush_paragraph()
            inFence = true
        else
            local row = parse_heading(line)
            if row then
                flush_paragraph()
                rows[#rows + 1] = row
            else
                local task = parse_task(line)
                if task then
                    flush_paragraph()
                    local normalized = normalize_task_label(task.text)
                    local occurrence = (taskOccurrences[normalized] or 0) + 1
                    taskOccurrences[normalized] = occurrence
                    local key = task_key(noteId, normalized, occurrence)
                    local checked = task.checkedMarker
                    if checkedTasks[key] ~= nil then
                        checked = checkedTasks[key] == true
                    end
                    rows[#rows + 1] = {
                        kind = "task",
                        indent = task.indent,
                        taskKey = key,
                        checked = checked,
                        segments = parse_inline(task.text),
                    }
                elseif is_malformed_task(line) then
                    paragraphLines[#paragraphLines + 1] = line
                else
                    local bullet = parse_bullet(line)
                    if bullet then
                        flush_paragraph()
                        rows[#rows + 1] = {
                            kind = "bullet",
                            indent = bullet.indent,
                            segments = parse_inline(bullet.text),
                        }
                    else
                        local ordered = parse_ordered(line)
                        if ordered then
                            flush_paragraph()
                            rows[#rows + 1] = {
                                kind = "ordered",
                                indent = ordered.indent,
                                number = ordered.number,
                                segments = parse_inline(ordered.text),
                            }
                        elseif is_separator(line) then
                            flush_paragraph()
                            rows[#rows + 1] = {
                                kind = "separator",
                                segments = {},
                            }
                        elseif is_blank(line) then
                            flush_paragraph()
                            rows[#rows + 1] = {
                                kind = "spacer",
                                segments = {},
                            }
                        else
                            paragraphLines[#paragraphLines + 1] = line
                        end
                    end
                end
            end
        end
    end

    flush_paragraph()
    return rows
end

addon.Markdown = Markdown
