# MarkdownNotes MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dependency-free World of Warcraft Retail Midnight 12.1 addon that stores account-wide Markdown notes, renders a practical Markdown subset, and displays several movable checklist-capable note overlays.

**Architecture:** Use focused Lua modules loaded by `MarkdownNotes.toc`. `Storage` owns the SavedVariables seam, `Markdown` turns source text into a UI-independent render model, `Renderer` turns that model into native WoW widgets, and the manager, editor, and overlay modules coordinate user workflows through those interfaces. Pure Markdown, storage, and command parsing code will run in a standard Lua 5.1 test harness; widget behavior will be verified in-game.

**Tech Stack:** WoW Retail FrameXML/Lua 5.1, native `Frame`, `Button`, `CheckButton`, `EditBox`, `ScrollFrame`, `FontString`, and `BackdropTemplate` widgets; standard Lua 5.1 test runner; no external addon libraries.

**Spec:** `docs/superpowers/specs/2026-08-18-markdown-notes-design.md`

## Global Constraints

- Target World of Warcraft Retail Midnight 12.1; use `## Interface: 120100` for the 12.1.0 client target.
- The `.toc` declares the account-wide variable exactly as `## SavedVariables: MarkdownNotesDB`.
- No external libraries, filesystem access, arbitrary file synchronization, raw HTML, embedded Lua, scripts, images, tables, or external browser launching.
- The MVP supports headings, unordered and numbered lists, basic indentation, task lists, separators, fenced code blocks, paragraphs, bold, italic, inline code, and Markdown links.
- The `/mn` slash command opens the manager and exposes the documented note and overlay commands.
- Checklist state is stored separately from Markdown source and persists account-wide.
- Multiple different notes may be pinned simultaneously; each note has at most one overlay.
- Only addon-owned frames are created or modified; protected Blizzard frames are not changed.
- The addon is event-driven and does not require a continuous `OnUpdate` loop.
- Parser and storage code must run without WoW-only globals so the standard Lua test harness can load them.

---

## File map and implementation contracts

Create this final layout:

```text
MarkdownNotes/
├── MarkdownNotes.toc
├── Core.lua
├── Storage.lua
├── Markdown.lua
├── Renderer.lua
├── NoteManager.lua
├── Editor.lua
├── Overlay.lua
├── Commands.lua
├── tests/
│   ├── assert.lua
│   ├── load_module.lua
│   ├── markdown_test.lua
│   ├── storage_test.lua
│   ├── renderer_test.lua
│   ├── commands_test.lua
│   └── run.lua
└── docs/superpowers/
    ├── specs/2026-08-18-markdown-notes-design.md
    └── plans/2026-08-18-markdown-notes-mvp.md
```

The following interfaces are fixed before implementation:

```lua
-- Markdown.lua: pure parser
addon.Markdown.Parse(noteId, source, checkedTasks) -> rows

-- Storage.lua: persistence seam
addon.Storage.Create(databaseOrNil, clockFunction) -> store
store:GetDatabase() -> database
store:ListNotes(queryOrNil) -> orderedNoteArray
store:GetNote(noteId) -> noteOrNil
store:CreateNote(title, markdown) -> noteOrNil, errorOrNil
store:UpdateNote(noteId, title, markdown) -> noteOrNil, errorOrNil
store:DeleteNote(noteId) -> boolean
store:SetTaskChecked(noteId, taskKey, checked) -> boolean
store:IsTaskChecked(noteId, taskKey) -> boolean
store:PinOverlay(noteId, defaults) -> layoutOrNil
store:SetOverlayVisible(noteId, visible) -> boolean
store:SetOverlayLocked(noteId, locked) -> boolean
store:SaveOverlayGeometry(noteId, point, relativePoint, x, y, width, height) -> boolean
store:ListVisibleOverlays() -> orderedOverlayArray
store:ResetOverlays() -> nil

-- Renderer.lua: widget adapter
addon.Renderer.EscapeText(text) -> escapedText
addon.Renderer.BuildInlineMarkup(segments) -> safeMarkup
addon.Renderer.Create() -> renderer
renderer:Clear(parentContentFrame) -> nil
renderer:Render(parentContentFrame, rows, onTaskClick) -> nil

-- Commands.lua: pure parser plus WoW registration
addon.Commands.Parse(text) -> verb, argument
addon.Commands.Register(addon) -> nil

-- UI modules
addon.NoteManager.Create(addon) -> manager
manager:Open() -> nil
manager:Close() -> nil
manager:Toggle() -> nil
manager:RefreshList() -> nil
manager:RefreshPreview(noteIdOrNil) -> nil
manager:Select(noteId) -> nil

addon.Editor.Create(addon) -> editor
editor:OpenNew() -> nil
editor:Open(noteId) -> nil
editor:Close() -> nil
editor:RefreshPreview() -> nil

addon.Overlay.Create(addon) -> overlayManager
overlayManager:Pin(noteId) -> boolean
overlayManager:Unpin(noteId) -> boolean
overlayManager:UnpinAll() -> nil
overlayManager:RestoreVisible() -> nil
overlayManager:Refresh(noteId) -> nil
overlayManager:RefreshAll() -> nil
overlayManager:Reset() -> nil
```

`Core.lua` supplies the coordinator callbacks:

```lua
addon:RefreshNote(noteId)
addon:RefreshAll()
```

They refresh the manager preview/list and any overlay for the affected note without allowing UI modules to mutate database tables directly.

---

### Task 1: Create the pure Lua test harness

**Files:**
- Create: `tests/assert.lua`
- Create: `tests/load_module.lua`
- Create: `tests/run.lua`

**Interfaces:**
- Produces `Test.equal(label, actual, expected)`, `Test.deepEqual(label, actual, expected)`, `Test.truthy(label, value)`, and `Test.run(label, callback)`.
- Produces `loadAddonFile(path, addon)`, which loads a Lua addon chunk and invokes it as `chunk("MarkdownNotes", addon)` so files using `local addonName, addon = ...` work outside WoW.
- Produces `lua tests/run.lua` as the single pure-module test command.

- [ ] **Step 1: Write the assertion helpers.**

```lua
local Test = {}

local function fail(label, message)
    error(label .. ": " .. message, 0)
end

function Test.equal(label, actual, expected)
    if actual ~= expected then
        fail(label, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
    end
end

function Test.truthy(label, value)
    if not value then
        fail(label, "expected a truthy value")
    end
end

function Test.deepEqual(label, actual, expected)
    local function compare(a, b, path)
        if type(a) ~= type(b) then
            return false, path .. " has different types"
        end
        if type(a) ~= "table" then
            return a == b, path .. " differs"
        end
        for key, value in pairs(a) do
            local ok, reason = compare(value, b[key], path .. "." .. tostring(key))
            if not ok then
                return false, reason
            end
        end
        for key in pairs(b) do
            if a[key] == nil then
                return false, path .. " is missing " .. tostring(key)
            end
        end
        return true
    end

    local ok, reason = compare(actual, expected, "value")
    if not ok then
        fail(label, reason)
    end
end

function Test.run(label, callback)
    local ok, err = pcall(callback)
    if not ok then
        error("FAIL: " .. label .. " - " .. tostring(err), 0)
    end
    print("PASS: " .. label)
end

return Test
```

- [ ] **Step 2: Add the addon-file loader.**

```lua
local function loadAddonFile(path, addon)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk("MarkdownNotes", addon)
end

return loadAddonFile
```

- [ ] **Step 3: Add a baseline runner and verify the harness.**

```lua
local Test = dofile("tests/assert.lua")
local loadAddonFile = dofile("tests/load_module.lua")

Test.run("test harness", function()
    Test.equal("arithmetic", 2 + 2, 4)
end)

print("All tests passed")
```

Run:

```bash
lua tests/run.lua
luac -p tests/assert.lua tests/load_module.lua tests/run.lua
```

Expected: the runner prints `PASS: test harness` and `All tests passed`, and `luac` exits successfully.

- [ ] **Step 4: Commit the harness.**

```bash
git add tests/assert.lua tests/load_module.lua tests/run.lua
git commit -m "test: add Lua module harness"
```

---

### Task 2: Implement and test the Markdown parser

**Files:**
- Create: `Markdown.lua`
- Create: `tests/markdown_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Consumes the addon table passed by the harness or WoW.
- Produces `addon.Markdown.Parse(noteId, source, checkedTasks) -> rows`.
- Each row has one of `heading`, `paragraph`, `bullet`, `ordered`, `task`, `code`, `separator`, or `spacer` kinds.
- Each row has `segments`; list rows have `indent`; ordered rows have `number`; task rows have `taskKey` and `checked`.

- [ ] **Step 1: Add failing parser tests.**

```lua
return function(addon, Test)
    Test.run("Markdown parses blocks and task state", function()
        local rows = addon.Markdown.Parse(
            "note-1",
            "# Weekly goals\n- [ ] Buy flasks\n- [x] Finish quest\n1. Open the map\n---",
            {}
        )

        Test.equal("row count", #rows, 5)
        Test.equal("heading kind", rows[1].kind, "heading")
        Test.equal("heading level", rows[1].level, 1)
        Test.equal("first task kind", rows[2].kind, "task")
        Test.equal("first task checked", rows[2].checked, false)
        Test.equal("second task checked", rows[3].checked, true)
        Test.equal("ordered kind", rows[4].kind, "ordered")
        Test.equal("separator kind", rows[5].kind, "separator")
    end)

    Test.run("Markdown creates deterministic duplicate task keys", function()
        local source = "- [ ] Check\n- [ ] Check"
        local rows = addon.Markdown.Parse("note-2", source, {})
        Test.equal("first key", rows[1].taskKey, "note-2:check:1")
        Test.equal("second key", rows[2].taskKey, "note-2:check:2")
    end)

    Test.run("Markdown returns inline segments", function()
        local rows = addon.Markdown.Parse("note-3", "**Important** *soon* `code` [guide](https://example.com)", {})
        Test.equal("paragraph kind", rows[1].kind, "paragraph")
        local kinds = {}
        local link
        for _, segment in ipairs(rows[1].segments) do
            kinds[segment.kind] = (kinds[segment.kind] or 0) + 1
            if segment.kind == "link" then
                link = segment
            end
        end
        Test.equal("bold segment count", kinds.bold, 1)
        Test.equal("italic segment count", kinds.italic, 1)
        Test.equal("code segment count", kinds.code, 1)
        Test.truthy("link segment", link ~= nil)
        Test.equal("link URL", link.url, "https://example.com")
    end)

    Test.run("Markdown treats malformed syntax as text", function()
        local rows = addon.Markdown.Parse("note-4", "**unclosed |literal", {})
        Test.equal("malformed row kind", rows[1].kind, "paragraph")
        Test.equal("literal text", rows[1].segments[1].text, "**unclosed |literal")
    end)
end
```

- [ ] **Step 2: Register the suite and run it to confirm the red state.**

Update `tests/run.lua` to load `Markdown.lua` and invoke `dofile("tests/markdown_test.lua")(addon, Test)`. Run:

```bash
lua tests/run.lua
```

Expected: FAIL because `Markdown.lua` does not yet define `addon.Markdown.Parse`.

- [ ] **Step 3: Implement the minimal parser.**

Implement `Markdown.lua` with these internal stages:

1. Normalize `nil` to an empty source and convert CRLF/CR line endings to LF.
2. Split the source into lines without using `io`, `os`, or WoW-only helpers.
3. Walk lines with a fenced-code state. Opening and closing triple-backtick lines are delimiters; all lines inside become `code` rows. An unclosed fence treats the remaining lines as code.
4. Outside code fences, recognize headings before lists, task lists before ordinary unordered lists, ordered lists, separators, blank lines, and paragraph runs in that order.
5. Preserve indentation as a numeric list-row `indent` based on leading whitespace.
6. Normalize task labels with trimmed whitespace and collapsed internal spaces, lowercase the label, and append the duplicate occurrence number to `noteId .. ":" .. normalized .. ":" .. occurrence`.
7. Read `checkedTasks[taskKey] == true` to populate task-row state; do not mutate the supplied table.
8. Parse inline constructs in this precedence order: code spans, links, strong emphasis, emphasis, then plain text. If a delimiter is unmatched, emit the original characters as text.
9. Group adjacent ordinary lines into one paragraph row separated by blank lines; preserve an embedded newline in the paragraph text.

The public entry point must remain small:

```lua
local Markdown = {}

function Markdown.Parse(noteId, source, checkedTasks)
    -- normalize, scan blocks, parse inline segments, return rows
end

addon.Markdown = Markdown
```

- [ ] **Step 4: Run the parser tests and syntax checks.**

```bash
lua tests/run.lua
luac -p Markdown.lua tests/assert.lua tests/load_module.lua tests/markdown_test.lua tests/run.lua
```

Expected: all parser tests pass and `luac` exits successfully.

- [ ] **Step 5: Commit the parser.**

```bash
git add Markdown.lua tests/markdown_test.lua tests/run.lua
git commit -m "feat: add Markdown render-model parser"
```

---

### Task 3: Implement and test account-wide storage

**Files:**
- Create: `Storage.lua`
- Create: `tests/storage_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Consumes an optional database table and an injected clock function.
- Produces the complete `Storage` interface defined above.
- Returns `nil, "empty-title"` from `CreateNote` or `UpdateNote` when the trimmed title is empty.
- Returns `false` for mutations targeting missing note IDs.

- [ ] **Step 1: Add failing storage tests.**

```lua
return function(addon, Test)
    Test.run("Storage creates account-wide notes", function()
        local store = addon.Storage.Create(nil, function() return 1700000000 end)
        local note, err = store:CreateNote("Tonight", "- [ ] World boss")

        Test.equal("create error", err, nil)
        Test.equal("note id", note.id, "note-1")
        Test.equal("title", note.title, "Tonight")
        Test.equal("timestamp", note.createdAt, 1700000000)
        Test.equal("order entry", store:GetDatabase().notes.order[1], "note-1")
    end)

    Test.run("Storage preserves source and toggles checklist state", function()
        local store = addon.Storage.Create({}, function() return 100 end)
        local note = store:CreateNote("Checklist", "- [ ] A")
        local source = note.markdown

        Test.truthy("set checked", store:SetTaskChecked(note.id, "note-1:a:1", true))
        Test.equal("checked", store:IsTaskChecked(note.id, "note-1:a:1"), true)
        Test.equal("source unchanged", store:GetNote(note.id).markdown, source)
        Test.truthy("unset checked", store:SetTaskChecked(note.id, "note-1:a:1", false))
        Test.equal("unchecked", store:IsTaskChecked(note.id, "note-1:a:1"), false)
    end)

    Test.run("Storage persists overlay geometry and visibility", function()
        local store = addon.Storage.Create({}, function() return 100 end)
        local note = store:CreateNote("Overlay", "text")
        local layout = store:PinOverlay(note.id, {
            point = "CENTER", relativePoint = "CENTER",
            x = 10, y = 20, width = 320, height = 240,
        })

        Test.equal("visible", layout.visible, true)
        Test.truthy("save geometry", store:SaveOverlayGeometry(note.id, "TOP", "TOP", 1, 2, 400, 300))
        Test.truthy("lock", store:SetOverlayLocked(note.id, true))
        Test.truthy("hide", store:SetOverlayVisible(note.id, false))
        Test.equal("visible after hide", store:GetDatabase().overlays.byNoteId[note.id].visible, false)
        Test.equal("saved width", store:GetDatabase().overlays.byNoteId[note.id].width, 400)
    end)

    Test.run("Storage rejects empty titles and cleans deleted notes", function()
        local store = addon.Storage.Create({}, function() return 100 end)
        local missing, err = store:CreateNote("   ", "body")
        Test.equal("empty title result", missing, nil)
        Test.equal("empty title error", err, "empty-title")

        local note = store:CreateNote("Delete me", "body")
        store:PinOverlay(note.id, {})
        Test.truthy("delete", store:DeleteNote(note.id))
        Test.equal("deleted note", store:GetNote(note.id), nil)
        Test.equal("deleted overlay", store:GetDatabase().overlays.byNoteId[note.id], nil)
    end)
end
```

- [ ] **Step 2: Register the suite and run the red state.**

Load `Storage.lua` before the storage suite in `tests/run.lua`, then run:

```bash
lua tests/run.lua
```

Expected: FAIL because `Storage.lua` does not yet define `addon.Storage.Create`.

- [ ] **Step 3: Implement database normalization and schema version 1.**

`Storage.Create` must accept `nil`, a non-table, or a partial table and return a store whose database has:

```lua
{
    schemaVersion = 1,
    nextNoteId = 1,
    notes = { order = {}, byId = {} },
    overlays = { byNoteId = {} },
}
```

Normalize `notes.order` by removing non-string IDs and IDs absent from `notes.byId`. Remove overlay records for absent notes. Keep only boolean `visible` and `locked` values; fill missing geometry with `CENTER/CENTER/0/0/320/240`. Keep timestamps numeric, defaulting to the injected clock value when a note is created or updated.

- [ ] **Step 4: Implement note and task operations.**

Use generated IDs by concatenating `"note-"` with the decimal `nextNoteId`, append new IDs to `notes.order`, preserve IDs during updates, and remove IDs from both the order list and lookup table on deletion. Store only `true` values in `checkedTasks`; remove a task key when setting it false. Trim title whitespace for validation and storage, but preserve Markdown source exactly.

- [ ] **Step 5: Implement overlay operations.**

`PinOverlay` creates or updates a layout, sets `visible = true`, and applies defaults only to missing fields. `SetOverlayVisible` and `SetOverlayLocked` update one boolean. `SaveOverlayGeometry` writes the six geometry fields. `ListVisibleOverlays` follows note order and returns `{ noteId = id, layout = layout }` entries. `ResetOverlays` replaces geometry with the defaults while preserving each layout’s `visible` and `locked` flags.

- [ ] **Step 6: Run all pure tests and syntax checks.**

```bash
lua tests/run.lua
luac -p Storage.lua Markdown.lua tests/*.lua
```

Expected: all parser and storage tests pass.

- [ ] **Step 7: Commit storage.**

```bash
git add Storage.lua tests/storage_test.lua tests/run.lua
git commit -m "feat: add account-wide note storage"
```

---

### Task 4: Add the addon manifest and startup coordinator

**Files:**
- Create: `MarkdownNotes.toc`
- Create: `Core.lua`

**Interfaces:**
- Consumes `addon.Storage.Create`, `addon.Renderer.Create`, `addon.NoteManager.Create`, `addon.Editor.Create`, `addon.Overlay.Create`, and `addon.Commands.Register` from later tasks.
- Produces `addon.store`, `addon.renderer`, `addon.manager`, `addon.editor`, `addon.overlay`, `addon:RefreshNote(noteId)`, and `addon:RefreshAll()`.

- [ ] **Step 1: Create the TOC with exact load order and metadata.**

```text
## Interface: 120100
## Title: MarkdownNotes
## Notes: Create and display Markdown notes as in-game overlays.
## Version: 0.1.0
## Author: MarkdownNotes
## SavedVariables: MarkdownNotesDB

Core.lua
Storage.lua
Markdown.lua
Renderer.lua
NoteManager.lua
Editor.lua
Overlay.lua
Commands.lua
```

Do not add `Dependencies`, `SavedVariablesPerCharacter`, or embedded libraries.

- [ ] **Step 2: Create the shared namespace and event coordinator.**

`Core.lua` must begin with `local addonName, addon = ...` and use the private table passed to every addon file. Register `ADDON_LOADED` and `PLAYER_LOGIN` on one frame. On the matching `ADDON_LOADED`, create the store with `MarkdownNotesDB` and the WoW `time` function, then assign `MarkdownNotesDB = addon.store:GetDatabase()` so first-run databases become the declared SavedVariable.

On `PLAYER_LOGIN`, construct dependencies in this order:

```lua
addon.renderer = addon.Renderer.Create()
addon.overlay = addon.Overlay.Create(addon)
addon.editor = addon.Editor.Create(addon)
addon.manager = addon.NoteManager.Create(addon)
addon.Commands.Register(addon)
addon.overlay:RestoreVisible()
```

Implement coordinator methods as:

```lua
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
```

`Overlay:RefreshAll` is an internal extension of the public interface and refreshes all active frames.

- [ ] **Step 3: Syntax-check the manifest-era files.**

The UI constructor calls will not run until the later modules exist. Verify Lua syntax now:

```bash
luac -p Core.lua Storage.lua Markdown.lua tests/*.lua
```

- [ ] **Step 4: Commit the manifest and coordinator.**

```bash
git add MarkdownNotes.toc Core.lua
git commit -m "feat: add addon manifest and startup lifecycle"
```

---

### Task 5: Implement the renderer widget adapter

**Files:**
- Create: `Renderer.lua`
- Create: `tests/renderer_test.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Consumes render-model rows from `Markdown.Parse`.
- Produces `Renderer.EscapeText`, `Renderer.BuildInlineMarkup`, `Renderer.Create`, `renderer:Clear`, and `renderer:Render`.
- `onTaskClick(taskKey, checked)` is called by a task button after the user changes it.

- [ ] **Step 1: Add pure renderer helper tests.**

```lua
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
end
```

- [ ] **Step 2: Register the tests and run the red state.**

Load `Renderer.lua` and the suite in `tests/run.lua`. Run `lua tests/run.lua`; expect failure because the renderer module is absent.

- [ ] **Step 3: Implement text escaping and inline markup.**

Escape every literal pipe by doubling it before adding addon-generated color markup. Map inline segments centrally: ordinary text uses the normal style, `bold` uses a highlighted Blizzard color/font treatment, `italic` uses a subdued emphasis treatment, `code` uses a code color, and `link` displays its label plus a safe destination hint without launching a browser. Keep this mapping in `BuildInlineMarkup` so Markdown never emits WoW escape sequences.

- [ ] **Step 4: Implement row creation and reuse.**

Create a renderer object with a weakly coupled row pool stored on each content parent. `Render` hides unused rows, creates missing rows, anchors visible rows vertically, sets the parent content height, and handles these row kinds:

- `heading`: one wrapped `FontString` with level styling.
- `paragraph`: one wrapped `FontString` with inline markup.
- `bullet` and `ordered`: indentation plus safe marker and wrapped text.
- `task`: a `CheckButton` plus wrapped label; initialize `SetChecked` before installing the click script, and call `onTaskClick(row.taskKey, button:GetChecked())` on click.
- `code`: a wrapped code-style `FontString`.
- `separator`: a thin texture or line.
- `spacer`: fixed vertical space.

Use `SetWidth`, `SetWordWrap(true)`, `GetStringHeight()`, and explicit row heights. `Clear` hides all pooled rows and resets the content height. The renderer must not access `MarkdownNotesDB`.

- [ ] **Step 5: Run pure tests and syntax checks.**

```bash
lua tests/run.lua
luac -p Renderer.lua Markdown.lua Storage.lua tests/*.lua
```

Expected: all pure tests pass.

- [ ] **Step 6: Commit the renderer.**

```bash
git add Renderer.lua tests/renderer_test.lua tests/run.lua
git commit -m "feat: render Markdown rows with native widgets"
```

---

### Task 6: Build the note manager and library flow

**Files:**
- Create: `NoteManager.lua`

**Interfaces:**
- Consumes `addon.store`, `addon.renderer`, `addon.editor`, and `addon.overlay`.
- Produces `addon.NoteManager.Create(addon)` and the manager methods from the contract.
- Calls `addon:RefreshNote(noteId)` after a task click and after a successful delete.

- [ ] **Step 1: Create the manager frame shell.**

Create `MarkdownNotesManagerFrame` as an addon-owned `Frame` parented to `UIParent` with `BackdropTemplate`, size `640x420`, centered by default, movable by its title bar, and hidden initially. Add a title bar, close button, New button, Edit button, Delete button, Pin button, Unpin button, a title filter `EditBox`, a left `ScrollFrame` for note rows, and a right `ScrollFrame` for the selected preview.

- [ ] **Step 2: Implement ordered note-list refresh.**

`RefreshList` calls `store:ListNotes(filterText)`, reuses list-button rows, labels each with the note title, and selects the existing selected ID when it remains in the result. If no note remains, clear the selection and disable Edit/Delete/Pin/Unpin. A row click calls `manager:Select(note.id)`.

- [ ] **Step 3: Implement selection and preview refresh.**

`Select(noteId)` verifies that `store:GetNote(noteId)` exists, stores the ID, refreshes button states, and calls `RefreshPreview(noteId)`. `RefreshPreview` parses the note with:

```lua
local rows = addon.Markdown.Parse(note.id, note.markdown, note.checkedTasks)
addon.renderer:Render(previewContent, rows, function(taskKey, checked)
    if addon.store:SetTaskChecked(note.id, taskKey, checked) then
        addon:RefreshNote(note.id)
    end
end)
```

- [ ] **Step 4: Wire manager actions.**

New calls `addon.editor:OpenNew()`. Edit calls `addon.editor:Open(selectedId)`. Delete displays a confirmation dialog; on confirmation it calls `store:DeleteNote(selectedId)`, clears selection, and refreshes all manager/overlay consumers. Pin and Unpin call `addon.overlay:Pin(selectedId)` and `addon.overlay:Unpin(selectedId)`. Search refreshes the list on `OnTextChanged` without an `OnUpdate` loop.

- [ ] **Step 5: Verify the manager in-game after the editor/overlay modules exist.**

Perform the manager checks listed in the final verification task after dependencies are present; at this stage verify frame construction and list selection in a test client session.

- [ ] **Step 6: Commit the manager.**

```bash
git add NoteManager.lua
git commit -m "feat: add note manager library window"
```

---

### Task 7: Build the Markdown editor and draft lifecycle

**Files:**
- Create: `Editor.lua`

**Interfaces:**
- Consumes `addon.store`, `addon.renderer`, and `addon:RefreshNote`/`addon:RefreshAll`.
- Produces `addon.Editor.Create(addon)`, `OpenNew`, `Open`, `Close`, and `RefreshPreview`.
- Does not write draft changes until Save.

- [ ] **Step 1: Create the editor frame and fields.**

Create a hidden `MarkdownNotesEditorFrame` with `BackdropTemplate`, size `720x500`, a title `EditBox`, a multiline source `EditBox` inside a `ScrollFrame`, a preview toggle or right-side preview `ScrollFrame`, Save, Cancel, and Close controls. Use `SetMultiLine(true)`, `SetAutoFocus(false)`, and a readable font object for source text. Keep a `draftNoteId` and `suppressTextChanged` flag.

- [ ] **Step 2: Implement open and draft initialization.**

`OpenNew` clears `draftNoteId`, sets title to `New note`, clears source, and displays the editor. `Open(noteId)` copies the selected note’s title and Markdown into the fields and stores its ID. Both functions set `suppressTextChanged` while loading and refresh the preview after loading.

- [ ] **Step 3: Implement preview refresh.**

When the preview is visible, title/source `OnTextChanged` calls `RefreshPreview` unless `suppressTextChanged` is true. For an existing note, use its saved ID and saved checkbox state. For a new draft, use the literal preview ID `draft` and an empty checked-state table. Render through the same `addon.renderer:Render` call used by the manager.

- [ ] **Step 4: Implement validation and Save/Cancel.**

On Save, trim the title. If it is empty, show an inline validation message and leave the editor open. Otherwise:

```lua
local note, err
if editor.draftNoteId then
    note, err = addon.store:UpdateNote(editor.draftNoteId, title, source)
else
    note, err = addon.store:CreateNote(title, source)
end
```

If `note` is returned, close the editor, select the saved note in the manager, and call `addon:RefreshAll()`. Cancel and Close hide the editor without changing storage.

- [ ] **Step 5: Verify draft isolation.**

In-game, type into a new draft, close it with Cancel, reopen New, and confirm the discarded text is gone. Edit an existing note, cancel, and confirm its overlay still displays the old source. Save and confirm manager and overlay content refresh.

- [ ] **Step 6: Commit the editor.**

```bash
git add Editor.lua
git commit -m "feat: add in-game Markdown editor"
```

---

### Task 8: Implement movable, resizable note overlays

**Files:**
- Create: `Overlay.lua`

**Interfaces:**
- Consumes `addon.store`, `addon.renderer`, and `addon.Markdown.Parse`.
- Produces `addon.Overlay.Create(addon)`, `Pin`, `Unpin`, `UnpinAll`, `RestoreVisible`, `Refresh`, `RefreshAll`, and `Reset`.

- [ ] **Step 1: Create the overlay manager and frame factory.**

Maintain `framesByNoteId`. `createFrame(noteId)` creates an addon-owned `Frame` parented to `UIParent` with `BackdropTemplate`, default size `320x240`, a title bar, title text, Lock and Unpin buttons, a scrollable body/content frame, and a resize handle. Set the overlay frame strata to a visible non-dialog strata and enable mouse input.

- [ ] **Step 2: Implement pin and restore behavior.**

`Pin(noteId)` verifies the note exists, calls `store:PinOverlay` with default geometry and an offset derived from the number of active frames, creates/reuses the frame, applies saved geometry and lock state, refreshes its body, and shows it. `RestoreVisible` iterates `store:ListVisibleOverlays()` in note order and calls the same frame setup without resetting saved geometry.

- [ ] **Step 3: Implement movement, resizing, and layout persistence.**

When unlocked, the title bar calls `StartMoving`/`StopMovingOrSizing`; the stop handler reads `GetPoint(1)` and calls `store:SaveOverlayGeometry`. Configure `SetResizable(true)` and `SetResizeBounds(240, 120, 800, 800)`. The resize handle calls `StartSizing("BOTTOMRIGHT")`; `OnSizeChanged` saves width and height and calls `Refresh(noteId)` so wrapped rows reflow. When locked, disable movement and sizing but leave body task buttons enabled.

- [ ] **Step 4: Implement body rendering and task callbacks.**

`Refresh(noteId)` gets the note, hides/removes a stale frame if the note no longer exists, parses the source with current `checkedTasks`, and calls:

```lua
addon.renderer:Render(content, rows, function(taskKey, checked)
    if addon.store:SetTaskChecked(noteId, taskKey, checked) then
        addon:RefreshNote(noteId)
    end
end)
```

The callback must not update the Markdown source.

- [ ] **Step 5: Implement unpin, reset, and recovery.**

`Unpin(noteId)` sets the layout visible flag false, hides the frame, and retains geometry for later repinning. `UnpinAll` applies that operation to every active frame. `Reset` calls `store:ResetOverlays`, reapplies default geometry to active frames, and refreshes them. Clamp saved points after applying them so a resolution/UI-scale change cannot leave a window unreachable.

- [ ] **Step 6: Verify overlay behavior in-game.**

Pin two notes, confirm they receive different default offsets, drag and resize both, lock one, click its checklist item, unpin one, reload, and verify only the still-visible overlay restores with its saved layout.

- [ ] **Step 7: Commit the overlay manager.**

```bash
git add Overlay.lua
git commit -m "feat: add persistent note overlays"
```

---

### Task 9: Add slash commands and complete startup integration

**Files:**
- Create: `Commands.lua`
- Create: `tests/commands_test.lua`
- Modify: `tests/run.lua`
- Modify: `Core.lua` if constructor guards or refresh wiring need final integration.

**Interfaces:**
- Produces `Commands.Parse(text) -> verb, argument` and registers `/mn` through `SlashCmdList`.
- Consumes `addon.manager`, `addon.editor`, `addon.overlay`, and `addon.store`.

- [ ] **Step 1: Add command parser tests.**

```lua
return function(addon, Test)
    Test.run("Commands parses empty input", function()
        local verb, argument = addon.Commands.Parse("")
        Test.equal("verb", verb, "")
        Test.equal("argument", argument, "")
    end)

    Test.run("Commands preserves a multi-word title", function()
        local verb, argument = addon.Commands.Parse("pin Raid prep")
        Test.equal("verb", verb, "pin")
        Test.equal("argument", argument, "Raid prep")
    end)
end
```

- [ ] **Step 2: Register the red suite, then implement parsing.**

Use Lua pattern matching rather than `strsplit` so the test harness remains standard Lua:

```lua
function Commands.Parse(text)
    local verb, argument = string.match(text or "", "^%s*(%S*)%s*(.-)%s*$")
    return string.lower(verb or ""), argument or ""
end
```

Run `lua tests/run.lua` and expect the new suite to fail before implementation, then pass after implementation.

- [ ] **Step 3: Register `/mn` and dispatch commands.**

Define:

```lua
SLASH_MARKDOWNNOTES1 = "/mn"
SlashCmdList.MARKDOWNNOTES = function(message)
    local verb, argument = addon.Commands.Parse(message)
    if verb == "" then
        addon.manager:Toggle()
    elseif verb == "new" then
        addon.editor:OpenNew()
    elseif verb == "pin" then
        local requested = string.lower(argument)
        local match
        for _, note in ipairs(addon.store:ListNotes()) do
            if string.lower(note.title) == requested then
                match = note
                break
            end
        end
        if match then
            addon.overlay:Pin(match.id)
        else
            print("MarkdownNotes: no note matched that title")
        end
    elseif verb == "unpin" and string.lower(argument) == "all" then
        addon.overlay:UnpinAll()
    elseif verb == "show" then
        addon.manager:Open()
        addon.overlay:RestoreVisible()
    elseif verb == "reset" then
        addon.overlay:Reset()
    else
        print("Usage: /mn | /mn new | /mn pin TITLE | /mn unpin all | /mn show | /mn reset")
    end
end
```

For `pin`, compare `string.lower(note.title)` with `string.lower(argument)`. If no exact match exists, print a concise usage message and leave existing UI unchanged. Empty input toggles the manager. Unknown commands print the supported command list.

- [ ] **Step 4: Complete Core constructor ordering and refresh callbacks.**

Confirm every constructor is called after `ADDON_LOADED` has created `addon.store`, every module is listed in the `.toc`, and `PLAYER_LOGIN` restores overlays only after manager/editor/renderer construction. Confirm task callbacks call `addon:RefreshNote` and save geometry through `Storage`.

- [ ] **Step 5: Run pure tests and syntax checks.**

```bash
lua tests/run.lua
luac -p Core.lua Storage.lua Markdown.lua Renderer.lua NoteManager.lua Editor.lua Overlay.lua Commands.lua tests/*.lua
```

Expected: all pure tests pass and every Lua file parses successfully.

- [ ] **Step 6: Commit command integration.**

```bash
git add Commands.lua tests/commands_test.lua tests/run.lua Core.lua
git commit -m "feat: add MarkdownNotes slash commands"
```

---

### Task 10: Execute final verification and document the smoke-test result

**Files:**
- Modify: none required for a passing implementation; if verification exposes a defect, modify only the responsible module and add a regression test beside the existing suite.

**Interfaces:**
- Consumes the complete addon from Tasks 1–9.
- Produces passing pure tests, a syntax-clean addon, and a completed in-game smoke checklist.

- [ ] **Step 1: Run the complete pure test suite.**

```bash
lua tests/run.lua
```

Expected: every test prints `PASS` and the process exits with code 0.

- [ ] **Step 2: Run Lua syntax validation.**

```bash
luac -p Core.lua Storage.lua Markdown.lua Renderer.lua NoteManager.lua Editor.lua Overlay.lua Commands.lua tests/*.lua
```

Expected: no parser output and exit code 0.

- [ ] **Step 3: Verify the installed addon in the target client.**

With the addon enabled in Retail Midnight 12.1, enable script errors, reload the UI, and exercise this exact sequence:

1. Run `/mn`; confirm manager opens and closes.
2. Choose New, save `Tonight` with headings, bullets, a code span, and two task items.
3. Reload with `/reload`; confirm the note remains.
4. Pin `Tonight`; move and resize its overlay.
5. Pin a second note; confirm both overlays remain independently visible.
6. Lock the first overlay and confirm dragging/resizing is disabled while its checklist remains clickable.
7. Click a task; confirm the Markdown source remains unchanged and the check state survives `/reload`.
8. Edit the note, save it, and confirm manager/overlay previews update.
9. Delete the pinned note; confirm the overlay disappears and stale storage is removed.
10. Move an overlay off-screen, reload, and run `/mn reset`; confirm it is recoverable.
11. Enter malformed Markdown containing literal pipes; confirm readable text and no script error.

- [ ] **Step 4: Inspect the final repository state.**

```bash
git status --short
git log --oneline --decorate -12
```

Expected: only intentional untracked skill/session files remain, all addon and test files are committed, and the task commits appear in dependency order.

- [ ] **Step 5: Commit any final regression fix.**

If a defect was found, add a focused regression test, fix the responsible module, rerun both verification commands and the affected in-game step, then commit:

```bash
git add Core.lua Storage.lua Markdown.lua Renderer.lua NoteManager.lua Editor.lua Overlay.lua Commands.lua tests
git commit -m "fix: address MarkdownNotes verification issue"
```

If no defect was found, do not create an empty commit.

---

## Self-review checklist

- **Spec coverage:** Tasks 2 and 5 cover the Markdown language and UI-independent render model; Task 3 covers account-wide storage, migrations, task state, and overlay geometry; Tasks 4 and 9 cover TOC metadata, loading lifecycle, and commands; Tasks 6–8 cover manager, editor, overlays, movement, resizing, locking, restoration, and deletion; Task 10 covers every in-game acceptance criterion.
- **Completeness scan:** Every step contains concrete implementation details; each UI behavior has a target file, interface, or verification action.
- **Type consistency:** `Markdown.Parse` returns rows consumed by `Renderer:Render`; `Storage.Create` returns the methods used by manager, editor, overlay, and Core; task callbacks use `(taskKey, checked)`; refresh methods use note IDs consistently.
- **Scope check:** The plan implements one integrated MVP. External synchronization, categories, context switching, full CommonMark, and browser launching remain explicitly excluded.
- **Dependency check:** Tasks are ordered so pure modules and their tests precede UI consumers; Core startup is completed only after all constructors and command registration exist.
