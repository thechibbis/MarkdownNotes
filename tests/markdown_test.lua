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
    Test.run("Markdown normalizes line endings and nil source", function()
        local emptyRows = addon.Markdown.Parse("empty", nil, {})
        Test.equal("nil source rows", #emptyRows, 0)
        local rows = addon.Markdown.Parse("lines", "first\r\nsecond\rthird", {})
        Test.deepEqual("normalized paragraph", rows, {
            {
                kind = "paragraph",
                segments = {
                    { kind = "text", text = "first\nsecond\nthird" },
                },
            },
        })
    end)

    Test.run("Markdown returns list metadata and spacer rows", function()
        local rows = addon.Markdown.Parse("lists", "* top\n  - nested\n3. numbered\n\nnext", {})
        Test.deepEqual("list rows", rows, {
            {
                kind = "bullet",
                indent = 0,
                segments = { { kind = "text", text = "top" } },
            },
            {
                kind = "bullet",
                indent = 2,
                segments = { { kind = "text", text = "nested" } },
            },
            {
                kind = "ordered",
                indent = 0,
                number = 3,
                segments = { { kind = "text", text = "numbered" } },
            },
            {
                kind = "spacer",
                segments = {},
            },
            {
                kind = "paragraph",
                segments = { { kind = "text", text = "next" } },
            },
        })
    end)

    Test.run("Markdown renders fenced and unclosed code", function()
        local rows = addon.Markdown.Parse("fence", "before\n```\n**literal**\n\n```\nafter", {})
        Test.deepEqual("closed fence rows", rows, {
            {
                kind = "paragraph",
                segments = { { kind = "text", text = "before" } },
            },
            {
                kind = "code",
                segments = { { kind = "text", text = "**literal**" } },
            },
            {
                kind = "code",
                segments = { { kind = "text", text = "" } },
            },
            {
                kind = "paragraph",
                segments = { { kind = "text", text = "after" } },
            },
        })

        local unclosed = addon.Markdown.Parse("unclosed", "```\nline\n- [ ] still code", {})
        Test.deepEqual("unclosed fence rows", unclosed, {
            {
                kind = "code",
                segments = { { kind = "text", text = "line" } },
            },
            {
                kind = "code",
                segments = { { kind = "text", text = "- [ ] still code" } },
            },
        })
    end)

    Test.run("Markdown normalizes task labels and preserves checked state input", function()
        local checkedTasks = {
            ["state:buy flasks:1"] = true,
            ["state:buy flasks:2"] = false,
        }
        local rows = addon.Markdown.Parse(
            "state",
            "  - [ ]  BUY   flasks  \n- [ ] buy flasks\n- [x] Other",
            checkedTasks
        )

        Test.deepEqual("task rows", rows, {
            {
                kind = "task",
                indent = 2,
                taskKey = "state:buy flasks:1",
                checked = true,
                segments = { { kind = "text", text = "BUY   flasks" } },
            },
            {
                kind = "task",
                indent = 0,
                taskKey = "state:buy flasks:2",
                checked = false,
                segments = { { kind = "text", text = "buy flasks" } },
            },
            {
                kind = "task",
                indent = 0,
                taskKey = "state:other:1",
                checked = true,
                segments = { { kind = "text", text = "Other" } },
            },
        })
        Test.deepEqual("checked state is not mutated", checkedTasks, {
            ["state:buy flasks:1"] = true,
            ["state:buy flasks:2"] = false,
        })
    end)

    Test.run("Markdown returns complete inline segments", function()
        local rows = addon.Markdown.Parse(
            "segments",
            "A **bold** __bold2__ *italic* _italic2_ `code` [link](https://example.com) |cffff0000literal|r",
            {}
        )
        Test.deepEqual("inline segments", rows, {
            {
                kind = "paragraph",
                segments = {
                    { kind = "text", text = "A " },
                    { kind = "bold", text = "bold" },
                    { kind = "text", text = " " },
                    { kind = "bold", text = "bold2" },
                    { kind = "text", text = " " },
                    { kind = "italic", text = "italic" },
                    { kind = "text", text = " " },
                    { kind = "italic", text = "italic2" },
                    { kind = "text", text = " " },
                    { kind = "code", text = "code" },
                    { kind = "text", text = " " },
                    { kind = "link", text = "link", url = "https://example.com" },
                    { kind = "text", text = " |cffff0000literal|r" },
                },
            },
        })
    end)

    Test.run("Markdown keeps unsupported and malformed inline syntax literal", function()
        local cases = {
            {
                label = "image",
                source = "![image](https://example.com/x.png)",
            },
            {
                label = "empty link label",
                source = "[](https://example.com)",
            },
            {
                label = "whitespace-only link label",
                source = "[ ](https://example.com)",
            },
            {
                label = "malformed link",
                source = "[guide](https://example.com",
            },
        }

        for _, case in ipairs(cases) do
            local rows = addon.Markdown.Parse("literal", case.source, {})
            Test.deepEqual(case.label, rows, {
                {
                    kind = "paragraph",
                    segments = { { kind = "text", text = case.source } },
                },
            })
        end
    end)

    Test.run("Markdown keeps malformed task markers literal", function()
        local cases = {
            "-[ ] no-space",
            "- [ ]no-space-after-checkbox",
            "- [ ]",
        }

        for _, source in ipairs(cases) do
            local rows = addon.Markdown.Parse("malformed-task", source, {})
            Test.deepEqual("malformed task: " .. source, rows, {
                {
                    kind = "paragraph",
                    segments = { { kind = "text", text = source } },
                },
            })
        end
    end)
end
