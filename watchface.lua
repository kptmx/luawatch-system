-- Константы экрана
local SCR_W, SCR_H = 410, 502
local LIST_Y, LIST_H = 65, 375
local PAGE_H = LIST_H -- Высота одной "страницы"

-- Состояние приложения: "browser" или "reader"
local mode = "browser"
local current_path = "/"
local current_fs = fs -- по умолчанию внутренняя память
local files = {}
local selected_file = ""

-- Состояние читалки
local pages = {"", "", ""} -- [1] прошлый, [2] текущий, [3] следующий
local line_pointers = {}    -- Указатели на начало строк для навигации по файлу
local current_line_idx = 1
local scroll_y = PAGE_H     -- Начинаем со "средней" страницы
local last_applied_scroll = PAGE_H

-- Загрузка списка файлов
function load_dir(path, storage)
    current_path = path
    current_fs = storage
    local res = storage.list(path)
    if res and not res.err then
        files = res
    else
        files = {".. (Error)"}
    end
end

-- Простая нарезка текста на страницы (упрощенно)
function get_chunk(start_line)
    -- В реальности тут должна быть логика чтения из файла побайтово
    -- Для примера читаем кусок текста (в вашей прошивке лучше доработать f.read)
    local raw = current_fs.load(selected_file) or ""
    local lines = {}
    for s in raw:gmatch("[^\r\n]+") do table.insert(lines, s) end
    
    local res = ""
    for i = start_line, start_line + 15 do -- примерно 15 строк на экран
        if lines[i] then res = res .. lines[i] .. "\n" end
    end
    return res
end

function init_reader(file)
    selected_file = file
    mode = "reader"
    pages[1] = "--- End of Start ---"
    pages[2] = get_chunk(1)
    pages[3] = get_chunk(16)
    scroll_y = PAGE_H
end

function update_infinite_scroll()
    -- Если пользователь перелистнул вниз (на 3-ю страницу)
    if scroll_y >= PAGE_H * 2 - 10 then
        current_line_idx = current_line_idx + 15
        pages[1] = pages[2]
        pages[2] = pages[3]
        pages[3] = get_chunk(current_line_idx + 30)
        scroll_y = PAGE_H -- Возвращаем в центр
    
    -- Если пользователь перелистнул вверх (на 1-ю страницу)
    elseif scroll_y <= 10 and current_line_idx > 1 then
        current_line_idx = math.max(1, current_line_idx - 15)
        pages[3] = pages[2]
        pages[2] = pages[1]
        pages[1] = get_chunk(math.max(1, current_line_idx - 15))
        scroll_y = PAGE_H -- Возвращаем в центр
    end
end

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)

    if mode == "browser" then
        ui.text(20, 20, "File Browser", 2, 0x07FF)
        
        -- Выбор хранилища
        if ui.button(20, 300, 180, 40, "Internal", 0x4444) then load_dir("/", fs) end
        if ui.button(210, 300, 180, 40, "SD Card", 0x4444) then load_dir("/", sd) end

        -- Список файлов
        local list_scroll = 0
        list_scroll = ui.beginList(5, 60, 400, 230, list_scroll, #files * 40)
        for i, f in ipairs(files) do
            if ui.button(10, (i-1)*40, 380, 35, f, 0x2104) then
                init_reader(current_path .. f)
            end
        end
        ui.endList()

    elseif mode == "reader" then
        ui.text(10, 10, "Reading: " .. selected_file, 1, 0xFD20)
        if ui.button(330, 5, 70, 30, "BACK", 0xF800) then mode = "browser" end

        -- Виртуальный размер списка в 3 раза больше области (PAGE_H * 3)
        scroll_y = ui.beginList(5, LIST_Y, 400, LIST_H, scroll_y, PAGE_H * 3)
            
            -- Отрисовка трех страниц
            ui.text(10, 0, pages[1], 2, 0x8410)        -- Прошлая (серая)
            ui.text(10, PAGE_H, pages[2], 2, 0xFFFF)   -- Текущая (белая)
            ui.text(10, PAGE_H * 2, pages[3], 2, 0x8410) -- Следующая (серая)
            
        ui.endList()

        update_infinite_scroll()
    end
end
