-- Константы экрана и области текста
local SCR_W, SCR_H = 410, 502
local LIST_X, LIST_Y = 5, 65
local LIST_W, LIST_H = 400, 375

-- Настройки читалки
local PAGE_H = LIST_H        -- Высота одной страницы
local TOTAL_V_H = PAGE_H * 3 -- Общая высота области скролла (1125 px)
local CENTER_Y = PAGE_H      -- Точка "покоя" (начало второй страницы)

-- Состояние
local scrollY = CENTER_Y     -- Текущее положение скролла
local currentFile = ""
local fileLines = {}
local topVisibleLine = 1     -- Индекс первой строки на текущей странице
local mode = "browser"       -- "browser" или "reader"
local storage = "sd"         -- "sd" или "fs"

-- Загрузка файла
function loadFile(path, source)
    local content = ""
    if source == "sd" then
        content = sd.readBytes(path)
    else
        content = fs.readBytes(path)
    end
    
    if content then
        fileLines = {}
        for line in content:gmatch("([^\n]*)\n?") do
            table.insert(fileLines, line)
        end
        currentFile = path
        topVisibleLine = 1
        scrollY = CENTER_Y
        mode = "reader"
    end
end

-- Отрисовка одной страницы текста
function drawPage(startY, startLine)
    local y = startY
    local lineIdx = startLine
    while y < startY + PAGE_H and lineIdx <= #fileLines do
        ui.text(10, y, fileLines[lineIdx], 2, 0xFFFF)
        y = y + 25 -- Высота строки
        lineIdx = lineIdx + 1
    end
    return lineIdx -- Возвращаем индекс, на котором остановились
end

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000) -- Очистка

    if mode == "browser" then
        ui.text(10, 20, "File Browser (" .. storage .. ")", 2, 0x07E0)
        
        if ui.button(300, 15, 100, 35, storage == "sd" and "to FLASH" or "to SD", 0x4444) then
            storage = (storage == "sd") and "fs" or "sd"
        end

        local files = (storage == "sd") and sd.list("/") or fs.list("/")
        local listSY = 0
        listSY = ui.beginList(LIST_X, LIST_Y, LIST_W, LIST_H, listSY, #files * 50)
        for i, f in ipairs(files) do
            if ui.button(0, (i-1)*50, 380, 45, f, 0x2104) then
                loadFile("/" .. f, storage)
            end
        end
        ui.endList()

    elseif mode == "reader" then
        ui.text(10, 20, "Reading: " .. currentFile, 1, 0x07E0)
        if ui.button(330, 15, 70, 35, "Back", 0x8000) then mode = "browser" end

        -- Включаем инерцию для плавности, но будем делать доводку
        ui.setListInertia(true)
        
        -- Главный механизм бесконечного списка
        -- Передаем TOTAL_V_H (3 страницы)
        local newY = ui.beginList(LIST_X, LIST_Y, LIST_W, LIST_H, scrollY, TOTAL_V_H)
        
        -- Отрисовка трех сегментов: "прошлое", "настоящее", "будущее"
        -- 1. Предыдущая страница (если есть)
        local prevStart = math.max(1, topVisibleLine - 15) -- примерно 15 строк на экран
        drawPage(0, prevStart)
        
        -- 2. Текущая страница (центр)
        local nextStart = drawPage(PAGE_H, topVisibleLine)
        
        -- 3. Следующая страница
        drawPage(PAGE_H * 2, nextStart)
        
        ui.endList()

        -- ЛОГИКА ПЕРЕКЛЮЧЕНИЯ СТРАНИЦ
        local diff = newY - CENTER_Y
        local touch = ui.getTouch()

        if not touch.touching then
            -- Если пользователь отпустил экран, делаем доводку
            if diff > PAGE_H / 3 then
                -- Листаем вперед
                topVisibleLine = nextStart
                scrollY = CENTER_Y -- Сбрасываем скролл в центр
            elseif diff < -PAGE_H / 3 then
                -- Листаем назад
                topVisibleLine = prevStart
                scrollY = CENTER_Y -- Сбрасываем скролл в центр
            else
                -- Возвращаем на текущую (доводка)
                scrollY = newY + (CENTER_Y - newY) * 0.2
            end
        else
            scrollY = newY
        end
    end
    
    ui.flush()
end
