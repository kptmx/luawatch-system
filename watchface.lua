-- Читалка текстовых файлов с бесконечной прокруткой
-- Инициализация переменных
local currentFile = ""
local currentSource = "fs" -- "fs" для встроенной памяти, "sd" для SD-карты
local fileContent = ""
local totalPages = 0
local currentPage = 1
local listScroll = 125 -- Начальная позиция скролла (средняя треть)
local maxScroll = 375
local linesPerPage = 25
local totalLines = 0
local allLines = {}
local isLoading = false
local lastDirection = 0 -- -1 для вверх, 1 для вниз, 0 для бездействия

-- Функция для загрузки файла
function loadFile(path, source)
    if not path or path == "" then return false end
    
    -- Очистка предыдущего содержимого
    allLines = {}
    totalLines = 0
    totalPages = 0
    currentPage = 1
    listScroll = 125
    isLoading = true
    
    -- Определение источника и чтение файла
    local result
    if source == "sd" then
        result = sd.readBytes(path)
    else
        result = fs.readBytes(path)
    end
    
    if result and result.ok then
        -- Разделение текста на строки
        for line in result.body:gmatch("[^\r\n]+") do
            table.insert(allLines, line)
        end
        totalLines = #allLines
        totalPages = math.ceil(totalLines / linesPerPage)
        currentFile = path
        currentSource = source
        
        -- Установка скролла на середину (вторая треть)
        listScroll = 125
        return true
    else
        return false
    end
end

-- Функция для получения строк для текущей страницы
function getCurrentPageLines()
    local startIdx = (currentPage - 1) * linesPerPage + 1
    local endIdx = math.min(startIdx + linesPerPage - 1, totalLines)
    local pageLines = {}
    
    for i = startIdx, endIdx do
        table.insert(pageLines, allLines[i])
    end
    
    return pageLines
end

-- Функция для обновления списка при прокрутке
function updateListOnScroll()
    -- Определение направления скролла
    if listScroll < 50 then
        -- Прокрутка вверх
        if currentPage > 1 and lastDirection ~= -1 then
            currentPage = currentPage - 1
            lastDirection = -1
            -- Сброс скролла на середину
            listScroll = 125
        end
    elseif listScroll > 200 then
        -- Прокрутка вниз
        if currentPage < totalPages and lastDirection ~= 1 then
            currentPage = currentPage + 1
            lastDirection = 1
            -- Сброс скролла на середину
            listScroll = 125
        end
    else
        -- В средней зоне, сбрасываем направление
        lastDirection = 0
    end
end

-- Основная функция отрисовки
function draw()
    -- Фон
    ui.rect(0, 0, 410, 502, 0)
    
    -- Заголовок
    ui.text(10, 10, "Text Reader", 2, 0xFFFF)
    
    -- Информация о файле и текущей странице
    if currentFile ~= "" then
        local fileName = currentFile:match("([^/]+)$") or currentFile
        ui.text(10, 35, fileName .. " [" .. currentPage .. "/" .. totalPages .. "]", 1, 0xC618)
    end
    
    -- Кнопка выбора файла
    if ui.button(300, 5, 100, 30, "Select File", 0x4208) then
        showFileSelector = not showFileSelector
    end
    
    -- Область текста
    ui.rect(5, 65, 400, 375, 0x2104)
    
    -- Список с текстом
    listScroll = ui.beginList(5, 65, 400, 375, listScroll, 1125) -- 375 * 3 = 1125
    
    -- Обновление списка при прокрутке
    updateListOnScroll()
    
    -- Отображение текущей страницы
    local lines = getCurrentPageLines()
    for i, line in ipairs(lines) do
        ui.text(10, 70 + (i-1) * 15, line, 1, 0xFFFF)
    end
    
    ui.endList()
    
    -- Навигационные кнопки
    if ui.button(5, 450, 100, 40, "Prev", 0x4208) and currentPage > 1 then
        currentPage = currentPage - 1
        listScroll = 125
    end
    
    if ui.button(155, 450, 100, 40, "Menu", 0x8410) then
        showFileSelector = not showFileSelector
    end
    
    if ui.button(305, 450, 100, 40, "Next", 0x4208) and currentPage < totalPages then
        currentPage = currentPage + 1
        listScroll = 125
    end
    
    -- Селектор файлов (показывается при необходимости)
    if showFileSelector then
        drawFileSelector()
    end
end

-- Функция отрисовки селектора файлов
function drawFileSelector()
    -- Полупрозрачный фон
    ui.rect(0, 0, 410, 502, 0x8000)
    
    -- Окно селектора
    ui.fillRoundRect(30, 50, 350, 400, 10, 0x0000)
    ui.roundRect(30, 50, 350, 400, 10, 0xFFFF)
    
    ui.text(150, 70, "Select File", 2, 0xFFFF)
    
    -- Кнопки выбора источника
    local fsColor = currentSource == "fs" and 0xF800 or 0x4208
    local sdColor = currentSource == "sd" and 0xF800 or 0x4208
    
    if ui.button(50, 100, 140, 30, "Internal", fsColor) then
        currentSource = "fs"
        fileList = getFileList(currentSource)
    end
    
    if ui.button(220, 100, 140, 30, "SD Card", sdColor) then
        currentSource = "sd"
        fileList = getFileList(currentSource)
    end
    
    -- Список файлов
    fileScroll = ui.beginList(50, 140, 310, 250, fileScroll or 0, #fileList * 25)
    
    for i, file in ipairs(fileList) do
        if ui.button(50, 140 + (i-1) * 25, 310, 25, file, 0x2104) then
            if loadFile(file, currentSource) then
                showFileSelector = false
            end
        end
    end
    
    ui.endList()
    
    -- Кнопка закрытия
    if ui.button(160, 400, 90, 30, "Close", 0x8410) then
        showFileSelector = false
    end
end

-- Функция для получения списка файлов
function getFileList(source)
    local files = {}
    
    if source == "sd" and sd_ok then
        local result = sd.list("/")
        if result and result.ok then
            for i, file in ipairs(result) do
                if file:match("%.txt$") or file:match("%.lua$") or file:match("%.md$") then
                    table.insert(files, file)
                end
            end
        end
    else
        local result = fs.list("/")
        if result and result.ok then
            for i, file in ipairs(result) do
                if file:match("%.txt$") or file:match("%.lua$") or file:match("%.md$") then
                    table.insert(files, file)
                end
            end
        end
    end
    
    return files
end

-- Инициализация
fileList = getFileList(currentSource)
showFileSelector = false
