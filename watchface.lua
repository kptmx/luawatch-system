-- Простая читалка текстовых файлов
-- Поддержка Flash (LittleFS) и SD
-- Infinite scroll для страниц текста

local SCR_W, SCR_H = 410, 502  -- Размеры экрана
local mode = "select_storage"  -- Режимы: select_storage, select_file, read
local storage = ""  -- "flash" или "sd"
local files = {}  -- Список файлов
local selected_file = ""
local content = ""
local lines = {}
local current_page = 0
local total_pages = 0
local list_scroll = 0
local file_scroll = 0
local msg = ""

-- Параметры рендеринга текста
local text_size = 1  -- Размер текста (1 для больше строк, 2 для крупнее)
local line_h = 20 * text_size  -- Высота строки (подгоните под шрифт, ~16-20 для size=1, ~30 для size=2)
local visible_h = 375  -- Высота видимой области
local lines_per_page = math.floor(visible_h / line_h)
local page_h = lines_per_page * line_h  -- Реальная высота страницы в пикселях (может быть < visible_h)
local color = 65535  -- Белый

-- Функция для чтения файла (унифицированная для fs и sd)
local function read_file(path, store)
    local res
    if store == "flash" then
        res = fs.readBytes(path)
    else
        res = sd.readBytes(path)
    end
    if type(res) == "table" then
        if not res.ok then
            msg = "Read error: " .. (res.err or "unknown")
            return false
        end
    else
        return res  -- Строка с содержимым
    end
    return false
end

-- Разбивка текста на строки
local function split_lines(text)
    local ls = {}
    for line in text:gmatch("([^\n]*)\n?") do
        table.insert(ls, line)
    end
    return ls
end

-- Отрисовка одной страницы текста начиная с base_y
local function render_page(page_idx, base_y)
    local start_line = page_idx * lines_per_page + 1
    for i = 1, lines_per_page do
        local ly = base_y + (i - 1) * line_h
        local line = lines[start_line + i - 1] or ""
        ui.text(10, ly, line, text_size, color)
    end
end

-- Основная функция отрисовки
function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)  -- Очистка экрана
    ui.text(10, 10, msg, 1, 65535)  -- Сообщения

    if mode == "select_storage" then
        ui.text(100, 50, "Select storage", 2, color)
        if ui.button(100, 150, 200, 50, "Flash", 2016) then
            mode = "select_file"
            storage = "flash"
            local res = fs.list("/")
            if type(res) == "table" and not res.ok then
                msg = "FS list error"
            else
                files = res or {}
            end
        end
        if ui.button(100, 220, 200, 50, "SD", 2016) then
            mode = "select_file"
            storage = "sd"
            local res = sd.list("/")
            if type(res) == "table" and not res.ok then
                msg = "SD list error"
            else
                files = res or {}
            end
        end
    elseif mode == "select_file" then
        ui.text(10, 20, "Select .txt file from " .. storage, 2, color)
        if ui.button(300, 20, 100, 40, "Back", 63488) then
            mode = "select_storage"
            files = {}
        end

        -- Фильтруем только .txt
        local txt_files = {}
        for _, f in ipairs(files) do
            if f:match("%.txt$") then
                table.insert(txt_files, f)
            end
        end

        -- Список файлов
        local item_h = 30
        local content_h = #txt_files * item_h
        file_scroll = ui.beginList(5, 65, 400, 375, file_scroll, content_h)
        for i = 1, #txt_files do
            local iy = (i - 1) * item_h
            if ui.button(0, iy, 400, item_h, txt_files[i], 8452) then
                local path = "/" .. txt_files[i]
                local txt = read_file(path, storage)
                if txt then
                    content = txt
                    lines = split_lines(content)
                    total_pages = math.ceil(#lines / lines_per_page)
                    current_page = 0
                    list_scroll = page_h  -- По умолчанию на средней странице
                    mode = "read"
                    msg = "Loaded: " .. txt_files[i]
                else
                    msg = "Failed to load file"
                end
            end
        end
        ui.endList()
    elseif mode == "read" then
        ui.text(10, 20, "Reading: " .. selected_file .. " (page " .. (current_page + 1) .. "/" .. total_pages .. ")", 2, color)
        if ui.button(300, 20, 100, 40, "Back", 63488) then
            mode = "select_file"
            content = ""
            lines = {}
            total_pages = 0
            list_scroll = 0
        end

        -- Корректировка позиции перед отрисовкой (для seamless shift)
        if list_scroll <= 0 and current_page > 0 then
            current_page = current_page - 1
            list_scroll = list_scroll + page_h
        elseif list_scroll >= page_h * 2 and current_page < total_pages - 2 then
            current_page = current_page + 1
            list_scroll = list_scroll - page_h
        end

        -- Отрисовка списка с 3 страницами
        local content_h = page_h * 3
        list_scroll = ui.beginList(5, 65, 400, 375, list_scroll, content_h)

        -- Предыдущая страница
        if current_page > 0 then
            render_page(current_page - 1, 0)
        end

        -- Текущая страница
        render_page(current_page, page_h)

        -- Следующая страница
        if current_page + 1 < total_pages then
            render_page(current_page + 1, page_h * 2)
        end

        ui.endList()
    end

    ui.flush()
end
