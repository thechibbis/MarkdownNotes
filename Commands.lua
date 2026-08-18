local addonName, addon = ...

addon = addon or {}

local Commands = {}

function Commands.Parse(text)
    local verb, argument = string.match(text or "", "^%s*(%S*)%s*(.-)%s*$")
    return string.lower(verb or ""), argument or ""
end
function Commands.Register(addon)
    SLASH_MARKDOWNNOTES1 = "/mn"
    SlashCmdList.MARKDOWNNOTES = function(message)
        local verb, argument = Commands.Parse(message)
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
end

addon.Commands = Commands
