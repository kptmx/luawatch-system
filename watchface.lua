-- Simple TXT Reader with file browser and Internal/SD switching
-- Place as /main.lua

local W, H = 410, 502
local HEADER_H = 60
local ITEM_H = 55
local LINE_HEIGHT = 32
local TEXT_SIZE = 2
local MARGIN_X = 20
local MARGIN_TOP = HEADER_H + 10

local visibleH = H - HEADER_H
local pageH = visibleH
local contentH_reader = pageH * 3

local mode = "browser"              -- "browser" or "reader"
local currentSource = "internal"    -- "internal" or "sd"
local fileList = {}
local fileName = ""
local errorMsg = nil
local scrollBrowserY = 0
local scrollY = pageH               -- middle of triple buffer

local lines = {}
local linesPerPage = math.floor((visibleH - 20) / LINE_HEIGHT)
local totalPages = 0
local currentPage = 0

local function refreshFileList()
    fileList = {}
    errorMsg = nil

    local res
    if currentSource == "internal" then
        res = fs.list("/")
    else
        if not sd_ok then
            errorMsg = "SD card not mounted"
            return
        end
        res = sd.list("/")
    end

    if type(res) ~= "table" then
        errorMsg = "Failed to list directory"
        return
    end

    for _, f in ipairs(res) do
        if f:lower():match("%.txt$") then
            table.insert(fileList, f)
        end
    end
    table.sort(fileList)
end

local function loadFile(path, isSD)
    local content
    if isSD then
        if not sd_ok then return false, "SD not mounted" end
        content = sd.readBytes(path)
    else
        content = fs.readBytes(path)
    end

    if type(content) ~= "string" then
        return false, "Failed to read file"
    end

    lines = {}
    for line in (content .. "\n"):gmatch("(.-)\r?\n") do
        table.insert(lines, line)
    end
    if #lines > 0 and lines[#lines] == "" then
        table.remove(lines)
    end

    totalPages = math.max(1, math.ceil(#lines / linesPerPage))
    currentPage = 0
    scrollY = pageH
    return true
end

local function drawPage(page, baseY)
    if page < 0 or page >= totalPages then
        local msg = page < 0 and "-- Beginning of file --" or "-- End of file --"
        ui.text(MARGIN_X, baseY + visibleH/2 - 30, msg, 3, 0x8410)
        return
    end

    local startLine = page * linesPerPage + 1
    local endLine = math.min(startLine + linesPerPage - 1, #lines)
    local y = baseY

    for i = startLine, endLine do
        ui.text(MARGIN_X, y, lines[i], TEXT_SIZE, 0xFFFF)
        y = y + LINE_HEIGHT
    end
end

local function drawReader()
    ui.rect(0, 0, W, H, 0)

    -- Header
    ui.text(10, 12, fileName, 2, 0xFFFF)
    ui.text(W - 180, 12, (currentPage + 1) .. "/" .. totalPages, 2, 0xFFFF)
    if ui.button(W - 110, 8, 100, 44, "Back", 0xF800) then
        mode = "browser"
    end

    ui.setListInertia(false)
    local updatedScroll = ui.beginList(0, HEADER_H, W, visibleH, scrollY, contentH_reader)

    drawPage(currentPage - 1, 0)
    drawPage(currentPage, pageH)
    drawPage(currentPage + 1, pageH * 2)

    ui.endList()

    local touch = ui.getTouch()
    if touch.released then
        local delta = updatedScroll - pageH
        local flipped = false

        if delta < -pageH * 0.3 then
            if currentPage > 0 then
                currentPage = currentPage - 1
                flipped = true
            end
        elseif delta > pageH * 0.3 then
            if currentPage < totalPages - 1 then
                currentPage = currentPage + 1
                flipped = true
            end
        end

        scrollY = pageH
    else
        scrollY = updatedScroll
    end
end

local function drawBrowser()
    ui.rect(0, 0, W, H, 0)

    -- Header
    ui.text(10, 12, "TXT Reader - " .. (currentSource == "internal" and "Internal Flash" or "SD Card"), 2, 0xFFFF)

    local switchLabel = currentSource == "internal" 
        and (sd_ok and "Switch to SD Card" or "SD not available")
        or "Switch to Internal Flash"
    local switchColor = (currentSource == "internal" and sd_ok or currentSource == "sd") and 0x07E0 or 0x8410

    if ui.button(10, 65, 380, 50, switchLabel, switchColor) then
        if (currentSource == "internal" and sd_ok) or currentSource == "sd" then
            currentSource = currentSource == "internal" and "sd" or "internal"
            refreshFileList()
            scrollBrowserY = 0
        end
    end

    if errorMsg then
        ui.text(20, 150, errorMsg, 3, 0xF800)
        return
    end

    if #fileList == 0 then
        ui.text(20, 180, "No .txt files found", 3, 0x8410)
        return
    end

    local contentH_browser = #fileList * ITEM_H
    ui.setListInertia(true)
    scrollBrowserY = ui.beginList(0, HEADER_H + 70, W, visibleH - 70, scrollBrowserY, contentH_browser)

    for i, f in ipairs(fileList) do
        local y = (i - 1) * ITEM_H
        if ui.button(10, y, W - 20, ITEM_H - 8, f, 0x0528) then
            local fullPath = "/" .. f
            local ok, err = loadFile(fullPath, currentSource == "sd")
            if ok then
                fileName = f
                mode = "reader"
            else
                errorMsg = err or "Load failed"
            end
        end
    end

    ui.endList()
end

function draw()
    if mode == "browser" then
        drawBrowser()
    else
        drawReader()
    end
    ui.flush()
end

-- Initialization
if sd_ok then
    currentSource = "sd"  -- prefer SD if available
end
refreshFileList()
