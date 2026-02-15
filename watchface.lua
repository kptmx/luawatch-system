-- ────────────────────────────────────────────────
-- Читалка текстовых файлов (LuaWatch)
-- ────────────────────────────────────────────────

-- Константы
local SCR_W, SCR_H = 410, 502
local TEXT_SIZE = 2  -- Размер шрифта (1 для читаемости)
local CHAR_W = 16    -- Примерная ширина символа в unifont (16px для size=1)
local LINE_H = 20    -- Высота строки с отступом
local MARGIN_X = 10  -- Отступы слева/справа
local MARGIN_Y = 40  -- Отступы сверху (для статуса) / снизу
local LINES_PER_PAGE = math.floor((SCR_H - 2 * MARGIN_Y) / LINE_H)  -- ~23 строки
local STATUS_H = 30  -- Высота строки статуса
local FADE_STEPS = 10  -- Шаги анимации fade (больше — плавнее, но медленнее)
local FADE_DELAY = 20  -- Задержка между шагами (мс)

-- Цвета
local COLOR_BG = 0       -- Черный
local COLOR_TEXT = 0xFFFF -- Белый
local COLOR_GRAY = 0x8410 -- Серый (для fade)
local COLOR_ACCENT = 0x07E0 -- Зеленый для прогресса
local COLOR_WARN = 0xF800  -- Красный для ошибок

-- Глобальные переменные
local file_path = "/book.txt"  -- Путь к файлу (замените на ваш)
local full_text = ""           -- Полный текст файла
local pages = {}               -- Массив страниц (каждая — таблица строк)
local current_page = 1         -- Текущая страница
local total_pages = 1          -- Всего страниц
local touch_start_x, touch_start_y = -1, -1  -- Для свайпа
local is_swiping = false       -- Флаг свайпа
local error_msg = ""           -- Сообщение об ошибке

-- ────────────────────────────────────────────────
-- Вспомогательные функции
-- ────────────────────────────────────────────────

-- Темнее цвета (RGB565)
function darken_color(color, factor)
    local r = bit.band(bit.rshift(color, 11), 0x1F)
    local g = bit.band(bit.rshift(color, 5), 0x3F)
    local b = bit.band(color, 0x1F)
    r = math.floor(r * factor / 255)
    g = math.floor(g * factor / 255)
    b = math.floor(b * factor / 255)
    return bit.bor(bit.lshift(r, 11), bit.lshift(g, 5), b)
end

-- Разбивка текста на строки с переносом по словам
function wrap_text(text)
    local lines = {}
    local current_line = ""
    local words = {}
    for word in string.gmatch(text, "[^%s]+") do table.insert(words, word) end
    for i, word in ipairs(words) do
        local test_line = current_line .. (current_line == "" and "" or " ") .. word
        local approx_width = string.len(test_line) * CHAR_W
        if approx_width <= (SCR_W - 2 * MARGIN_X) then
            current_line = test_line
        else
            if current_line ~= "" then table.insert(lines, current_line) end
            current_line = word
        end
    end
    if current_line ~= "" then table.insert(lines, current_line) end
    return lines
end

-- Разбивка текста на страницы
function paginate_text()
    pages = {}
    local res = fs.readBytes(file_path)
    if not res.ok then
        error_msg = res.err or "File not found"
        return
    end
    full_text = res[1]  -- lua_pushlstring возвращает как 1 аргумент

    -- Удаляем \r для совместимости с CRLF
    full_text = string.gsub(full_text, "\r", "")

    -- Разбиваем на строки по \n сначала (параграфы)
    local raw_lines = {}
    for line in string.gmatch(full_text, "([^\n]*)\n?") do
        table.insert(raw_lines, line)
    end

    -- Теперь wrap каждую raw_line и собираем все wrapped lines
    local all_lines = {}
    for _, raw in ipairs(raw_lines) do
        local wrapped = wrap_text(raw)
        for _, w in ipairs(wrapped) do table.insert(all_lines, w) end
        table.insert(all_lines, "")  -- Пустая строка для параграфа
    end

    -- Собираем страницы
    local page = {}
    for _, line in ipairs(all_lines) do
        table.insert(page, line)
        if #page >= LINES_PER_PAGE then
            table.insert(pages, page)
            page = {}
        end
    end
    if #page > 0 then table.insert(pages, page) end
    total_pages = #pages
end

-- Отрисовка страницы с опциональным fade_factor (0-255, 255=полный)
function draw_page(page_num, fade_factor)
    if fade_factor == nil then fade_factor = 255 end
    local text_color = darken_color(COLOR_TEXT, fade_factor)

    ui.rect(0, 0, SCR_W, SCR_H, COLOR_BG)  -- Очистка

    -- Статус сверху
    local time = hw.getTime()
    local batt = hw.getBatt()
    local progress = math.floor((current_page / total_pages) * 100)
    local status_text = string.format("%02d:%02d  Batt: %d%%  Page %d/%d (%d%%)", time.h, time.m, batt, page_num, total_pages, progress)
    ui.text(MARGIN_X, 5, status_text, 1, COLOR_GRAY)

    -- Прогресс-бар
    local prog_w = math.floor((SCR_W - 2 * MARGIN_X) * (current_page / total_pages))
    ui.rect(MARGIN_X, STATUS_H - 5, SCR_W - 2 * MARGIN_X, 3, 0x4208)  -- Фон
    ui.rect(MARGIN_X, STATUS_H - 5, prog_w, 3, COLOR_ACCENT)         -- Прогресс

    -- Текст
    local page = pages[page_num]
    if page then
        for i, line in ipairs(page) do
            ui.text(MARGIN_X, MARGIN_Y + (i-1) * LINE_H, line, TEXT_SIZE, text_color)
        end
    end

    -- Кнопки Prev/Next (внизу)
    if ui.button(20, SCR_H - 50, 180, 40, "Prev", COLOR_ACCENT) then prev_page() end
    if ui.button(SCR_W - 200, SCR_H - 50, 180, 40, "Next", COLOR_ACCENT) then next_page() end
end

-- Анимация переключения страницы
function animate_page_flip(new_page)
    -- Fade out текущей
    for i = FADE_STEPS, 1, -1 do
        local factor = math.floor(255 * (i / FADE_STEPS))
        draw_page(current_page, factor)
        ui.flush()
        hw.millis()  -- Просто вызов для yield, но лучше os.execute("delay " .. FADE_DELAY) если есть, иначе loop
        -- Поскольку нет delay в bindings, используем hw.millis() в цикле
        local start = hw.millis()
        while hw.millis() - start < FADE_DELAY do end
    end

    -- Меняем страницу
    current_page = new_page

    -- Fade in новой
    for i = 1, FADE_STEPS do
        local factor = math.floor(255 * (i / FADE_STEPS))
        draw_page(current_page, factor)
        ui.flush()
        local start = hw.millis()
        while hw.millis() - start < FADE_DELAY do end
    end
end

-- Переход к следующей/предыдущей
function next_page()
    if current_page < total_pages then
        animate_page_flip(current_page + 1)
    end
end

function prev_page()
    if current_page > 1 then
        animate_page_flip(current_page - 1)
    end
end

-- Обработка свайпа (left/right для страниц)
function handle_swipe()
    local touch = ui.getTouch()
    if touch.touching then
        if not is_swiping then
            touch_start_x = touch.x
            touch_start_y = touch.y
            is_swiping = true
        end
    else
        if is_swiping then
            local dx = touch.x - touch_start_x
            local dy = touch.y - touch_start_y
            if math.abs(dx) > 100 and math.abs(dy) < 50 then  -- Горизонтальный свайп
                if dx < 0 then next_page() else prev_page() end
            end
            is_swiping = false
        end
    end
end

-- ────────────────────────────────────────────────
-- Основной цикл draw()
-- ────────────────────────────────────────────────
function draw()
    if error_msg ~= "" then
        ui.rect(0, 0, SCR_W, SCR_H, COLOR_BG)
        ui.text(20, SCR_H/2 - 20, "Error: " .. error_msg, 2, COLOR_WARN)
        ui.flush()
        return
    end

    handle_swipe()
    draw_page(current_page)
    ui.flush()
end

-- Инициализация
paginate_text()
if total_pages == 0 then error_msg = "Empty file" end
