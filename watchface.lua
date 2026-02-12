-- Константы
local W, H = 410, 502
local HEADER_H = 50
local MARGIN_X = 15
local LINE_HEIGHT = 32
local TEXT_SIZE = 2
local CHARS_LIMIT = 20 -- Символов в строке (не байт!)

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

-- Дополнительные переменные для анимации
local animationVelocity = 0
local animationActive = false
local animationTarget = pageH
local ANIMATION_DAMPING = 0.15 -- Скорость анимации (0.1-0.2 оптимально)
local SWIPE_THRESHOLD = pageH * 0.30 -- 30% экрана

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
    animationActive = false
    animationVelocity = 0
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
    -- Проверка границ массива
    if pIdx < 0 or pIdx >= totalPages then
        -- Рисуем плейсхолдеры только если страница в пределах видимой области
        if baseY >= -50 and baseY < H then
            local msg = pIdx < 0 and "--- НАЧАЛО ---" or "--- КОНЕЦ ---"
            ui.text(W/2 - 80, baseY + visibleH/2, msg, 2, 0x8410)
        end
        return
    end

    local start = pIdx * linesPerPage + 1
    local stop = math.min(start + linesPerPage - 1, #lines)
    
    for i = start, stop do
        local y = baseY + 10 + (i - start) * LINE_HEIGHT
        -- Проверяем, что строка видна на экране (оптимизация)
        if y + 20 > HEADER_H and y < H then
            ui.text(MARGIN_X, y, lines[i], TEXT_SIZE, 0xFFFF)
        end
    end
end

local function drawReader()
    ui.rect(0, 0, W, H, 0)
    
    -- Шапка
    ui.fillRoundRect(0, 0, W, HEADER_H - 5, 0, 0x10A2)
    ui.text(10, 10, (currentPage + 1) .. " / " .. totalPages, 2, 0xFFFF)
    if ui.button(W - 80, 5, 70, 35, "EXIT", 0xF800) then 
        mode = "browser"
        animationActive = false
    end

    -- Важно: Отключаем инерцию списка, мы будем делать её сами
    ui.setListInertia(false)

    -- Получаем состояние касания
    local touch = ui.getTouch()
    
    -- Обработка касания и обновление scrollY
    if touch.touching then
        -- Если палец на экране, список следует за ним
        local updatedScroll = ui.beginList(0, HEADER_H, W, visibleH, scrollY, contentH)
        
        -- Рендерим три страницы
        renderPage(currentPage - 1, 0)
        renderPage(currentPage, pageH)
        renderPage(currentPage + 1, pageH * 2)
        
        ui.endList()
        
        -- Сохраняем новую позицию
        scrollY = updatedScroll
        animationActive = false -- Отменяем анимацию при касании
        animationVelocity = 0
        
    else
        -- Палец отпущен
        if animationActive then
            -- Продолжаем анимацию возврата
            scrollY = ui.beginList(0, HEADER_H, W, visibleH, scrollY, contentH)
            
            renderPage(currentPage - 1, 0)
            renderPage(currentPage, pageH)
            renderPage(currentPage + 1, pageH * 2)
            
            ui.endList()
            
            -- Плавное движение к цели
            local diff = scrollY - animationTarget
            if math.abs(diff) > 0.5 then
                -- Применяем демпфирование
                scrollY = scrollY - diff * ANIMATION_DAMPING
            else
                -- Достигли цели
                scrollY = animationTarget
                animationActive = false
            end
        else
            -- Начало анимации - анализируем свайп
            local diff = scrollY - pageH
            
            -- Проверяем порог свайпа
            if math.abs(diff) > SWIPE_THRESHOLD then
                -- Достаточный свайп - перелистываем
                if diff > 0 and currentPage < totalPages - 1 then
                    currentPage = currentPage + 1
                    scrollY = pageH
                elseif diff < 0 and currentPage > 0 then
                    currentPage = currentPage - 1
                    scrollY = pageH
                else
                    -- Край файла - просто возвращаемся
                    animationActive = true
                    animationTarget = pageH
                    -- Принудительно обновляем список, чтобы анимация началась
                    scrollY = ui.beginList(0, HEADER_H, W, visibleH, scrollY, contentH)
                    renderPage(currentPage - 1, 0)
                    renderPage(currentPage, pageH)
                    renderPage(currentPage + 1, pageH * 2)
                    ui.endList()
                end
            else
                -- Недостаточный свайп - запускаем анимацию возврата
                animationActive = true
                animationTarget = pageH
                -- Обновляем список для первого кадра анимации
                scrollY = ui.beginList(0, HEADER_H, W, visibleH, scrollY, contentH)
                renderPage(currentPage - 1, 0)
                renderPage(currentPage, pageH)
                renderPage(currentPage + 1, pageH * 2)
                ui.endList()
            end
        end
        
        -- Защита от выхода за границы
        if scrollY < 0 then
            scrollY = 0
            animationActive = false
        elseif scrollY > contentH - visibleH then
            scrollY = contentH - visibleH
            animationActive = false
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
    if mode == "browser" then 
        drawBrowser() 
    else 
        drawReader() 
    end
    ui.flush()
end

-- Старт
refreshFiles()
