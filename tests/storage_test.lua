return function(addon, Test)
    Test.run("Storage normalizes empty and non-table databases", function()
        local expected = {
            schemaVersion = 1,
            nextNoteId = 1,
            notes = { order = {}, byId = {} },
            overlays = { byNoteId = {} },
        }

        local emptyStore = addon.Storage.Create(nil, function() return 1700000000 end)
        Test.deepEqual("nil database defaults", emptyStore:GetDatabase(), expected)

        local invalidStore = addon.Storage.Create("not a database", function() return 1700000000 end)
        Test.deepEqual("non-table database defaults", invalidStore:GetDatabase(), expected)
    end)

    Test.run("Storage migrates and cleans legacy database", function()
        local database = {
            schemaVersion = 0,
            nextNoteId = 1,
            notes = {
                order = { "note-1", 17, "missing" },
                byId = {
                    ["note-1"] = {
                        title = "  Legacy  ",
                        markdown = "keep\r\nsource",
                        createdAt = "old",
                        updatedAt = false,
                        checkedTasks = {
                            ["legacy:done"] = true,
                            ["legacy:off"] = false,
                        },
                    },
                    ["note-2"] = {
                        title = "Second",
                        markdown = "second",
                        createdAt = 10,
                        updatedAt = 20,
                    },
                },
            },
            overlays = {
                byNoteId = {
                    ["note-1"] = {
                        visible = "yes",
                        locked = 1,
                        point = "TOP",
                        y = 7,
                    },
                    missing = {},
                },
            },
        }

        local store = addon.Storage.Create(database, function() return 50 end)
        local normalized = store:GetDatabase()
        local layout = normalized.overlays.byNoteId["note-1"]
        local note = normalized.notes.byId["note-1"]

        Test.equal("migrated schema", normalized.schemaVersion, 1)
        Test.equal("next id skips existing notes", normalized.nextNoteId, 3)
        Test.equal("first order entry", normalized.notes.order[1], "note-1")
        Test.equal("appended valid note", normalized.notes.order[2], "note-2")
        Test.equal("trimmed legacy title", note.title, "Legacy")
        Test.equal("legacy source preserved", note.markdown, "keep\r\nsource")
        Test.equal("invalid created timestamp default", note.createdAt, 50)
        Test.equal("invalid updated timestamp default", note.updatedAt, 50)
        Test.equal("checked state retained", note.checkedTasks["legacy:done"], true)
        Test.equal("unchecked state removed", note.checkedTasks["legacy:off"], nil)
        Test.equal("invalid visible defaults false", layout.visible, false)
        Test.equal("invalid locked defaults false", layout.locked, false)
        Test.equal("legacy point retained", layout.point, "TOP")
        Test.equal("missing relative point default", layout.relativePoint, "CENTER")
        Test.equal("missing x default", layout.x, 0)
        Test.equal("legacy y retained", layout.y, 7)
        Test.equal("missing width default", layout.width, 320)
        Test.equal("missing height default", layout.height, 240)
        Test.equal("stale overlay removed", normalized.overlays.byNoteId.missing, nil)
    end)

    Test.run("Storage creates account-wide notes", function()
        local store = addon.Storage.Create(nil, function() return 1700000000 end)
        local note, err = store:CreateNote("Tonight", "- [ ] World boss")

        Test.equal("create error", err, nil)
        Test.equal("note id", note.id, "note-1")
        Test.equal("title", note.title, "Tonight")
        Test.equal("timestamp", note.createdAt, 1700000000)
        Test.equal("order entry", store:GetDatabase().notes.order[1], "note-1")
    end)

    Test.run("Storage lists, updates, and deletes notes account-wide", function()
        local database = {}
        local now = 100
        local store = addon.Storage.Create(database, function() return now end)
        local first = store:CreateNote("  First  ", "first\r\nsource")
        local second = store:CreateNote("Second", "second")

        Test.equal("same account database", store:GetDatabase(), database)
        Test.equal("list count", #store:ListNotes(), 2)
        Test.equal("first list order", store:ListNotes()[1].id, first.id)
        Test.equal("title query count", #store:ListNotes("sec"), 1)
        Test.equal("title query result", store:ListNotes("sec")[1].id, second.id)

        now = 250
        local updated, err = store:UpdateNote(first.id, "  Updated  ", "updated\r\nsource")
        Test.equal("update error", err, nil)
        Test.equal("updated id preserved", updated.id, first.id)
        Test.equal("updated title trimmed", updated.title, "Updated")
        Test.equal("updated source preserved", updated.markdown, "updated\r\nsource")
        Test.equal("created timestamp preserved", updated.createdAt, 100)
        Test.equal("updated timestamp changed", updated.updatedAt, 250)

        Test.truthy("delete second", store:DeleteNote(second.id))
        Test.equal("deleted note absent", store:GetNote(second.id), nil)
        Test.equal("deleted order entry absent", store:GetDatabase().notes.order[2], nil)
        Test.equal("delete missing false", store:DeleteNote(second.id), false)
    end)

    Test.run("Storage rejects empty titles with exact errors", function()
        local store = addon.Storage.Create({}, function() return 100 end)
        local missing, err = store:CreateNote(" \t\n ", "body")
        Test.equal("empty create result", missing, nil)
        Test.equal("empty create error", err, "empty-title")

        local note = store:CreateNote("Valid", "original")
        local updated, updateError = store:UpdateNote(note.id, "   ", "replacement")
        Test.equal("empty update result", updated, nil)
        Test.equal("empty update error", updateError, "empty-title")
        Test.equal("failed update preserves title", store:GetNote(note.id).title, "Valid")
        Test.equal("failed update preserves source", store:GetNote(note.id).markdown, "original")
    end)

    Test.run("Storage reports missing updates after title validation", function()
        local store = addon.Storage.Create({}, function() return 100 end)
        local missing, missingError = store:UpdateNote("note-404", "Valid", "body")
        Test.equal("missing update result", missing, nil)
        Test.equal("missing update error", missingError, "missing-note")

        local blank, blankError = store:UpdateNote("note-404", "   ", "body")
        Test.equal("blank missing update result", blank, nil)
        Test.equal("blank missing update error", blankError, "empty-title")
    end)

    Test.run("Storage preserves source and toggles checklist state", function()
        local store = addon.Storage.Create({}, function() return 100 end)
        local note = store:CreateNote("Checklist", "- [ ] A")
        local source = note.markdown

        Test.truthy("set checked", store:SetTaskChecked(note.id, "note-1:a:1", true))
        Test.equal("checked", store:IsTaskChecked(note.id, "note-1:a:1"), true)
        Test.equal("stored checked value", note.checkedTasks["note-1:a:1"], true)
        Test.equal("source unchanged", store:GetNote(note.id).markdown, source)
        local updated, updateError = store:UpdateNote(note.id, "Checklist updated", "replacement\r\nsource")
        Test.equal("update error", updateError, nil)
        Test.equal("updated source exact", updated.markdown, "replacement\r\nsource")
        Test.equal("checked state survives update", updated.checkedTasks["note-1:a:1"], true)
        Test.equal("checked lookup survives update", store:IsTaskChecked(note.id, "note-1:a:1"), true)
        Test.truthy("unset checked", store:SetTaskChecked(note.id, "note-1:a:1", false))
        Test.equal("unchecked", store:IsTaskChecked(note.id, "note-1:a:1"), false)
        Test.equal("unchecked value removed", note.checkedTasks["note-1:a:1"], nil)
    end)

    Test.run("Storage returns false for missing note mutations", function()
        local store = addon.Storage.Create({}, function() return 100 end)
        local missing = "note-404"

        Test.equal("missing task mutation", store:SetTaskChecked(missing, "task", true), false)
        Test.equal("missing visible mutation", store:SetOverlayVisible(missing, true), false)
        Test.equal("missing lock mutation", store:SetOverlayLocked(missing, true), false)
        Test.equal("missing geometry mutation", store:SaveOverlayGeometry(missing, "TOP", "TOP", 1, 2, 3, 4), false)
        Test.equal("missing pin", store:PinOverlay(missing, {}), nil)
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
        Test.equal("saved point", store:GetDatabase().overlays.byNoteId[note.id].point, "TOP")
        Test.equal("saved width", store:GetDatabase().overlays.byNoteId[note.id].width, 400)
        Test.equal("saved height", store:GetDatabase().overlays.byNoteId[note.id].height, 300)

        local repinned = store:PinOverlay(note.id, { x = 999, width = 999 })
        Test.equal("repin makes visible", repinned.visible, true)
        Test.equal("repin preserves point", repinned.point, "TOP")
        Test.equal("repin preserves saved width", repinned.width, 400)
        Test.equal("repin preserves lock", repinned.locked, true)
    end)

    Test.run("Storage lists visible overlays in note order", function()
        local store = addon.Storage.Create({}, function() return 100 end)
        local first = store:CreateNote("First", "one")
        local second = store:CreateNote("Second", "two")
        local third = store:CreateNote("Third", "three")
        store:PinOverlay(first.id, {})
        store:PinOverlay(second.id, {})
        store:PinOverlay(third.id, {})
        store:SetOverlayVisible(second.id, false)

        local visible = store:ListVisibleOverlays()
        Test.equal("visible count", #visible, 2)
        Test.equal("first visible order", visible[1].noteId, first.id)
        Test.equal("second visible order", visible[2].noteId, third.id)
        Test.equal("layout reference", visible[1].layout, store:GetDatabase().overlays.byNoteId[first.id])
    end)

    Test.run("Storage resets overlay geometry without changing flags", function()
        local store = addon.Storage.Create({}, function() return 100 end)
        local hidden = store:CreateNote("Hidden", "hidden")
        local visible = store:CreateNote("Visible", "visible")
        store:PinOverlay(hidden.id, {
            point = "TOPLEFT", relativePoint = "BOTTOMRIGHT",
            x = 12, y = 13, width = 500, height = 400,
        })
        store:SetOverlayVisible(hidden.id, false)
        store:SetOverlayLocked(hidden.id, true)
        store:PinOverlay(visible.id, {
            point = "BOTTOM", relativePoint = "TOP",
            x = 22, y = 23, width = 600, height = 500,
        })

        store:ResetOverlays()
        local hiddenLayout = store:GetDatabase().overlays.byNoteId[hidden.id]
        local visibleLayout = store:GetDatabase().overlays.byNoteId[visible.id]

        Test.equal("hidden flag preserved", hiddenLayout.visible, false)
        Test.equal("hidden lock preserved", hiddenLayout.locked, true)
        Test.equal("hidden point reset", hiddenLayout.point, "CENTER")
        Test.equal("hidden relative point reset", hiddenLayout.relativePoint, "CENTER")
        Test.equal("hidden x reset", hiddenLayout.x, 0)
        Test.equal("hidden y reset", hiddenLayout.y, 0)
        Test.equal("hidden width reset", hiddenLayout.width, 320)
        Test.equal("hidden height reset", hiddenLayout.height, 240)
        Test.equal("visible flag preserved", visibleLayout.visible, true)
        Test.equal("visible lock preserved", visibleLayout.locked, false)
        Test.equal("visible geometry reset", visibleLayout.width, 320)
    end)

    Test.run("Storage rejects empty titles and cleans deleted notes", function()
        local store = addon.Storage.Create({}, function() return 100 end)
        local missing, err = store:CreateNote("   ", "body")
        Test.equal("empty title result", missing, nil)
        Test.equal("empty title error", err, "empty-title")

        local note = store:CreateNote("Delete me", "body")
        store:SetTaskChecked(note.id, "task", true)
        store:PinOverlay(note.id, {})
        Test.truthy("delete", store:DeleteNote(note.id))
        Test.equal("deleted note", store:GetNote(note.id), nil)
        Test.equal("deleted order entry", store:GetDatabase().notes.order[1], nil)
        Test.equal("deleted overlay", store:GetDatabase().overlays.byNoteId[note.id], nil)
        Test.equal("deleted task state", store:IsTaskChecked(note.id, "task"), false)
    end)
end
