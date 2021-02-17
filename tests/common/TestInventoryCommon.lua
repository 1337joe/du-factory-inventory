#!/usr/bin/env lua
--- Tests for InventoryCommon.

package.path = package.path .. ";../du-mocks/?.lua" -- add du-mocks project
package.path = package.path .. ";../game-data-lua/?.lua" -- add fallback for dkjson

local lu = require("luaunit")
local json = require("dkjson")


local mockDatabankUnit = require("dumocks.DatabankUnit")

local ic = require("common.InventoryCommon")

_G.TestInventoryCommon = {}

function _G.TestInventoryCommon.testJsonToIntList()
    local jsonStr, expected, actual

    -- empty
    jsonStr = "[]"
    expected = json.decode(jsonStr)
    actual = ic.jsonToIntList(jsonStr)
    lu.assertEquals(actual, expected)

    -- single element
    jsonStr = "[1]"
    expected = json.decode(jsonStr)
    actual = ic.jsonToIntList(jsonStr)
    lu.assertEquals(actual, expected)

    -- multiple elements
    jsonStr = "[1,2]"
    expected = json.decode(jsonStr)
    actual = ic.jsonToIntList(jsonStr)
    lu.assertEquals(actual, expected)

    -- handles spaces
    jsonStr = "[1, 2]"
    expected = json.decode(jsonStr)
    actual = ic.jsonToIntList(jsonStr)
    lu.assertEquals(actual, expected)
end

function _G.TestInventoryCommon.testIntListToJson()
    local list, expected, actual

    list = {}
    expected = json.encode(list)
    actual = ic.intListToJson(list)
    lu.assertEquals(actual, expected)

    list = {
        [1] = 1
    }
    expected = json.encode(list)
    actual = ic.intListToJson(list)
    lu.assertEquals(actual, expected)

    list = {
        [1] = 1,
        [2] = 2
    }
    local time1, time2, time3
    expected = json.encode(list)
    actual = ic.intListToJson(list)
    lu.assertEquals(actual, expected)
end

function _G.TestInventoryCommon.testRemoveContainerFromDb()
    local databankMock = mockDatabankUnit:new(nil, 1)
    local databank = databankMock:mockGetClosure()

    local resources = {"pure aluminium", "pure carbon", "pure iron", "pure silicon"}
    local resourceKeys = {}
    for i, resource in pairs(resources) do
        resourceKeys[i] = resource .. ic.constants.CONTAINER_SUFFIX
    end

    local function setValue(resourceId, containerString)
        local key = resources[resourceId] .. ic.constants.CONTAINER_SUFFIX
    end

    local containerId, expected, actual

    -- key not found, no-op
    containerId = 2
    databankMock.data = {
        [resourceKeys[1]] = nil,
        [resourceKeys[2]] = "[3]",
        [resourceKeys[3]] = "[4,5]",
        [resourceKeys[4]] = "[]"
    }
    expected = {
        [resourceKeys[1]] = nil,
        [resourceKeys[2]] = "[3]",
        [resourceKeys[3]] = "[4,5]",
        [resourceKeys[4]] = "[]"
    }
    ic.removeContainerFromDb(databank, containerId)
    lu.assertEquals(databankMock.data, expected)

    -- key found alone
    containerId = 2
    databankMock.data = {
        [resourceKeys[1]] = "[2]"
    }
    expected = {
        [resourceKeys[1]] = "[]"
    }
    ic.removeContainerFromDb(databank, containerId)
    lu.assertEquals(databankMock.data, expected)

    -- key found with other combinations
    containerId = 2
    databankMock.data = {
        [resourceKeys[1]] = "[2,3]",
        [resourceKeys[2]] = "[4,2,5]",
        [resourceKeys[3]] = "[6,2]"
    }
    expected = {
        [resourceKeys[1]] = "[3]",
        [resourceKeys[2]] = "[4,5]",
        [resourceKeys[3]] = "[6]"
    }
    ic.removeContainerFromDb(databank, containerId)
    lu.assertEquals(databankMock.data, expected)

    -- key is substring of other container
    containerId = 2
    databankMock.data = {
        [resourceKeys[1]] = "[2]",
        [resourceKeys[2]] = "[22]",
        [resourceKeys[3]] = "[2,22]",
        [resourceKeys[4]] = "[22,2]"
    }
    expected = {
        [resourceKeys[1]] = "[]",
        [resourceKeys[2]] = "[22]",
        [resourceKeys[3]] = "[22]",
        [resourceKeys[4]] = "[22]"
    }
    ic.removeContainerFromDb(databank, containerId)
    lu.assertEquals(databankMock.data, expected)
end

os.exit(lu.LuaUnit.run())