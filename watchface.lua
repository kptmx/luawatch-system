local SCR_W, SCR_H = 410, 502
local LINE_HEIGHT = 28
local LINES_PER_PAGE = math.floor(SCR_H / LINE_HEIGHT)
local CHARS_PER_LINE = 30 

local appMode = "MENU"
local fileList = {}
local lines = {}
local currentPage = 1
local totalPages = 1
local scrollY = SCR_H 

-- Функция сканирования
local function scanFiles()
    fileList = {}
    local all = sd.list("/")
    if all then
        for _, v in ipairs(all) do
            if string.find(v:lower(), ".txt") then
                table.insert(fileList, "/sdcard/" .. v)
            end
        end
    end
    -- Если SD пустая, добавим хотя бы системный лог для проверки
    if #fileList == 0 then table.insert(fileList, "/main.lua") end
end

-- Загрузка книги
local function loadBook(path)
    print("Trying to load: " .. path) -- Отладка в консоль Serial
    local data = sd.readBytes(path)
    if not data then data = fs.load(path) end
    
    if data and #data > 0 then
        lines = {}
        -- Безопасный парсинг строк
        for line in string.gmatch(data, "([^\r\n]+)") do
            local str = line
            while #str > CHARS_PER_LINE do
                table.insert(lines, string.sub(str, 1, CHARS_PER_LINE))
                str = string.sub(str, CHARS_PER_LINE + 1)
            end
            table.insert(lines, str)
        end
        
        totalPages = math.ceil(#lines / LINES_PER_PAGE)
        currentPage = 1
        scrollY = SCR_H
        appMode = "READER"
        print("Loaded lines: " .. #lines)
    else
        print("Failed to load or file empty")
    end
end

scanFiles()

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
    
    if appMode == "MENU" then
        ui.text(20, 20, "Select File:", 2, 0x07E0)
        
        for i, path in ipairs(fileList) do
            -- Отрисовка кнопки
            -- ВАЖНО: проверяем нажатие. Если ui.button не срабатывает, 
            -- попробуем через проверку координат тача напрямую
            if ui.button(20, 60 + (i-1)*55, 370, 45, path, 0x2104) then
                loadBook(path)
            end
        end
        
        if ui.button(300, 15, 90, 30, "SCAN", 0x421F) then scanFiles() end

    elseif appMode == "READER" then
        -- Виджет списка (3 экрана высотой)
        scrollY = ui.beginList(0, 0, SCR_W, SCR_H, scrollY, SCR_H * 3)
            
            -- Секция 1: Предидущая
            if currentPage > 1 then
                drawPage(currentPage - 1, 0)
            else
                ui.text(140, 200, "[START]", 2, 0x421F)
            end
            
            -- Секция 2: Текущая
            drawPage(currentPage, SCR_H)
            
            -- Секция 3: Следующая
            if currentPage < totalPages then
                drawPage(currentPage + 1, SCR_H * 2)
            else
                ui.text(140, SCR_H * 2 + 200, "[END]", 2, 0x421F)
            end

        ui.endList()

        -- ЛОГИКА ПЕРЕКЛЮЧЕНИЯ (Твое ТЗ: незаметная подмена)
        local threshold_top = SCR_H * 0.1
        local threshold_bottom = SCR_H * 1.9

        if scrollY < threshold_top and currentPage > 1 then
            currentPage = currentPage - 1
            scrollY = scrollY + SCR_H -- Возвращаем скролл в центр
        elseif scrollY > threshold_bottom and currentPage < totalPages then
            currentPage = currentPage + 1
            scrollY = scrollY - SCR_H -- Возвращаем скролл в центр
        end

        -- Доводка (Snapping)
        local t = ui.getTouch()
        if not t.touching then
            -- Плавное стремление к центральному экрану (SCR_H)
            local speed = 0.2
            scrollY = scrollY + (SCR_H - scrollY) * speed
            
            -- Если почти дошли - фиксируем
            if math.abs(SCR_H - scrollY) < 1 then scrollY = SCR_H end
        end

        -- Кнопка выхода
        if ui.button(5, 5, 40, 40, "<", 0xF800) then appMode = "MENU" end
    end
end

function drawPage(pageNum, offsetY)
    local startIdx = (pageNum - 1) * LINES_PER_PAGE + 1
    local endIdx = math.min(startIdx + LINES_PER_PAGE - 1, #lines)
    
    for i = startIdx, endIdx do
        local yPos = offsetY + (i - startIdx) * LINE_HEIGHT
        -- Рисуем только если строка попадает в видимую область (оптимизация)
        ui.text(15, yPos, lines[i], 2, 0xFFFF)
    end
end
