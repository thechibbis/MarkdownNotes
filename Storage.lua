local addonName, addon = ...

addon = addon or {}

local Storage = {}
local CURRENT_SCHEMA_VERSION = 1
local DEFAULT_LAYOUT = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
    width = 320,
    height = 240,
}

local GEOMETRY_FIELDS = {
    "point",
    "relativePoint",
    "x",
    "y",
    "width",
    "height",
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

local function normalize_markdown(value)
    return as_string(value)
end

local function make_clock(clockFunction)
    if type(clockFunction) == "function" then
        return function()
            local value = clockFunction()
            if type(value) == "number" then
                return value
            end
            return 0
        end
    end

    return function()
        if type(time) == "function" then
            local value = time()
            if type(value) == "number" then
                return value
            end
        end
        return 0
    end
end

local function is_number(value)
    return type(value) == "number"
end

local function is_point(value)
    return type(value) == "string" and value ~= ""
end

local function copy_default_layout()
    return {
        point = DEFAULT_LAYOUT.point,
        relativePoint = DEFAULT_LAYOUT.relativePoint,
        x = DEFAULT_LAYOUT.x,
        y = DEFAULT_LAYOUT.y,
        width = DEFAULT_LAYOUT.width,
        height = DEFAULT_LAYOUT.height,
    }
end

local function normalize_checked_tasks(note)
    local checkedTasks = {}
    if type(note.checkedTasks) == "table" then
        for taskKey, checked in pairs(note.checkedTasks) do
            if type(taskKey) == "string" and checked == true then
                checkedTasks[taskKey] = true
            end
        end
    end
    note.checkedTasks = checkedTasks
end

local function normalize_note(record, noteId, clock)
    local note = record
    if type(note) ~= "table" then
        note = {}
    end

    note.id = noteId
    note.title = trim(note.title)
    note.markdown = normalize_markdown(note.markdown)

    local timestamp = clock()
    if not is_number(note.createdAt) then
        note.createdAt = timestamp
    end
    if not is_number(note.updatedAt) then
        note.updatedAt = timestamp
    end

    normalize_checked_tasks(note)
    return note
end

local function normalize_layout(layout)
    if type(layout) ~= "table" then
        layout = {}
    end

    if type(layout.visible) ~= "boolean" then
        layout.visible = false
    end
    if type(layout.locked) ~= "boolean" then
        layout.locked = false
    end

    if not is_point(layout.point) then
        layout.point = DEFAULT_LAYOUT.point
    end
    if not is_point(layout.relativePoint) then
        layout.relativePoint = DEFAULT_LAYOUT.relativePoint
    end
    if not is_number(layout.x) then
        layout.x = DEFAULT_LAYOUT.x
    end
    if not is_number(layout.y) then
        layout.y = DEFAULT_LAYOUT.y
    end
    if not is_number(layout.width) then
        layout.width = DEFAULT_LAYOUT.width
    end
    if not is_number(layout.height) then
        layout.height = DEFAULT_LAYOUT.height
    end

    return layout
end

local function normalize_database(database, clock)
    local db
    if type(database) == "table" then
        db = database
    else
        db = {}
    end

    db.schemaVersion = CURRENT_SCHEMA_VERSION

    if type(db.notes) ~= "table" then
        db.notes = {}
    end
    if type(db.notes.order) ~= "table" then
        db.notes.order = {}
    end
    if type(db.notes.byId) ~= "table" then
        db.notes.byId = {}
    end

    local normalizedNotes = {}
    for noteId, record in pairs(db.notes.byId) do
        if type(noteId) == "string" then
            normalizedNotes[noteId] = normalize_note(record, noteId, clock)
        end
    end
    db.notes.byId = normalizedNotes

    local order = {}
    local seen = {}
    for index = 1, #db.notes.order do
        local noteId = db.notes.order[index]
        if type(noteId) == "string" and normalizedNotes[noteId] and not seen[noteId] then
            order[#order + 1] = noteId
            seen[noteId] = true
        end
    end

    local missingIds = {}
    for noteId in pairs(normalizedNotes) do
        if not seen[noteId] then
            missingIds[#missingIds + 1] = noteId
        end
    end
    table.sort(missingIds)
    for _, noteId in ipairs(missingIds) do
        order[#order + 1] = noteId
    end
    db.notes.order = order

    local nextNoteId = db.nextNoteId
    if not is_number(nextNoteId) or nextNoteId < 1 then
        nextNoteId = 1
    else
        nextNoteId = math.floor(nextNoteId)
    end
    for noteId in pairs(normalizedNotes) do
        local suffix = string.match(noteId, "^note%-(%d+)$")
        if suffix then
            local candidate = tonumber(suffix) + 1
            if candidate > nextNoteId then
                nextNoteId = candidate
            end
        end
    end
    db.nextNoteId = nextNoteId

    if type(db.overlays) ~= "table" then
        db.overlays = {}
    end
    if type(db.overlays.byNoteId) ~= "table" then
        db.overlays.byNoteId = {}
    end

    local normalizedOverlays = {}
    for noteId, layout in pairs(db.overlays.byNoteId) do
        if type(noteId) == "string" and normalizedNotes[noteId] then
            normalizedOverlays[noteId] = normalize_layout(layout)
        end
    end
    db.overlays.byNoteId = normalizedOverlays

    return db
end

local function remove_note_from_order(order, noteId)
    local compacted = {}
    for index = 1, #order do
        if order[index] ~= noteId then
            compacted[#compacted + 1] = order[index]
        end
    end
    return compacted
end

local function layout_value(layout, defaults, field)
    local value = defaults and defaults[field] or nil
    if field == "point" or field == "relativePoint" then
        if is_point(value) then
            return value
        end
    elseif is_number(value) then
        return value
    end
    return DEFAULT_LAYOUT[field]
end

function Storage.Create(database, clockFunction)
    local clock = make_clock(clockFunction)
    local db = normalize_database(database, clock)
    local store = {}

    function store:GetDatabase()
        return db
    end

    function store:ListNotes(queryOrNil)
        local notes = {}
        local query = ""
        if queryOrNil ~= nil then
            query = string.lower(as_string(queryOrNil))
        end

        for _, noteId in ipairs(db.notes.order) do
            local note = db.notes.byId[noteId]
            if note and (query == "" or string.find(string.lower(note.title), query, 1, true)) then
                notes[#notes + 1] = note
            end
        end
        return notes
    end

    function store:GetNote(noteId)
        return db.notes.byId[noteId]
    end

    function store:CreateNote(title, markdown)
        title = trim(title)
        if title == "" then
            return nil, "empty-title"
        end

        local noteId
        repeat
            noteId = "note-" .. tostring(db.nextNoteId)
            db.nextNoteId = db.nextNoteId + 1
        until db.notes.byId[noteId] == nil

        local timestamp = clock()
        local note = {
            id = noteId,
            title = title,
            markdown = normalize_markdown(markdown),
            createdAt = timestamp,
            updatedAt = timestamp,
            checkedTasks = {},
        }
        db.notes.byId[noteId] = note
        db.notes.order[#db.notes.order + 1] = noteId
        return note, nil
    end

    function store:UpdateNote(noteId, title, markdown)
        title = trim(title)
        if title == "" then
            return nil, "empty-title"
        end

        local note = db.notes.byId[noteId]
        if not note then
            return nil, nil
        end

        note.title = title
        note.markdown = normalize_markdown(markdown)
        note.updatedAt = clock()
        if type(note.checkedTasks) ~= "table" then
            note.checkedTasks = {}
        end
        return note, nil
    end

    function store:DeleteNote(noteId)
        if not db.notes.byId[noteId] then
            return false
        end

        db.notes.byId[noteId] = nil
        db.notes.order = remove_note_from_order(db.notes.order, noteId)
        db.overlays.byNoteId[noteId] = nil
        return true
    end

    function store:SetTaskChecked(noteId, taskKey, checked)
        local note = db.notes.byId[noteId]
        if not note or type(taskKey) ~= "string" then
            return false
        end
        if type(note.checkedTasks) ~= "table" then
            note.checkedTasks = {}
        end

        if checked == true then
            note.checkedTasks[taskKey] = true
        else
            note.checkedTasks[taskKey] = nil
        end
        return true
    end

    function store:IsTaskChecked(noteId, taskKey)
        local note = db.notes.byId[noteId]
        return note ~= nil and type(note.checkedTasks) == "table" and note.checkedTasks[taskKey] == true
    end

    function store:PinOverlay(noteId, defaults)
        if not db.notes.byId[noteId] then
            return nil
        end

        local layout = db.overlays.byNoteId[noteId]
        if type(layout) ~= "table" then
            layout = {}
        end

        if type(layout.visible) ~= "boolean" then
            layout.visible = false
        end
        if type(layout.locked) ~= "boolean" then
            layout.locked = false
        end
        for _, field in ipairs(GEOMETRY_FIELDS) do
            local valid = false
            if field == "point" or field == "relativePoint" then
                valid = is_point(layout[field])
            else
                valid = is_number(layout[field])
            end
            if not valid then
                layout[field] = layout_value(layout, defaults, field)
            end
        end

        layout.visible = true
        db.overlays.byNoteId[noteId] = layout
        return layout
    end

    function store:SetOverlayVisible(noteId, visible)
        local layout = db.overlays.byNoteId[noteId]
        if not db.notes.byId[noteId] or type(layout) ~= "table" then
            return false
        end
        layout.visible = visible == true
        return true
    end

    function store:SetOverlayLocked(noteId, locked)
        local layout = db.overlays.byNoteId[noteId]
        if not db.notes.byId[noteId] or type(layout) ~= "table" then
            return false
        end
        layout.locked = locked == true
        return true
    end

    function store:SaveOverlayGeometry(noteId, point, relativePoint, x, y, width, height)
        local layout = db.overlays.byNoteId[noteId]
        if not db.notes.byId[noteId] or type(layout) ~= "table" then
            return false
        end

        layout.point = is_point(point) and point or DEFAULT_LAYOUT.point
        layout.relativePoint = is_point(relativePoint) and relativePoint or DEFAULT_LAYOUT.relativePoint
        layout.x = is_number(x) and x or DEFAULT_LAYOUT.x
        layout.y = is_number(y) and y or DEFAULT_LAYOUT.y
        layout.width = is_number(width) and width or DEFAULT_LAYOUT.width
        layout.height = is_number(height) and height or DEFAULT_LAYOUT.height
        return true
    end

    function store:ListVisibleOverlays()
        local overlays = {}
        for _, noteId in ipairs(db.notes.order) do
            local layout = db.overlays.byNoteId[noteId]
            if layout and layout.visible == true then
                overlays[#overlays + 1] = {
                    noteId = noteId,
                    layout = layout,
                }
            end
        end
        return overlays
    end

    function store:ResetOverlays()
        for noteId, layout in pairs(db.overlays.byNoteId) do
            if db.notes.byId[noteId] and type(layout) == "table" then
                local visible = layout.visible == true
                local locked = layout.locked == true
                local defaults = copy_default_layout()
                layout.point = defaults.point
                layout.relativePoint = defaults.relativePoint
                layout.x = defaults.x
                layout.y = defaults.y
                layout.width = defaults.width
                layout.height = defaults.height
                layout.visible = visible
                layout.locked = locked
            else
                db.overlays.byNoteId[noteId] = nil
            end
        end
    end

    return store
end

addon.Storage = Storage
