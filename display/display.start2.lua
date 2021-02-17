-- exported variables
local elementsReadPerUpdate = 100 --export: The number of elements to process for data collection before the coroutine sleeps.
local maxMassError = 0.001 -- max error allowed for container lookups

-- localize global lookups
local slots = _G.slots
local Utilities = _G.Utilities
local InventoryCommon = _G.InventoryCommon
local json = _G.json
local math = _G.math

-- validate inputs
local screenIndex = 1
for slot, _ in pairs(slots.displays) do
    assert(slot.getElementClass() == "ScreenUnit",
        string.format("Display slot %d is invalid type: %s", screenIndex, slot.getElementClass()))
    slot.activate()
    screenIndex = screenIndex + 1
end

-----------------------
-- End Configuration --
-----------------------

-- link missing slot inputs / validate provided slots
local module = "inventory-report"
slots.core = Utilities.loadSlot(slots.core, {"CoreUnitDynamic", "CoreUnitStatic", "CoreUnitSpace"}, nil, module,
                    "core", true, "No core link found, will default to emitter for data population.")
slots.databank = Utilities.loadSlot(slots.databank, "DataBankUnit", nil, module, "databank", slots.core,
                        "Databank link not found, required for reading data from core.")
slots.receiver = Utilities.loadSlot(slots.receiver, "ReceiverUnit", nil, module, "receiver", slots.core)

-- hide widget
unit.hide()

-- define display constants and functions
local STYLE_TEMPLATE = [[
<style>
text {
    font-size: %fpx;
    font-family: Arial;
    text-transform: none;
}
text.blockTitle {
    font-size: %fpx;
    fill: green;
    text-anchor: middle;
}
.empty .label {
    fill: #777;
}
.full text {
    fill: black;
}
.full .label {
    fill: #333;
}
.fillHigh {
    fill: green;
}
.fillMed {
    fill: yellow;
}
.fillLow {
    fill: red;
}
</style>
]]
local function generateStyle(screenConfig)
    return string.format(STYLE_TEMPLATE, screenConfig.fontSize, screenConfig.titleFontSize)
end

local ROW_TEMPLATE = [[
<g transform="translate(%.1f,%.1f)">
    <defs>
        <clipPath id="percentClip%d">
            <rect x="%.1f" y="0" width="1920" height="1920" />
        </clipPath>
    </defs>
    <g class="empty %s">
        <text x="$leftText" y="$textHeight">%s</text>
        <text x="$countOffset" y="$textHeight" text-anchor="end">%s</text>
        <text x="$countOffset" y="$textHeight" class="label">%s</text>
        <text x="$rightText" y="$textHeight" text-anchor="end">%.0f<tspan class="label">%%</tspan></text>
    </g>
    <g class="full" clip-path="url(#percentClip%d)">
        <rect x="0" y="0" width="%.1f" height="64" class="%s"/>
        <text x="$leftText" y="$textHeight">%s</text>
        <text x="$countOffset" y="$textHeight" text-anchor="end">%s</text>
        <text x="$countOffset" y="$textHeight" class="label">%s</text>
        <text x="$rightText" y="$textHeight" text-anchor="end">%.0f<tspan class="label">%%</tspan></text>
    </g>
</g>
]]
local rowClassIndex = 0
local function generateRowCell(item, itemData, xStart, yStart, width, height, reverse)
    rowClassIndex = rowClassIndex + 1

    local itemName, itemLabel
    if type(item) == "table" then
        itemName = string.lower(item.name)
        itemLabel = item.label or itemName
    else
        itemName = string.lower(item)
        itemLabel = item
    end

    local itemResults = itemData[itemName] or {}
    local units = ""
    local count = 0
    local maxCount = 1
    local countError = false

    local useContainer = itemResults.containerData
    if useContainer then
        units = itemResults.units
        count = itemResults.containerItems
        maxCount = itemResults.containerMaxItems
        countError = itemResults.containerError
    end

    local percent = count / maxCount

    local barColor
    if reverse then
        if percent > 0.9 then
            barColor = "fillLow"
        elseif percent > 0.5 then
            barColor = "fillMed"
        else
            barColor = "fillHigh"
        end
    else
        if percent > 0.5 then
            barColor = "fillHigh"
        elseif percent > 0.1 then
            barColor = "fillMed"
        else
            barColor = "fillLow"
        end
    end

    local printableCount, countUnits = Utilities.printableNumber(count, units)
    local printablePercent = math.floor(percent * 100 + 0.5)

    -- TODO show/test error

    local rowSvg = string.format(ROW_TEMPLATE, xStart, yStart,
               rowClassIndex, (1 - percent) * width, barColor, itemLabel, printableCount, countUnits,
               printablePercent, rowClassIndex, width, barColor, itemLabel, printableCount, countUnits, printablePercent)

    rowSvg = string.gsub(rowSvg, "$textHeight", height * 3 / 4)
    rowSvg = string.gsub(rowSvg, "$leftText", 5)
    rowSvg = string.gsub(rowSvg, "$countOffset", width - 200)
    rowSvg = string.gsub(rowSvg, "$rightText", width - 5)

    return rowSvg
end

local function generateTable(table, screenConfig, xOffset, yOffset, width, itemData)
    local title = table.title

    local document = ""
    if title then
        document = string.format([[<text class="blockTitle" x="%f" y="%f">%s</text>]], xOffset + width / 2, yOffset + screenConfig.titleHeight * 3 / 4, title)
        yOffset = yOffset + screenConfig.titleHeight
    end

    local columns = table.columns or 1
    local columnXPadding = table.xPadding or screenConfig.tableXPadding or screenConfig.xPadding or 0

    local columnWidth = (width - (columns - 1) * columnXPadding) / columns
    local rowHeight = table.rowHeight or screenConfig.rowHeight
    local rowPadding = table.rowPadding or screenConfig.rowPadding

    local tableReverse = table.reverse

    for _, row in pairs(table.rows) do
        local rowReverse = row.reverse
        if rowReverse == nil then
            rowReverse = tableReverse
        end

        local column = 0
        for _, item in pairs(row) do
            local itemReverse
            if type(item) == "table" and item.reverse ~= nil then
                itemReverse = item.reverse
            else
                itemReverse = rowReverse
            end

            local rowX = xOffset + column * (columnWidth + columnXPadding)
            document = document .. generateRowCell(item, itemData, rowX, yOffset, columnWidth, rowHeight, itemReverse)

            column = column + 1
        end

        yOffset = yOffset + rowHeight + rowPadding
    end

    return document, yOffset
end

local function populateScreen(screen, screenConfig, itemData)
    local document = [[<svg viewbox="0 0 1920 1145" style="width:100%;height:100%;" class="bootstrap" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" preserveAspectRatio="none">]]

    document = document .. generateStyle(screenConfig)

    local height, width, rotateString
    if screenConfig.vertical then
        height = 1920
        width = 1145
        document = document .. [[<g transform="translate(0,1145) rotate(-90)">]]
    else
        height = 1145
        width = 1920
    end

    local xOffset, yOffset = 0, 0
    local maxYOffset = 0

    for _, table in pairs(screenConfig.tables) do
        -- xOffset = xOffset + screenConfig.xPadding
        local tableWidth = width - screenConfig.xPadding * 2

        local tableElement, tableYEnd = generateTable(table, screenConfig, xOffset, yOffset, width, itemData)
        document = document .. tableElement
        maxYOffset = math.max(maxYOffset, tableYEnd)

        yOffset = maxYOffset
        maxYOffset = 0
    end

    if screenConfig.vertical then
        document = document .. [[</g>]]
    end
    document = document .. "</svg>"
    screen.setHTML(document)
end

-- define data gathering functions

--- Initialize metadata: complete autodetected config fields, prepare for reading/receiving data.
local function initializeMetadata(firstRun)
    for screen, config in pairs(slots.displays) do
        if firstRun then
            if not config.source then
                if slots.core then
                    config.source = InventoryCommon.constants.CORE
                elseif slots.receiver then
                    config.source = InventoryCommon.constants.RECEIVER
                end
            end

        -- TODO add loading overlay svg screen
        end

        -- clear/prep for data
        config.data = nil
        config.complete = false
    end
end
initializeMetadata(true)

-- define class for managing item data
local ItemReport = {}
function ItemReport:new(o)
    if not o or type(o) ~= "table" then
        o = {}
    end
    setmetatable(o, self)
    self.__index = self

    o.units = ""

    o.containerData = false
    o.containerItems = 0
    o.containerMaxItems = 0
    o.containerError = false

    return o
end
local gatheredItems = {}

--- Checks all screens to see if they have finished updating.
local function checkFinished()
    local finished = true
    for screen, config in pairs(slots.displays) do
        if not config.complete then
            finished = false
            break
        end
    end
    return finished
end

local resumeOnUpdate = true
local function updateData()

    -- determine necessary data
    for slot, config in pairs(slots.displays) do
        -- skip if not local
        if config.source ~= InventoryCommon.constants.CORE then
            goto continue
        end

        for _, table in pairs(config.tables) do
            for _, row in pairs(table.rows) do
                for _, item in pairs(row) do
                    if type(item) == "table" then
                        gatheredItems[string.lower(item.name)] = ItemReport:new(item)
                    elseif type(item) == "string" then
                        gatheredItems[string.lower(item)] = ItemReport:new()
                    else
                        assert(false, "Unexpected item type: " .. tostring(item) .. " (" .. type(item) .. ")")
                    end
                end
            end
        end

        coroutine.yield()
        ::continue::
    end

    while not checkFinished() do

        -- gather data by databank lookup (containers)
        local elementsRead = 0
        for name, data in pairs(gatheredItems) do
            if not slots.databank then
                break
            end


            -- read container data using databank values
            local containerIdListKey = name .. InventoryCommon.constants.CONTAINER_SUFFIX
            if not (slots.databank.hasKey(name) == 1 and slots.databank.hasKey(containerIdListKey) == 1) then
                goto continueContainers
            end

            -- itemName -> unitMass, unitVolume, isMaterial
            -- itemName.CONTAINER_SUFFIX -> [id, id, id, ...]
            -- CONTAINER_PREFIX.containerId -> selfMass, maxVolume, optimization

            local itemDetails = json.decode(slots.databank.getStringValue(name))

            local containerIdList = InventoryCommon.jsonToIntList(slots.databank.getStringValue(containerIdListKey))

            -- TODO remove container ids that aren't in core.getElementIdList

            for _, containerId in pairs(containerIdList) do
                local containerDetails = json.decode(slots.databank.getStringValue(InventoryCommon.constants.CONTAINER_PREFIX .. containerId))

                local itemMass = (slots.core.getElementMassById(containerId) - containerDetails.selfMass) / containerDetails.optimization
                local itemCount = itemMass / itemDetails.unitMass
                local itemUnits
                local maxItems
                if itemDetails.isMaterial then
                    itemUnits = "L"
                    maxItems = containerDetails.maxVolume
                else
                    itemUnits = ""
                    maxItems = math.floor(itemDetails.unitVolume / containerDetails.maxVolume)
                end

                data.units = itemUnits
                data.containerData = true
                data.containerItems = data.containerItems + itemCount
                data.containerMaxItems = data.containerMaxItems + maxItems
                data.containerError = data.containerError or math.abs(itemCount - math.floor(itemCount)) > maxMassError

                elementsRead = elementsRead + 1
                if elementsRead % elementsReadPerUpdate == 0 then
                    coroutine.yield()
                end
            end

            ::continueContainers::
        end

        -- gather data by industry scanning
        if slots.core then
            for _, id in pairs(slots.core.getElementIdList()) do
                -- system.print(id .. ": " .. slots.core.getElementNameById(id) .. ": " .. slots.core.getElementTypeById(id))

                elementsRead = elementsRead + 1
                if elementsRead % elementsReadPerUpdate == 0 then
                    coroutine.yield()
                end
            end
        end

        -- update screens
        for slot, config in pairs(slots.displays) do
            -- skip if already done
            if config.finished then
                goto continue
            end

            populateScreen(slot, config, gatheredItems)
            config.complete = true

            coroutine.yield()
            ::continue::
        end
    end

    unit.exit()
end

local updateCoroutine = coroutine.create(updateData)
function _G.resumeWork()
    -- don't hit coroutine every tick when it's waiting for more data
    if not resumeOnUpdate then
        return
    end

    local ok, message = coroutine.resume(updateCoroutine)
    if not ok then
        error(string.format("Resuming coroutine failed: %s", message))
    end
end

function _G.handleMessage(msg)
    -- TODO store data as appropriate

    resumeOnUpdate = true
end