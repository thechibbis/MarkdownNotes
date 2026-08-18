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
