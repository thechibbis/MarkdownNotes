local function loadAddonFile(path, addon)
    local chunk, err = loadfile(path)
    assert(chunk, err)
    chunk("MarkdownNotes", addon)
end

return loadAddonFile
