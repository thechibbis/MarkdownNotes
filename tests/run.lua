local Test = dofile("tests/assert.lua")
local loadAddonFile = dofile("tests/load_module.lua")

Test.run("test harness", function()
    Test.equal("arithmetic", 2 + 2, 4)
end)

print("All tests passed")
