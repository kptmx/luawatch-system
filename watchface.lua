-- Reader.lua — простая читалка (все файлы, без фильтра .txt)
local SCR_W, SCR_H = 410, 502
local LIST_X, LIST_Y, LIST_W, LIST_H = 5, 65, 400, 375

local mode = "selector"          -- "selector" или "reader"
local source = "flash"           -- "flash" или "sd"
local files = {}
local file_scroll = 0

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
-- Утилиты
-- ===================================================================
local function get_fs()
    return (source == "flash") and fs or sd
end

local function refresh_file_list()
    local fs_obj = get_fs()
    local raw = fs_obj.list("/") or {}
    files = {}
    for _, name in ipairs(raw) do
        -- Показываем ВСЕ файлы (без фильтра по расширению)
        if name ~= "" and not name:match("/$") then  -- исключаем папки, если они попадают
            table.insert(files, name)
        end
    end
    table.sort(files)
end

local function wrap_text(raw_text)
    local lines = {}
    for line in (raw_text .. "\n"):gmatch("([^\n]*)\n") do
        if #line == 0 then
            table.insert(lines, "")
        elseif #line <= MAX_CHARS_PER_LINE then
            table.insert(lines, line)
        else
            -- word wrap
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
    pages = {}
    local cur_page = {}
    for _, ln in ipairs(text_lines) do
        table.insert(cur_page, ln)
        if #cur_page >= LINES_PER_PAGE then
            table.insert(pages, cur_page)
            cur_page = {}
        end
    end
    if #cur_page > 0 then table.insert(pages, cur_page) end
    total_pages = #pages
    if total_pages == 0 then total_pages = 1 end  -- хотя бы одна пустая страница
end

local function open_file(path)
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

    selected_file = path:gsub("^/", "")
    full_path = path
    text_lines = wrap_text(content)
    build_pages()
    current_page_idx = math.min(current_page_idx, total_pages)
    if current_page_idx < 1 then current_page_idx = 1 end
    reader_scroll = LIST_H
    mode = "reader"
    return true
end

-- ===================================================================
-- Отрисовка
-- ===================================================================
function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)                       -- фон

    if mode == "selector" then
        -- Верхняя панель селектора
        ui.rect(0, 0, SCR_W, 60, 0x18C3)
        ui.text(10, 15, "Читалка — выбор файла", 2, 65535)

        -- Кнопки выбора источника
        if ui.button(20, 70, 170, 50, "Flash", source == "flash" and 2016 or 33808) then
            source = "flash"
            refresh_file_list()
        end
        local sd_label = sd_ok and "SD-карта" or "SD нет"
        local sd_col = (source == "sd") and 2016 or 33808
        if sd_ok and ui.button(210, 70, 170, 50, sd_label, sd_col) then
            source = "sd"
            refresh_file_list()
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
                    -- показываем ошибку поверх
                    ui.text(50, 200, "Ошибка: " .. (err or "???"), 2, 63488)
                end
            end
        end
        ui.endList()

    else -- mode == "reader"
        local PAGE_H = LIST_H
        local VIRTUAL_H = PAGE_H * 3

        -- Сначала рисуем список (только текст страниц)
        reader_scroll = ui.beginList(LIST_X, LIST_Y, LIST_W, LIST_H, reader_scroll, VIRTUAL_H)

        local prev_p = math.max(1, current_page_idx - 1)
        local next_p = math.min(total_pages, current_page_idx + 1)
        local buffer = { prev_p, current_page_idx, next_p }

        for i = 1, 3 do
            local pidx = buffer[i]
            local base_y = (i - 1) * PAGE_H + TOP_MARGIN

            if pidx >= 1 and pidx <= total_pages then
                local page_lines = pages[pidx]
                local page_content_h = #page_lines * LINE_H
                local start_y = base_y + math.floor((PAGE_H - page_content_h - TOP_MARGIN) / 2)

                for l, line in ipairs(page_lines) do
                    ui.text(LEFT_MARGIN, start_y + (l - 1) * LINE_H, line, FONT_SIZE, 65535)
                end
            else
                -- пустая страница — на всякий случай
                ui.text(LEFT_MARGIN, base_y + 100, "(пустая страница)", FONT_SIZE, 0x630C)
            end
        end
        ui.endList()

        -- Перелистывание с доводкой (незаметно для пользователя)
        local shifted = true
        while shifted do
            shifted = false
            if reader_scroll >= 2 * PAGE_H and current_page_idx < total_pages then
                current_page_idx = current_page_idx + 1
                reader_scroll = reader_scroll - PAGE_H
                shifted = true
            elseif reader_scroll < PAGE_H and current_page_idx > 1 then
                current_page_idx = current_page_idx - 1
                reader_scroll = reader_scroll + PAGE_H
                shifted = true
            end
        end

        -- Верхняя панель режима чтения — рисуется ПОСЛЕ endList, чтобы не скроллилась
        ui.rect(0, 0, SCR_W, 60, 0x18C3)
        ui.text(10, 15, selected_file or "???", 2, 65535)
        ui.text(SCR_W - 190, 15, "Стр. " .. current_page_idx .. "/" .. total_pages, 2, 65535)
        if ui.button(SCR_W - 100, 12, 90, 40, "Back", 63488) then
            mode = "selector"
            file_scroll = 0
        end

        -- Если файл пустой
        if total_pages == 1 and #pages[1] == 0 then
            ui.text(50, 200, "Файл пустой или не текст", 2, 63488)
        end
    end

    ui.flush()
end

-- Инициализация
refresh_file_list()
