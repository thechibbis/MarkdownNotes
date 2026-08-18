# MarkdownNotes MVP Design

- **Date:** 2026-08-18
- **Target:** World of Warcraft Retail Midnight 12.1
- **Status:** Approved for specification review

## 1. Goal

MarkdownNotes is a dependency-free World of Warcraft Retail addon for creating, storing, browsing, and displaying personal Markdown notes in-game. Its primary use is general-purpose: raid notes, profession references, quest reminders, shopping lists, and session checklists should all use the same note library.

The core display feature is a set of user-controlled overlay windows. A user can pin several different notes at the same time, move and resize their windows, and interact with checklist items without opening the editor.

## 2. MVP decisions

The MVP will provide:

- An in-game note manager opened with `/mn`.
- An in-game editor for a title and raw Markdown source.
- Account-wide SavedVariables shared by all characters.
- A practical, explicitly limited Markdown subset.
- Multiple independent pinned note overlays.
- Movable, resizable, and lockable overlay windows.
- Interactive task-list checkboxes whose state persists separately from the Markdown source.
- No external libraries and no filesystem access.

The MVP will not provide:

- External `.md` file synchronization.
- Categories, tags, folders, or collaborative editing.
- Automatic context or encounter-based note switching.
- Full CommonMark compatibility.
- Raw HTML, embedded Lua, scripts, images, tables, or external browser launching.

## 3. Architecture

The addon will use native WoW UI widgets and focused Lua modules. The `.toc` file will load the modules in dependency order. The target 12.1 `.toc` metadata will use the client interface number for the shipped 12.1 build.

```text
MarkdownNotes/
├── MarkdownNotes.toc
├── Core.lua              -- namespace, defaults, startup events
├── Storage.lua           -- account-wide notes, layouts, migrations
├── Markdown.lua          -- Markdown source -> render model
├── NoteManager.lua       -- note list, selection, CRUD actions
├── Editor.lua            -- title/source editor and preview
├── Overlay.lua           -- pinned note windows and layout state
├── Renderer.lua          -- render model -> WoW widgets
└── Commands.lua          -- /mn commands
```

### Module interfaces and seams

- **Core** exposes the addon namespace and coordinates initialization. It does not own note data or widget details.
- **Storage** is the persistence seam. It initializes and migrates `MarkdownNotesDB`, validates records, and exposes note, checklist, and layout operations. UI modules do not edit SavedVariables tables directly.
- **Markdown** is a pure parsing module. Given a note ID, Markdown source, and checkbox state, it returns a deterministic render model. It does not create frames or access SavedVariables.
- **Renderer** consumes a render model and a parent content frame. It owns row creation/reuse, layout, text styling, and task-button callbacks. It does not decide where note data is stored.
- **NoteManager** owns the library window and selection flow.
- **Editor** owns draft fields and save/cancel behavior. Draft changes are not written until Save.
- **Overlay** owns the collection of pinned windows, movement/resizing, restore, and layout persistence.
- **Commands** translates slash-command text into calls to the manager and overlay interfaces.

The parser and storage seams are intentionally deep: callers provide small inputs and receive complete results without knowing parsing or persistence implementation details. This makes them independently testable and keeps UI changes local.

### Loading and lifecycle

The `.toc` will declare one account-wide variable:

```text
## SavedVariables: MarkdownNotesDB
```

`Core` listens for `ADDON_LOADED` and initializes/migrates the database when the event identifies `MarkdownNotes`. It listens for `PLAYER_LOGIN` to create the manager, editor, and overlay infrastructure and then restores overlay records marked visible. The addon is event-driven and does not require a continuous `OnUpdate` loop.

## 4. Data model

The first schema is:

```lua
MarkdownNotesDB = {
    schemaVersion = 1,
    nextNoteId = 3,

    notes = {
        order = { "note-1", "note-2" },

        byId = {
            ["note-1"] = {
                title = "Raid prep",
                markdown = "# Before pull\\n- [ ] Check flasks",
                createdAt = 0,
                updatedAt = 0,
                checkedTasks = {
                    ["note-1:check-flasks:1"] = true,
                },
            },
        },
    },

    overlays = {
        byNoteId = {
            ["note-1"] = {
                visible = true,
                locked = false,
                point = "CENTER",
                relativePoint = "CENTER",
                x = 160,
                y = 40,
                width = 320,
                height = 240,
            },
        },
    },
}
```

Notes use stable generated IDs rather than titles. `notes.order` controls library order, while `notes.byId` provides direct lookup. `createdAt` and `updatedAt` are numeric timestamps.

Checkbox state is stored only for checked tasks. A task key is deterministic for a note, normalized task label, and occurrence number among duplicate labels. This preserves state through refreshes and ordinary re-rendering while allowing substantially changed tasks to begin unchecked. Duplicate identical tasks are disambiguated by occurrence order; their state may follow the occurrence if the user reorders them.

An overlay record is retained while a note is pinned so that repinning can reuse its previous size and position. `visible` determines whether it is restored or shown; unpinning clears the active visible state while keeping the note itself. Deleting a note removes its checkbox state and overlay record.

The database is account-wide. No `SavedVariablesPerCharacter` variable is used. Storage creates missing tables and defaults on first run and applies explicit migrations whenever `schemaVersion` is older than the current schema.

## 5. Markdown language

The parser is line-oriented and intentionally smaller than CommonMark.

### Block syntax

Supported block forms:

- ATX headings with one to three `#` characters.
- Unordered list items beginning with `-` or `*`.
- Ordered list items beginning with a number and `.`.
- Task items beginning with `- [ ]` or `- [x]`; `X` is accepted case-insensitively for checked tasks.
- Basic indentation for nested list items.
- Horizontal separators consisting of three or more hyphens.
- Fenced code blocks delimited by triple backticks.
- Plain paragraphs and blank lines.

### Inline syntax

Supported inline forms:

- `**bold**` and `__bold__`.
- `*italic*` and `_italic_`.
- `` `inline code` ``.
- `[label](url)` links.

Markdown links are displayed safely as formatted text. The MVP does not open external websites. Unsupported syntax, unmatched delimiters, and malformed blocks are displayed as readable literal text.

The parser returns a UI-independent model. A row contains a `kind`, layout metadata, and inline `segments`. Task rows additionally contain a deterministic `taskKey` and current `checked` state.

```lua
{
    {
        kind = "heading",
        level = 1,
        segments = {
            { kind = "text", text = "Weekly goals" },
        },
    },
    {
        kind = "task",
        indent = 0,
        taskKey = "note-1:buy-flasks:1",
        checked = false,
        segments = {
            { kind = "text", text = "Buy flasks" },
        },
    },
}
```

`Markdown` never applies WoW escape sequences itself. `Renderer` escapes user text before adding its own font colors, sizes, and emphasis markup so note content cannot inject UI markup.

## 6. Rendering

`Renderer` renders both manager previews and overlays from the same model. Each content region uses a scrollable child frame. Rows are created or reused for headings, paragraphs, lists, code, separators, and task items.

- Headings use distinct Blizzard font objects or controlled font sizes/colors by level.
- Lists receive indentation and visible bullet/number prefixes.
- Code uses a readable monospace-style font treatment where available.
- Wrapped rows calculate their height from the available content width.
- Resizing an overlay triggers a layout refresh so wrapped text reflows.
- Task rows contain real `CheckButton` widgets and a text region.
- A task click calls `Storage` to toggle that task key, then refreshes the manager preview and the corresponding overlay.

The renderer owns visual row lifecycle and callbacks but never mutates note records directly. The first implementation may rebuild visible rows on refresh while reusing row frames; it will not use a per-frame update loop.

## 7. User interface and workflows

### Manager

`/mn` toggles a manager frame containing:

- An ordered note list.
- New, Edit, Delete, Pin, and Unpin controls.
- A title filter.
- A rendered preview of the selected note.
- Close behavior that leaves saved notes untouched.

Actions that require a selected note are disabled when no note is selected. The manager uses the same Renderer as overlays, ensuring consistent formatting.

### Editor

The editor contains:

- A title input.
- A multiline raw Markdown input.
- A preview pane or preview toggle.
- Save and Cancel buttons.

New notes receive a generated ID and default title. Save rejects an empty title, stores the draft Markdown, updates `updatedAt`, and refreshes any visible consumers. Empty Markdown is valid. Cancel discards the draft.

### Overlays

Pinning a note creates one addon-owned overlay for that note. Different notes can be pinned simultaneously. New overlays use a small default offset to avoid complete overlap. Each overlay has:

- A title bar used for dragging.
- A lock control that disables movement and resizing but leaves task buttons usable.
- An unpin/close control.
- A scrollable rendered body.
- A resize handle or equivalent resizing affordance.

Position, size, visibility, and lock state are persisted. Overlay records are restored after login if visible. Invalid or off-screen positions are clamped; `/mn reset` restores default layouts.

### Commands

```text
/mn              Toggle the manager
/mn new          Open a new-note editor
/mn pin <title>  Pin a matching note
/mn unpin all    Unpin all overlays
/mn show         Show the manager and visible overlays
/mn reset        Reset overlay positions and sizes
```

The manager remains the primary place for editing and note deletion. Overlays are optimized for reading and checklist interaction during play.

## 8. Error handling and constraints

- Missing or malformed database fields are replaced with defaults during initialization.
- Unknown or stale note IDs in order lists and overlay records are ignored and cleaned up.
- Parser failures are represented as literal text rather than thrown errors.
- Empty titles show an inline validation message and do not save.
- Note bodies may be empty.
- User text is escaped before it is inserted into WoW font markup.
- The addon does not access the operating system or arbitrary files.
- Only addon-owned frames are created or modified; protected Blizzard frames are not changed.
- The addon should remain usable for ordinary reading and checklist interaction during combat. Editing and layout controls are user-interface operations and are not used to control protected game actions.

## 9. Testing and acceptance criteria

### Pure-module tests

A dependency-free table-driven Lua harness will test `Markdown` with expected render models for:

- Headings and paragraphs.
- Bullets, numbered lists, indentation, and task lists.
- Checked and unchecked tasks.
- Duplicate task labels and deterministic task keys.
- Bold, italic, inline code, and links.
- Fenced code blocks.
- Blank lines, unmatched delimiters, and unsupported syntax.
- Literal pipe characters and text containing WoW-sensitive markup.

Storage tests will cover defaults, note CRUD, ordering, checkbox persistence, layout persistence, migration, and deleted-note cleanup.

### In-game smoke tests

1. `/mn` opens and closes the manager.
2. A new note can be saved and survives `/reload`.
3. The note renders consistently in the manager and an overlay.
4. Multiple overlays can be pinned, moved, resized, locked, and restored.
5. Checklist changes persist after reload without changing the Markdown source.
6. Deleting a pinned note removes its overlay safely.
7. Invalid Markdown produces no script errors.
8. Off-screen layouts can be recovered with `/mn reset`.

The MVP is complete when these behaviors work on the target Retail Midnight 12.1 client and the pure parser/storage tests pass.
