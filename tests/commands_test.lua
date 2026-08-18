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
    Test.run("Commands registers the /mn slash handler", function()
        local previousSlashCmdList = _G.SlashCmdList
        local previousSlash = _G.SLASH_MARKDOWNNOTES1
        local previousPrint = _G.print
        _G.SlashCmdList = {}
        _G.print = function() end
        local runtime = {
            manager = {},
            editor = {},
            overlay = {},
            store = {},
        }
        local ok, err = pcall(function()
            addon.Commands.Register(runtime)
            Test.equal("slash trigger", _G.SLASH_MARKDOWNNOTES1, "/mn")
            Test.truthy("slash handler", type(_G.SlashCmdList.MARKDOWNNOTES) == "function")
        end)
        _G.SlashCmdList = previousSlashCmdList
        _G.SLASH_MARKDOWNNOTES1 = previousSlash
        _G.print = previousPrint
        if not ok then
            error(err, 0)
        end
    end)

    local function new_runtime()
        local events = {}
        local runtime = {
            manager = {},
            editor = {},
            overlay = {},
            store = {},
        }
        runtime.store.notes = {
            { id = "note-1", title = "Raid Prep" },
            { id = "note-2", title = "Daily" },
        }
        function runtime.store:ListNotes()
            return self.notes
        end
        function runtime.manager:Toggle()
            events[#events + 1] = "toggle"
        end
        function runtime.manager:Open()
            events[#events + 1] = "open"
        end
        function runtime.editor:OpenNew()
            events[#events + 1] = "new"
        end
        function runtime.overlay:Pin(noteId)
            events[#events + 1] = "pin:" .. noteId
        end
        function runtime.overlay:UnpinAll()
            events[#events + 1] = "unpin-all"
        end
        function runtime.overlay:RestoreVisible()
            events[#events + 1] = "restore"
        end
        function runtime.overlay:Reset()
            events[#events + 1] = "reset"
        end
        return runtime, events
    end

    local function with_handler(callback)
        local previousSlashCmdList = _G.SlashCmdList
        local previousSlash = _G.SLASH_MARKDOWNNOTES1
        local previousPrint = _G.print
        local messages = {}
        _G.SlashCmdList = {}
        _G.print = function(message)
            messages[#messages + 1] = message
        end
        local runtime, events = new_runtime()
        local ok, err = pcall(function()
            addon.Commands.Register(runtime)
            callback(_G.SlashCmdList.MARKDOWNNOTES, runtime, events, messages)
        end)
        _G.SlashCmdList = previousSlashCmdList
        _G.SLASH_MARKDOWNNOTES1 = previousSlash
        _G.print = previousPrint
        if not ok then
            error(err, 0)
        end
    end

    Test.run("Commands dispatches supported UI commands", function()
        with_handler(function(handler, _, events)
            handler("")
            handler("new")
            handler("unpin all")
            handler("show")
            handler("reset")
            Test.deepEqual("UI command events", events, {
                "toggle",
                "new",
                "unpin-all",
                "open",
                "restore",
                "reset",
            })
        end)
    end)

    Test.run("Commands pins an exact title case-insensitively", function()
        with_handler(function(handler, _, events)
            handler("pin raid prep")
            Test.equal("pin event", events[1], "pin:note-1")
        end)
    end)

    Test.run("Commands rejects non-exact prefix and substring titles", function()
        with_handler(function(handler, _, events, messages)
            handler("pin Raid")
            handler("pin Prep")
            Test.equal("no non-exact UI events", #events, 0)
            Test.equal("prefix message", messages[1], "MarkdownNotes: no note matched that title")
            Test.equal("substring message", messages[2], "MarkdownNotes: no note matched that title")
        end)
    end)

    Test.run("Commands reports a missing pin without changing UI", function()
        with_handler(function(handler, _, events, messages)
            handler("pin Missing")
            Test.equal("no UI event", #events, 0)
            Test.equal("missing title message", messages[1], "MarkdownNotes: no note matched that title")
        end)
    end)

    Test.run("Commands reports usage for unknown input", function()
        with_handler(function(handler, _, events, messages)
            handler("archive")
            Test.equal("no unknown command event", #events, 0)
            Test.equal("usage message", messages[1], "Usage: /mn | /mn new | /mn pin TITLE | /mn unpin all | /mn show | /mn reset")
        end)
    end)
end
