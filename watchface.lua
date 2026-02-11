-- Простая читалка текстовых файлов для LuaWatch
-- Поддержка: выбор из Flash/SD, бесконечный скролл с буфером из 3 страниц, snap к страницам
-- Исправления: обработка границ для малых файлов, предотвращение отрицательных страниц, добавлен выход

-- Константы
local SCR_W, SCR_H = 410, 502  -- Размеры экрана (из вашего примера)
local FONT_SIZE = 1            -- Размер шрифта для текста (1 для unifont ~16px)
local LINE_HEIGHT = 16         -- Высота строки (для unifont_t_cyrillic)
local LIST_X, LIST_Y, LIST_W, LIST_H = 5, 65, 400, 375  -- Область списка (из вашего примера)
local PAGE_LINES = math.floor(LIST_H / LINE_HEIGHT)  -- Строк на страницу (~23 для 375/16)
local PAGE_HEIGHT = PAGE_LINES * LINE_HEIGHT   -- Высота страницы в пикселях
local BUFFER_PAGES = 3                         -- Буфер: prev, current, next
local TOTAL_HEIGHT = BUFFER_PAGES * PAGE_HEIGHT  -- Полная высота виртуального списка

-- Состояние приложения
local mode = "source_select"  -- "source_select", "file_select", "reader", "exit"
local sources = {"Flash", "SD"}  -- Источники
local selected_source = 1
local files = {}              -- Список файлов
local selected_file = 1
local text_lines = {}         -- Строки текста (таблица)
local total_pages = 0         -- Общее страниц в файле
local current_page = 1        -- Текущая страница (1-based)
local list_scroll = PAGE_HEIGHT  -- Начальный скролл: на средней странице
local snap_target = nil       -- Цель для доводки (анимация snap)
local snap_speed = 0.2        -- Скорость анимации (0.1-0.3 для плавности)

-- Функция для получения списка .txt файлов из источника
local function load_files(source)
    files = {}
    local fs_lib = (source == "Flash") and fs or sd
    local res = fs_lib.list("/")
    if res then
        for _, fname in ipairs(res) do
            if fname:lower():match("%.txt$") then
                table.insert(files, fname)
            end
        end
        table.sort(files)  -- Сортировка по алфавиту
    end
end

-- Функция для загрузки и разбивки текста на строки
local function load_text(source, fname)
    text_lines = {}
    local fs_lib = (source == "Flash") and fs or sd
    local res = fs_lib.readBytes("/" .. fname)
    if res and res.ok then
        local text = res[1]  -- lstring
        for line in text:gmatch("([^\n]*)\n?") do
            table.insert(text_lines, line)
        end
        total_pages = math.ceil(#text_lines / PAGE_LINES)
        if total_pages == 0 then total_pages = 1 end  -- Минимум 1 страница для пустого файла
        current_page = 1
        list_scroll = PAGE_HEIGHT
    else
        -- Ошибка: вернуться к выбору файлов
        mode = "file_select"
    end
end

-- Функция для рендеринга страницы текста на заданной y-позиции
local function render_page(page, base_y)
    if page < 1 or page > total_pages then return end
    local start_line = (page - 1) * PAGE_LINES + 1
    local end_line = math.min(start_line + PAGE_LINES - 1, #text_lines)
    local y = base_y
    for i = start_line, end_line do
        ui.text(10, y, text_lines[i], FONT_SIZE, 0xFFFF)  -- Белый текст, отступ слева
        y = y + LINE_HEIGHT
    end
end

-- Обновление буфера страниц при перелистывании
local function update_buffer()
    if list_scroll >= 2 * PAGE_HEIGHT and current_page < total_pages - 1 then
        -- Перешли вниз: сдвигаем буфер
        current_page = current_page + 1
        list_scroll = list_scroll - PAGE_HEIGHT
    elseif list_scroll < PAGE_HEIGHT and current_page > 1 then
        -- Перешли вверх: сдвигаем буфер
        current_page = current_page - 1
        list_scroll = list_scroll + PAGE_HEIGHT
    end
    -- Ограничения (на всякий случай)
    current_page = math.max(1, current_page)
    current_page = math.min(total_pages - 1, current_page)
end

-- Логика snap: вычислить ближайшую границу страницы с учетом границ
local function get_snap_target(sy)
    local page_idx = math.floor(sy / PAGE_HEIGHT + 0.5)
    local min_idx = (current_page == 1) and 1 or 0
    local max_idx = (current_page + 1 > total_pages) and 1 or 2
    page_idx = math.max(min_idx, math.min(max_idx, page_idx))
    return page_idx * PAGE_HEIGHT
end

-- Основная функция отрисовки
function draw()
    if mode == "exit" then return end  -- Выход из скрипта (прекращаем отрисовку)

    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)  -- Черный фон

    if mode == "source_select" then
        -- Выбор источника (Flash/SD)
        ui.text(100, 100, "Select Source:", 2, 0xFFFF)
        for i, src in ipairs(sources) do
            local color = (i == selected_source) and 0x07E0 or 0x4208  -- Зеленый/серый
            if ui.button(100, 150 + (i-1)*60, 200, 50, src, color) then
                load_files(src)
                mode = "file_select"
            end
        end

    elseif mode == "file_select" then
        -- Список файлов
        ui.text(100, 20, "Select File:", 2, 0xFFFF)
        list_scroll = ui.beginList(LIST_X, LIST_Y, LIST_W, LIST_H, list_scroll, #files * 30)  -- Пример: 30px на файл
        local y = 0
        for i, fname in ipairs(files) do
            local color = (i == selected_file) and 0x07E0 or 0x4208
            if ui.button(0, y, LIST_W, 28, fname, color) then
                load_text(sources[selected_source], fname)
                mode = "reader"
            end
            y = y + 30
        end
        ui.endList()
        -- Кнопка назад
        if ui.button(10, 10, 100, 40, "Back", 0xF800) then
            mode = "source_select"
        end
        -- Кнопка выхода
        if ui.button(300, 10, 100, 40, "Exit", 0xF800) then
            mode = "exit"
        end

    elseif mode == "reader" then
        -- Читалка: список с буфером 3 страниц
        -- Сначала обработка snap и обновления буфера
        local touch = ui.getTouch()
        if not touch.touching then
            -- Нет касания: применяем snap/анимацию
            if snap_target == nil then
                snap_target = get_snap_target(list_scroll)
            end
            -- Анимация к цели
            local delta = snap_target - list_scroll
            if math.abs(delta) > 1 then
                list_scroll = list_scroll + delta * snap_speed
            else
                list_scroll = snap_target
                snap_target = nil
                -- После snap: проверить и обновить буфер (если перешли границу)
                update_buffer()
            end
        else
            -- Касание: сбрасываем цель snap
            snap_target = nil
        end

        -- Рендеринг виртуального списка
        list_scroll = ui.beginList(LIST_X, LIST_Y, LIST_W, LIST_H, list_scroll, TOTAL_HEIGHT)
        -- Рендерим 3 страницы: prev, current, next
        render_page(current_page - 1, 0)
        render_page(current_page, PAGE_HEIGHT)
        render_page(current_page + 1, 2 * PAGE_HEIGHT)
        ui.endList()

        -- Инфо: страница / всего
        ui.text(10, 10, "Page " .. current_page .. "/" .. total_pages, 2, 0xFFFF)
        -- Кнопка назад
        if ui.button(200, 10, 100, 40, "Back", 0xF800) then
            mode = "file_select"
            list_scroll = 0  -- Сброс скролла для списка файлов
        end
        -- Кнопка выхода
        if ui.button(300, 10, 100, 40, "Exit", 0xF800) then
            mode = "exit"
        end

    end

    ui.flush()
end
