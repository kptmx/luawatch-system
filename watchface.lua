-- Reader.lua — простая читалка с доводкой и прогрессбаром (без утечек)
local SCR_W, SCR_H = 410, 502
local LIST_X, LIST_Y, LIST_W, LIST_H = 5, 65, 400, 375

local mode = "selector"          -- "selector" или "reader"
local source = "flash"           -- "flash" или "sd"
local files = {}
local file_scroll = 0

-- Данные текущего файла (очищаем при закрытии)
local selected_file = nil
local full_path = nil
local text_lines = {}            
local pages = {}                 
local total_pages = 0
local current_page_idx = 1       
local reader_scroll = LIST_H     -- стартуем с центра (вторая страница из трёх)

-- Настройки отрисовки текста
local FONT_SIZE = 2
local LINE_H = 28                
local LEFT_MARGIN = 20
local TOP_MARGIN = 20
local LINES_PER_PAGE = math.floor((LIST_H - TOP_MARGIN * 2) / LINE_H)
local MAX_CHARS_PER_LINE = 52    

-- ===================================================================
-- Очистка памяти
-- ===================================================================
local function clear_file_data()
    -- Очищаем таблицы, чтобы сборщик мусора мог их удалить
    text_lines = {}
    pages = {}
    selected_file = nil
    full_path = nil
    total_pages = 0
    current_page_idx = 1
    
    -- Принудительно запускаем сборку мусора
    collectgarbage()
    collectgarbage()
end

-- ===================================================================
-- Утилиты
-- ===================================================================
local function get_fs()
    return (source == "flash") and fs or sd
end

local function refresh_file_list()
    local fs_obj = get_fs()
    local raw = fs_obj.list("/") or {}
    
    -- Очищаем предыдущий список
    files = {}
    
    for _, name in ipairs(raw) do
        if name ~= "" and not name:match("/$") then
            table.insert(files, name)
        end
    end
    table.sort(files)
end

local function wrap_text(raw_text)
    local lines = {}
    local line_count = 0
    
    for line in (raw_text .. "\n"):gmatch("([^\n]*)\n") do
        line_count = line_count + 1
        
        -- Защита от слишком больших файлов
        if line_count > 5000 then
            table.insert(lines, "[Файл слишком большой, показана только часть]")
            break
        end
        
        if #line == 0 then
            table.insert(lines, "")
        elseif #line <= MAX_CHARS_PER_LINE then
            table.insert(lines, line)
        else
            local words = {}
            for w in line:gmatch("%S+") do table.insert(words, w) end
            local cur = ""
            for _, w in ipairs(words) do
                local test = cur .. (cur == "" and "" or " ") .. w
                if #test > MAX_CHARS_PER_LINE then
                    table.insert(lines, cur)
                    cur = w
                else
                    cur = test
                end
            end
            if cur ~= "" then table.insert(lines, cur) end
        end
    end
    return lines
end

local function build_pages()
    -- Очищаем предыдущие страницы
    pages = {}
    
    local cur_page = {}
    local page_count = 0
    
    for _, ln in ipairs(text_lines) do
        table.insert(cur_page, ln)
        if #cur_page >= LINES_PER_PAGE then
            page_count = page_count + 1
            table.insert(pages, cur_page)
            cur_page = {}
        end
    end
    if #cur_page > 0 then
        table.insert(pages, cur_page)
    end
    
    total_pages = #pages
    if total_pages == 0 then 
        total_pages = 1
        pages = {{"[Пустой файл]"}}
    end
end

local function open_file(path)
    -- Очищаем память перед открытием нового файла
    clear_file_data()
    
    local fs_obj = get_fs()
    local content

    if source == "flash" then
        content = fs_obj.load(path)
        if not content then return false, "Не удалось прочитать файл" end
    else
        local res = fs_obj.readBytes(path)
        if type(res) ~= "string" then return false, "Не удалось прочитать файл с SD" end
        content = res
    end

    -- Проверяем размер
    if #content > 100 * 1024 then  -- 100KB лимит для безопасности
        return false, "Файл слишком большой (" .. math.floor(#content/1024) .. "KB)"
    end

    selected_file = path:gsub("^/", "")
    full_path = path
    text_lines = wrap_text(content)
    
    -- Очищаем сырой контент сразу после использования
    content = nil
    
    build_pages()
    current_page_idx = 1
    reader_scroll = LIST_H  -- центр
    mode = "reader"
    
    -- Запускаем сборку мусора
    collectgarbage()
    
    return true
end

-- ===================================================================
-- Прогресс чтения
-- ===================================================================
local function get_progress_percent()
    if total_pages <= 1 then return 0 end
    return math.floor((current_page_idx - 1) / (total_pages - 1) * 100)
end

local function draw_progress_bar(x, y, w, h, percent)
    -- Фон прогрессбара
    ui.rect(x, y, w, h, 0x4208)
    
    -- Заполнение
    local fill_w = math.floor(w * percent / 100)
    if fill_w > 0 then
        ui.rect(x, y, fill_w, h, 0x07E0)  -- Зелёный
    end
    
    -- Текст процентов
    local percent_text = percent .. "%"
    local text_x = x + w - 50
    local text_y = y - 20
    ui.text(text_x, text_y, percent_text, 2, 65535)
end

-- ===================================================================
-- Доводка скролла
-- ===================================================================
local function snap_scroll()
    local PAGE_H = LIST_H
    local changed = false
    
    -- Доводка вперёд (к следующей странице)
    if reader_scroll > PAGE_H + 20 and current_page_idx < total_pages then
        current_page_idx = current_page_idx + 1
        reader_scroll = reader_scroll - PAGE_H
        changed = true
    end
    
    -- Доводка назад (к предыдущей странице)
    if reader_scroll < PAGE_H - 20 and current_page_idx > 1 then
        current_page_idx = current_page_idx - 1
        reader_scroll = reader_scroll + PAGE_H
        changed = true
    end
    
    -- Блокировка на границах
    if current_page_idx == 1 then
        if reader_scroll < PAGE_H then
            reader_scroll = PAGE_H
            changed = true
        end
    end
    
    if current_page_idx == total_pages then
        if reader_scroll > PAGE_H then
            reader_scroll = PAGE_H
            changed = true
        end
    end
    
    -- Если были изменения, проверяем ещё раз
    if changed then
        snap_scroll()
    end
end

-- ===================================================================
-- Отрисовка
-- ===================================================================
function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)

    if mode == "selector" then
        -- Верхняя панель селектора
        ui.rect(0, 0, SCR_W, 60, 0x18C3)
        ui.text(10, 15, "Читалка — выбор файла", 2, 65535)

        -- Кнопки выбора источника
        if ui.button(20, 70, 170, 50, "Flash", source == "flash" and 2016 or 33808) then
            source = "flash"
            refresh_file_list()
            file_scroll = 0
            -- Очищаем данные файла при смене источника
            clear_file_data()
        end
        
        local sd_label = sd_ok and "SD-карта" or "SD нет"
        local sd_col = (source == "sd") and 2016 or 33808
        if sd_ok then
            if ui.button(210, 70, 170, 50, sd_label, sd_col) then
                source = "sd"
                refresh_file_list()
                file_scroll = 0
                clear_file_data()
            end
        else
            ui.rect(210, 70, 170, 50, 0x4208)
            ui.text(240, 90, "SD нет", 2, 65535)
        end

        -- Список файлов
        local item_h = 48
        local content_h = #files * item_h
        file_scroll = ui.beginList(LIST_X, LIST_Y + 60, LIST_W, LIST_H - 60, file_scroll, content_h)

        for i, fname in ipairs(files) do
            local y = (i - 1) * item_h
            if ui.button(0, y, LIST_W, item_h - 4, fname, 8452) then
                local ok, err = open_file("/" .. fname)
                if not ok then
                    ui.text(50, 200, "Ошибка: " .. (err or "???"), 2, 63488)
                    ui.flush()
                    delay(1500)
                end
            end
        end
        ui.endList()

    else -- mode == "reader"
        local PAGE_H = LIST_H
        local VIRTUAL_H = PAGE_H * 3

        -- Применяем доводку скролла
        snap_scroll()

        -- Отрисовка текста страниц
        reader_scroll = ui.beginList(LIST_X, LIST_Y, LIST_W, LIST_H, reader_scroll, VIRTUAL_H)

        local prev_p = math.max(1, current_page_idx - 1)
        local next_p = math.min(total_pages, current_page_idx + 1)
        local buffer = { prev_p, current_page_idx, next_p }

        for i = 1, 3 do
            local pidx = buffer[i]
            local base_y = (i - 1) * PAGE_H + TOP_MARGIN

            if pidx >= 1 and pidx <= total_pages then
                local page_lines = pages[pidx]
                if page_lines then
                    local page_content_h = #page_lines * LINE_H
                    local start_y = base_y + math.floor((PAGE_H - page_content_h - TOP_MARGIN) / 2)

                    for l, line in ipairs(page_lines) do
                        ui.text(LEFT_MARGIN, start_y + (l - 1) * LINE_H, line, FONT_SIZE, 65535)
                    end
                end
            end
        end
        ui.endList()

        -- Верхняя панель режима чтения
        ui.rect(0, 0, SCR_W, 70, 0x18C3)
        
        -- Имя файла
        local filename = selected_file or "???"
        if #filename > 25 then
            filename = filename:sub(1, 22) .. "..."
        end
        ui.text(10, 12, filename, 2, 65535)
        
        -- Номер страницы
        ui.text(SCR_W - 190, 12, "Стр. " .. current_page_idx .. "/" .. total_pages, 2, 65535)
        
        -- Кнопка назад
        if ui.button(SCR_W - 100, 8, 90, 35, "Back", 63488) then
            mode = "selector"
            file_scroll = 0
            -- Очищаем данные файла при выходе
            clear_file_data()
        end
        
        -- Прогрессбар
        local progress = get_progress_percent()
        draw_progress_bar(10, 50, SCR_W - 20, 8, progress)

        -- Подсказка по свайпу
        ui.text(SCR_W - 150, SCR_H - 20, "← свайп →", 1, 0x8410)
    end

    ui.flush()
end

-- Хелпер для задержки
function delay(ms)
    local start = hw.millis()
    while hw.millis() - start < ms do 
        -- просто ждём
    end
end

-- Инициализация
refresh_file_list()
clear_file_data()  -- Очищаем при старте
collectgarbage()
