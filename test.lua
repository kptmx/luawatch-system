-- Простой веб-браузер на Lua БЕЗ поддержки изображений
-- Ссылки встроены в текст страницы

local SCR_W, SCR_H = 410, 502
local LINE_H = 28
local MAX_CHARS_PER_LINE = 45  -- Увеличим для более естественного переноса

local current_url = "https://www.furtails.pw"
local history, history_pos = {}, 0
local scroll_y = 0
local content = {}  -- Каждый элемент: {text, is_link, url, x, y, w, h}
local content_height = 0

-- ==========================================
-- ПРОСТОЙ ПАРСЕР HTML
-- ==========================================

-- Декодирование HTML-сущностей
local function decode_html_entities(str)
    if not str then return "" end
    str = str:gsub("&lt;", "<")
    str = str:gsub("&gt;", ">")
    str = str:gsub("&amp;", "&")
    str = str:gsub("&quot;", '"')
    str = str:gsub("&#(%d+);", function(code)
        return string.char(tonumber(code))
    end)
    str = str:gsub("&nbsp;", " ")
    return str
end

-- Разрешение относительных ссылок
local function resolve_url(base, href)
    if not href then return nil end
    href = href:gsub("^%s+", ""):gsub("%s+$", "")
    
    if href:sub(1,2) == "//" then return "https:" .. href end
    if href:match("^https?://") then return href end
    if href:match("^mailto:") or href:match("^javascript:") or href:match("^#") then 
        return nil 
    end
    
    local proto, domain = base:match("^(https?://)([^/]+)")
    if not proto then return nil end
    
    if href:sub(1,1) == "/" then
        return proto .. domain .. href
    end
    
    local path = base:match("^https?://[^/]+(.*/)") or "/"
    return proto .. domain .. path .. href
end

-- Основной парсинг
local function parse_html(html)
    content = {}
    content_height = 100
    
    -- Удаляем ненужное
    html = html:gsub("<!%-%-.-%-%->", "")  -- комментарии
    html = html:gsub("<script[^>]*>.-</script>", "")  -- скрипты
    html = html:gsub("<style[^>]*>.-</style>", "")   -- стили
    html = html:gsub("<img[^>]*>", "")  -- изображения
    
    -- Преобразуем теги
    html = html:gsub("<br%s*/?>", "\n")
    html = html:gsub("<p>", "\n")
    html = html:gsub("</p>", "\n\n")
    html = html:gsub("<h%d>", "\n\n")
    html = html:gsub("</h%d>", "\n\n")
    html = html:gsub("<div>", "\n")
    html = html:gsub("</div>", "\n")
    
    -- Удаляем все остальные теги, но сохраняем ссылки
    local result = {}
    local pos = 1
    local in_link = false
    local current_link = nil
    
    while pos <= #html do
        -- Ищем тег
        local tag_start = html:find("<", pos)
        
        if not tag_start then
            -- Текст до конца
            local text = html:sub(pos)
            text = decode_html_entities(text)
            if text ~= "" then
                table.insert(result, {
                    text = text,
                    is_link = in_link,
                    url = current_link
                })
            end
            break
        end
        
        if tag_start > pos then
            -- Текст до тега
            local text = html:sub(pos, tag_start - 1)
            text = decode_html_entities(text)
            if text ~= "" then
                table.insert(result, {
                    text = text,
                    is_link = in_link,
                    url = current_link
                })
            end
        end
        
        -- Обрабатываем тег
        local tag_end = html:find(">", tag_start)
        if not tag_end then break end
        
        local tag = html:sub(tag_start + 1, tag_end - 1)
        local tag_name = tag:match("^/?([%w]+)")
        
        if tag_name then
            tag_name = tag_name:lower()
            
            if tag_name == "a" then
                if tag:sub(1,1) == "/" then
                    -- Закрывающий тег </a>
                    in_link = false
                    current_link = nil
                else
                    -- Открывающий тег <a>
                    local href = tag:match('href%s*=%s*"([^"]+)"') or 
                                 tag:match("href%s*=%s*'([^']+)'")
                    current_link = resolve_url(current_url, href)
                    if current_link then
                        in_link = true
                    end
                end
            end
        end
        
        pos = tag_end + 1
    end
    
    -- Теперь формируем контент для отображения
    prepare_content(result)
end

-- Подготовка контента для отображения
local function prepare_content(parts)
    content = {}
    local x = 20
    local y = 10
    local current_line = ""
    local current_line_is_link = false
    local current_line_url = nil
    local line_start_x = x
    
    -- Примерные размеры символов
    local CHAR_W = 12 * 2  -- Для размера текста 2
    
    local function add_text_segment(text, is_link, url)
        local segment_w = #text * CHAR_W
        
        if x + segment_w > SCR_W - 20 then
            -- Перенос строки
            x = 20
            y = y + LINE_H
        end
        
        table.insert(content, {
            text = text,
            is_link = is_link,
            url = url,
            x = x,
            y = y,
            w = segment_w,
            h = LINE_H
        })
        
        x = x + segment_w
    end
    
    for _, part in ipairs(parts) do
        local text = part.text
        
        -- Разбиваем текст на слова
        for word in text:gmatch("[^%s]+") do
            add_text_segment(word .. " ", part.is_link, part.url)
        end
        
        -- Если был пробел в конце
        if text:match("%s$") then
            add_text_segment(" ", false, nil)
        end
    end
    
    content_height = y + LINE_H + 40
end

-- ==========================================
-- ОСНОВНЫЕ ФУНКЦИИ
-- ==========================================

-- Загрузка страницы
function load_page(new_url)
    if not new_url:match("^https?://") then
        new_url = "https://" .. new_url
    end
    
    print("Loading: " .. new_url)
    
    local res = net.get(new_url)
    if res.ok and res.code == 200 then
        current_url = new_url
        table.insert(history, current_url)
        history_pos = #history
        parse_html(res.body)
        scroll_y = 0
        print("Page loaded successfully")
    else
        print("Error loading page")
        -- Простая ошибка
        content = {{
            text = "Error loading page: " .. tostring(res.err or "unknown"),
            is_link = false,
            url = nil,
            x = 20,
            y = 20,
            w = 200,
            h = LINE_H
        }}
        content_height = 100
    end
    
    draw()
    ui.flush()
end

-- Назад
local function go_back()
    if history_pos > 1 then
        history_pos = history_pos - 1
        load_page(history[history_pos])
    end
end

-- Проверка клика
local function handle_click(x, y)
    for _, item in ipairs(content) do
        if item.is_link and item.url then
            if x >= item.x and x <= item.x + item.w and
               y >= item.y and y <= item.y + item.h then
                print("Clicked link: " .. item.url)
                load_page(item.url)
                return true
            end
        end
    end
    return false
end

-- ==========================================
-- ОТРИСОВКА
-- ==========================================

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)  -- Черный фон

    -- Панель URL
    ui.rect(0, 0, SCR_W, 40, 0x2104)
    local display_url = current_url
    if #display_url > 40 then
        display_url = display_url:sub(1, 37) .. "..."
    end
    ui.text(10, 10, display_url, 2, 0xFFFF)

    -- Панель управления
    ui.rect(0, 40, SCR_W, 50, 0x3186)
    
    if history_pos > 1 then
        if ui.button(10, 45, 80, 40, "Back", 0x4A69) then 
            go_back()
        end
    end
    
    if ui.button(100, 45, 100, 40, "Reload", 0x4A69) then 
        load_page(current_url)
    end
    
    if ui.button(210, 45, 100, 40, "Home", 0x4A69) then 
        load_page("https://www.furtails.pw")
    end
    
    -- Кнопка тестовой загрузки
    if ui.button(320, 45, 80, 40, "Test", 0x4A69) then 
        load_page("https://textise dot iitty")
    end

    -- Область контента
    scroll_y = ui.beginList(0, 90, SCR_W, SCR_H - 90, scroll_y, content_height)
    
    -- Обработка кликов
    local touch = ui.getTouch()
    if touch and touch.released then
        handle_click(touch.x, touch.y + scroll_y - 90)  -- Учитываем скролл
    end
    
    -- Отображение текста
    for _, item in ipairs(content) do
        local color = item.is_link and 0x07FF or 0xFFFF
        ui.text(item.x, item.y, item.text, 2, color)
        
        -- Подчеркивание для ссылок
        if item.is_link then
            ui.rect(item.x, item.y + 22, item.w, 1, 0x07FF)
        end
    end
    
    ui.endList()
    
    -- Статусная строка
    ui.rect(0, SCR_H - 30, SCR_W, 30, 0x2104)
    
    -- Подсчет ссылок
    local link_count = 0
    for _, item in ipairs(content) do
        if item.is_link then link_count = link_count + 1 end
    end
    
    ui.text(10, SCR_H - 25, "Links: " .. link_count, 1, 0x7BEF)
    ui.text(SCR_W - 100, SCR_H - 25, #content .. " items", 1, 0x7BEF)
end

-- ==========================================
-- ИНИЦИАЛИЗАЦИЯ
-- ==========================================

-- Загружаем стартовую страницу
load_page(current_url)

-- Основной цикл
-- Функция draw() будет вызываться автоматически из прошивки
