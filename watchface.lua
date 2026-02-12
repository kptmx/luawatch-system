-- Константы
local W, H = 410, 502
local HEADER_H = 50
local MARGIN_X = 15
local LINE_HEIGHT = 32
local TEXT_SIZE = 2
local CHARS_LIMIT = 24 -- Символов в строке (не байт!)

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
local function renderPage(pIdx, baseY)
    -- Плейсхолдеры для начала и конца файла
    if pIdx < 0 then
        ui.text(W/2 - 80, baseY + visibleH/2, "--- НАЧАЛО ---", 2, 0x8410)
        return
    elseif pIdx >= totalPages then
        ui.text(W/2 - 80, baseY + visibleH/2, "--- КОНЕЦ ---", 2, 0x8410)
        return
    end

    local start = pIdx * linesPerPage + 1
    local stop = math.min(start + linesPerPage - 1, #lines)
    
    for i = start, stop do
        local y = baseY + 10 + (i - start) * LINE_HEIGHT
        ui.text(MARGIN_X, y, lines[i], TEXT_SIZE, 0xFFFF)
    end
end

local function drawReader()
    ui.rect(0, 0, W, H, 0)
    
    -- Шапка
    ui.fillRoundRect(0, 0, W, HEADER_H - 5, 0, 0x10A2)
    ui.text(10, 10, (currentPage + 1) .. " / " .. totalPages, 2, 0xFFFF)
    if ui.button(W - 80, 5, 70, 35, "EXIT", 0xF800) then mode = "browser" end

    -- Важно: Отключаем инерцию списка, мы будем делать её сами математикой
    ui.setListInertia(false)

    -- Рисуем список. updatedScroll - это то, где список находится СЕЙЧАС (физически)
    local updatedScroll = ui.beginList(0, HEADER_H, W, visibleH, scrollY, contentH)
        
        -- Секция 1 (предыдущая) - от 0 до pageH
        renderPage(currentPage - 1, 0)
        
        -- Секция 2 (текущая) - от pageH до pageH*2
        renderPage(currentPage, pageH)
        
        -- Секция 3 (следующая) - от pageH*2 до pageH*3
        renderPage(currentPage + 1, pageH * 2)

    ui.endList()

    local touch = ui.getTouch()

    if touch.touching then
        -- 1. Если палец на экране, список просто следует за ним
        scrollY = updatedScroll
    else
        -- 2. Палец отпущен. Анализируем смещение от ЦЕНТРА (pageH)
        local diff = updatedScroll - pageH
        local threshold = pageH * 0.30 -- 30% экрана нужно протащить для перелистывания

        -- СЦЕНАРИЙ А: Перелистывание ВПЕРЕД (свайп вверх)
        if diff > threshold and currentPage < totalPages - 1 then
            currentPage = currentPage + 1
            scrollY = pageH -- Мгновенный сброс в центр (бесшовная подмена)
            
        -- СЦЕНАРИЙ Б: Перелистывание НАЗАД (свайп вниз)
        elseif diff < -threshold and currentPage > 0 then
            currentPage = currentPage - 1
            scrollY = pageH -- Мгновенный сброс в центр (бесшовная подмена)
            
        -- СЦЕНАРИЙ В: Не дотянули до 30% или край файла -> АНИМАЦИЯ ВОЗВРАТА
        else
            -- Нам нужно плавно изменить scrollY от текущего (updatedScroll) к целевому (pageH)
            -- math.abs(diff) > 1 нужно чтобы остановить бесконечные микродвижения
            if math.abs(diff) > 1 then
                -- Формула плавности: (Цель - Текущее) * Скорость
                -- 0.2 - это скорость анимации (чем меньше число, тем плавнее)
                scrollY = updatedScroll - (diff * 0.2)
            else
                scrollY = pageH -- Доводка завершена
            end
        end
    end
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
