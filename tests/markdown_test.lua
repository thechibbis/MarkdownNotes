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
