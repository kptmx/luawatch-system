-- Параметры экрана
local SW, SH = 410, 502
local scroll = 0
local files = {}
local selected_file = ""
local message = "Select a script"
local last_scan = 0

-- Функция сканирования файлов
function scan_files()
    local all = fs.list("/")
    files = {}
    for _, name in ipairs(all) do
        -- Отбираем только .lua файлы и игнорируем сам лаунчер
        if name:sub(-4) == ".lua" and name ~= "main.lua" then
            table.insert(files, name)
        end
    end
    last_scan = hw.millis()
end

-- Начальное сканирование
scan_files()

function draw()
    -- Фон
    ui.rect(0, 0, SW, SH, 0x0000) -- Черный
    
    -- Шапка
    ui.rect(0, 0, SW, 60, 0x2104) -- Темно-серый
    ui.text(80, 15, "LAUNCHER", 3, 0xFFFF)
    
    -- Инфо-панель
    ui.text(20, 70, message, 2, 0xCE79) -- Желтоватый
    ui.text(300, 70, hw.getBatt() .. "%", 2, 2016)

    -- Область списка файлов
    -- Высота контента = количество файлов * высота строки (50px)
    local content_h = #files * 55
    scroll = ui.beginList(10, 100, 390, 300, scroll, content_h)
    
    for i, name in ipairs(files) do
        local y = (i - 1) * 55
        local is_sel = (selected_file == name)
        
        -- Цвет кнопки: если выбрано — синий, иначе серый
        local btn_col = is_sel and 0x001F or 0x4208
        
        if ui.button(0, y, 300, 45, name, btn_col) then
            selected_file = name
            message = "Selected: " .. name
        end
    end
    ui.endList()

    -- Нижняя панель управления
    ui.rect(0, 410, SW, 92, 0x2104)

    -- Кнопка RUN
    if ui.button(20, 430, 110, 50, "RUN", 0x07E0) then -- Зеленый
        if selected_file ~= "" then
            local code = fs.load("/" .. selected_file)
            if code then
                -- ВАЖНО: загружаем новый код в среду выполнения
                local f, err = load(code)
                if f then
                    message = "Running..."
                    f() -- Запуск
                else
                    message = "Lua Error!"
                    print(err)
                end
            end
        else
            message = "Select file first!"
        end
    end

    -- Кнопка REFRESH
    if ui.button(150, 430, 110, 50, "SCAN", 0x001F) then
        scan_files()
        message = "Found " .. #files .. " files"
    end

    -- Кнопка DELETE
    if ui.button(280, 430, 110, 50, "DEL", 0xF800) then -- Красный
        if selected_file ~= "" then
            fs.remove("/" .. selected_file)
            message = "Deleted " .. selected_file
            selected_file = ""
            scan_files()
        else
            message = "Nothing to delete"
        end
    end
end
