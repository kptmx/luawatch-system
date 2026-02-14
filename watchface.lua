-- Константы
local W, H = 410, 502
local HEADER_H = 50
local MARGIN_X = 15
local LINE_HEIGHT = 32
local TEXT_SIZE = 2
local CHARS_LIMIT = 28 -- Символов в строке (не байт!)
-- Расчетные высоты
local visibleH = H - HEADER_H
local pageH = visibleH
local contentH = pageH * 3 -- Три экрана высоты
local linesPerPage = math.floor((visibleH - 20) / LINE_HEIGHT)
-- Переменные
local mode = "browser"
local currentSource = "sd" -- или "internal"
local fileList = {}
local fileName = ""
local lines = {}
local totalPages = 0
local currentPage = 0
local scrollY = pageH -- Начинаем всегда с центра (вторая страница)
local animDir = 0
local animProgress = 0
local targetProgress = 0
local isFlip = false
-- === [ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ] ===
-- Подсчет длины строки UTF-8 (чтобы кириллица считалась за 1 символ)
local function utf8_len(s)
    local _, count = string.gsub(s, "[^\128-\193]", "")
    return count
end
-- Умный перенос слов
local function wrapText(text)
    local res = {}
    -- Разбиваем на параграфы
    for paragraph in (text .. "\n"):gmatch("(.-)\r?\n") do
        if paragraph == "" then
            table.insert(res, "")
        else
            local line = ""
            local lineLen = 0
            -- Разбиваем параграф на слова
            for word in paragraph:gmatch("%S+") do
                local wLen = utf8_len(word)
                -- Влезет ли слово в текущую строку?
                if lineLen + wLen + 1 <= CHARS_LIMIT then
                    line = line .. (line == "" and "" or " ") .. word
                    lineLen = lineLen + wLen + (line == "" and 0 or 1)
                else
                    -- Не влезло, сохраняем строку и начинаем новую
                    table.insert(res, line)
                    line = word
                    lineLen = wLen
                end
            end
            if line ~= "" then table.insert(res, line) end
        end
    end
    return res
end
local function loadFile(path)
    local data = (currentSource == "sd") and sd.readBytes(path) or fs.readBytes(path)
    if not data or #data == 0 then return false end
   
    lines = wrapText(data)
    totalPages = math.ceil(#lines / linesPerPage)
    currentPage = 0
    scrollY = pageH
    mode = "reader"
    return true
end
local function refreshFiles()
    fileList = {}
    local res = (currentSource == "sd") and sd.list("/") or fs.list("/")
    if type(res) == "table" then
        for _, name in ipairs(res) do
            if name:lower():match("%.txt$") then table.insert(fileList, name) end
        end
        table.sort(fileList)
    end
end
-- === [ОТРИСОВКА] ===
-- Рисует одну страницу текста по указанному смещению Y
-- Оптимизированная отрисовка страницы
local function renderPage(pIdx, baseY)
    if pIdx < 0 or pIdx >= totalPages then
        ui.text(W/2 - 50, baseY + visibleH/2, pIdx < 0 and "START" or "END", 2, 0x8410)
        return
    end

    local start = pIdx * linesPerPage + 1
    local stop = math.min(start + linesPerPage - 1, #lines)
    
    -- Оптимизация: не рисуем то, что за пределами физического экрана
    -- baseY — это координата начала страницы относительно 0 экрана
    for i = start, stop do
        local lineY = baseY + 10 + (i - start) * LINE_HEIGHT
        if lineY > -LINE_HEIGHT and lineY < H then -- Clip check
            ui.text(MARGIN_X, lineY, lines[i], TEXT_SIZE, 0xFFFF)
        end
    end
end

local function drawReader()
    ui.rect(0, 0, W, H, 0)
    
    -- Отрисовка интерфейса (статично)
    ui.fillRoundRect(0, 0, W, HEADER_H - 5, 0, 0x10A2)
    ui.text(10, 15, string.format("%d / %d", currentPage + 1, totalPages), 2, 0xFFFF)
    if ui.button(W - 80, 5, 70, 35, "EXIT", 0xF800) then mode = "browser" end

    local touch = ui.getTouch()
    
    -- ЛОГИКА АНИМАЦИИ (упрощенная)
    if touch.touching then
        -- Когда тянем, просто меняем временное смещение
        if not lastTouchY then lastTouchY = touch.y end
        local delta = touch.y - lastTouchY
        scrollY = pageH + delta
        animDir = 0
    else
        lastTouchY = nil
        -- Плавный возврат или перелистывание (Lerp)
        local targetScroll = pageH
        local diff = scrollY - pageH
        
        if math.abs(diff) > pageH * 0.25 then
            if diff < 0 and currentPage < totalPages - 1 then 
                targetScroll = 0 -- Листаем вперед
            elseif diff > 0 and currentPage > 0 then 
                targetScroll = pageH * 2 -- Листаем назад
            end
        end
        
        -- Плавное приближение к цели (простой Lerp эффективнее сложной анимации)
        if math.abs(scrollY - targetScroll) > 1 then
            scrollY = scrollY + (targetScroll - scrollY) * 0.3
        else
            -- Завершение анимации
            if targetScroll == 0 then currentPage = currentPage + 1 end
            if targetScroll == pageH * 2 then currentPage = currentPage - 1 end
            scrollY = pageH
        end
    end

    -- Рендерим только нужные страницы напрямую без beginList
    -- Это сэкономит кучу ресурсов на обработке внутренних контейнеров списка
    local drawY = scrollY - pageH
    
    -- Используем экранные координаты напрямую
    renderPage(currentPage - 1, HEADER_H + drawY - pageH)
    renderPage(currentPage,     HEADER_H + drawY)
    renderPage(currentPage + 1, HEADER_H + drawY + pageH)
end
local function drawBrowser()
    ui.rect(0, 0, W, H, 0)
    ui.text(20, 15, "FILES (" .. currentSource .. ")", 2, 0xFFFF)
   
    if ui.button(W - 100, 10, 90, 35, "SOURCE", 0x421F) then
        currentSource = (currentSource == "sd") and "internal" or "sd"
        refreshFiles()
    end
    local bScroll = 0
    bScroll = ui.beginList(0, 60, W, H - 60, bScroll, #fileList * 55)
    for i, f in ipairs(fileList) do
        if ui.button(10, (i-1)*55, W-20, 45, f, 0x2104) then
            fileName = f
            loadFile("/" .. f)
        end
    end
    ui.endList()
end
function draw()
    if mode == "browser" then drawBrowser() else drawReader() end
    ui.flush()
end
-- Старт
refreshFiles()
