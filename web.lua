-- Simple Web Browser for LuaWatch
local SW, SH = 410, 502

-- Состояние браузера
local url_input = "https://"
local page_content = ""
local history = {}
local scroll_pos = 0
local max_scroll = 0
local loading = false
local current_title = "Web Browser"
local status_msg = "Ready"
local bookmarks = {}
local zoom = 1.0

-- Элементы управления
local buttons = {
    {name = "BACK", x = 10, y = 10, w = 60, h = 40, col = 0x2104},
    {name = "FWD", x = 75, y = 10, w = 60, h = 40, col = 0x2104},
    {name = "RELOAD", x = 140, y = 10, w = 80, h = 40, col = 0x07E0},
    {name = "HOME", x = 225, y = 10, w = 70, h = 40, col = 0x6318},
    {name = "ZOOM+", x = 300, y = 10, w = 50, h = 40, col = 0x2104},
    {name = "ZOOM-", x = 355, y = 10, w = 45, h = 40, col = 0x2104},
}

-- Загрузка закладок
function load_bookmarks()
    if fs.exists("/bookmarks.txt") then
        local data = fs.load("/bookmarks.txt")
        if data then
            bookmarks = {}
            for line in data:gmatch("[^\r\n]+") do
                local title, url = line:match("(.+)|(.+)")
                if title and url then
                    table.insert(bookmarks, {title = title, url = url})
                end
            end
        end
    end
end

-- Сохранение закладок
function save_bookmarks()
    local data = ""
    for _, bm in ipairs(bookmarks) do
        data = data .. bm.title .. "|" .. bm.url .. "\n"
    end
    fs.save("/bookmarks.txt", data)
end

-- Добавить текущую страницу в закладки
function add_bookmark()
    if current_title ~= "Web Browser" and url_input ~= "" then
        table.insert(bookmarks, {title = current_title, url = url_input})
        save_bookmarks()
        status_msg = "Bookmark added!"
    end
end

-- Простой парсер HTML (упрощенный)
function parse_html(content)
    local result = ""
    
    -- Удаляем теги <script> и <style>
    content = content:gsub("<script[^>]*>.-</script>", "")
    content = content:gsub("<style[^>]*>.-</style>", "")
    
    -- Извлекаем заголовок
    local title = content:match("<title[^>]*>(.-)</title>")
    if title then
        current_title = title:gsub("&nbsp;", " "):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"):sub(1, 50)
    end
    
    -- Извлекаем основной текст
    local body = content:match("<body[^>]*>(.-)</body>") or content
    
    -- Упрощенное извлечение текста
    body = body:gsub("<br%s*/?>", "\n")
    body = body:gsub("<p[^>]*>", "\n")
    body = body:gsub("<div[^>]*>", "\n")
    body = body:gsub("<h[1-6][^>]*>", "\n## ")
    body = body:gsub("</h[1-6]>", "\n")
    
    -- Удаляем все остальные теги
    body = body:gsub("<[^>]+>", "")
    
    -- Заменяем HTML-сущности
    body = body:gsub("&nbsp;", " ")
    body = body:gsub("&lt;", "<")
    body = body:gsub("&gt;", ">")
    body = body:gsub("&amp;", "&")
    body = body:gsub("&quot;", "\"")
    body = body:gsub("&#(%d+);", function(n) return string.char(n) end)
    
    -- Ограничиваем длину
    result = body:sub(1, 5000)
    
    -- Добавляем заголовок в начало
    if title then
        result = "=== " .. current_title .. " ===\n\n" .. result
    end
    
    return result
end

-- Загрузка страницы
function load_page(url)
    if net.status() ~= 3 then
        status_msg = "No internet connection"
        return
    end
    
    if not url:match("^https?://") then
        url = "http://" .. url
        url_input = url
    end
    
    loading = true
    status_msg = "Loading..."
    
    -- Добавляем в историю
    if #history == 0 or history[#history] ~= url then
        table.insert(history, url)
        if #history > 20 then
            table.remove(history, 1)
        end
    end
    
    local res = net.get(url)
    
    if res and res.ok and res.code == 200 then
        page_content = parse_html(res.body)
        scroll_pos = 0
        status_msg = "Loaded"
        
        -- Сохраняем последнюю посещенную страницу
        fs.save("/last_page.txt", url)
    else
        page_content = "Error loading page\n"
        if res and res.code then
            page_content = page_content .. "HTTP Code: " .. res.code .. "\n"
            if res.err then
                page_content = page_content .. "Error: " .. res.err .. "\n"
            end
        end
        status_msg = "Load failed"
    end
    
    loading = false
end

-- Сохранение страницы
function save_page()
    if current_title and page_content ~= "" then
        local filename = "/pages/" .. current_title:gsub("[^%w]", "_") .. ".txt"
        fs.mkdir("/pages")
        fs.save(filename, page_content)
        status_msg = "Page saved!"
    end
end

-- Поиск в тексте
function search_text(text)
    if page_content == "" then return end
    
    local lower_content = page_content:lower()
    local lower_text = text:lower()
    
    local pos = lower_content:find(lower_text, scroll_pos + 1)
    if pos then
        scroll_pos = pos - 100
        if scroll_pos < 0 then scroll_pos = 0 end
        status_msg = "Found at position " .. pos
    else
        status_msg = "Text not found"
    end
end

-- Получение favicon (упрощенное)
function get_favicon_url(url)
    local domain = url:match("https?://([^/]+)")
    if domain then
        return "http://" .. domain .. "/favicon.ico"
    end
    return nil
end

-- Загрузка favicon (не отображается, но можно сохранить)
function load_favicon(url)
    local favicon_url = get_favicon_url(url)
    if favicon_url then
        local res = net.get(favicon_url)
        if res and res.ok then
            -- Можно сохранить favicon для отображения
            fs.save("/favicon.ico", res.body)
        end
    end
end

-- Отображение текста с прокруткой
function display_content()
    if page_content == "" then
        ui.text(10, 100, "Enter URL and press GO", 2, 0xFFFF)
        return
    end
    
    -- Определяем видимую часть текста
    local lines = {}
    for line in page_content:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    max_scroll = #lines * 20 -- примерная высота
    
    local start_line = math.floor(scroll_pos / 20)
    local y = 100
    local max_lines = math.floor(350 / 20) -- Сколько строк помещается
    
    for i = start_line + 1, math.min(start_line + max_lines, #lines) do
        local line = lines[i]
        if line then
            -- Обрезаем строку для отображения
            local display_line = line:sub(1, 60)
            ui.text(10, y, display_line, 1, 0xFFFF)
            y = y + 20
        end
    end
    
    -- Индикатор прокрутки
    if max_scroll > 350 then
        local scroll_bar_height = 350 * 350 / max_scroll
        local scroll_bar_pos = 350 * scroll_pos / max_scroll
        ui.rect(395, 100 + scroll_bar_pos, 10, scroll_bar_height, 0x6318)
    end
end

-- Отображение закладок
function show_bookmarks()
    local y = 100
    ui.text(10, y, "=== BOOKMARKS ===", 2, 0x07E0)
    y = y + 30
    
    for i, bm in ipairs(bookmarks) do
        if ui.button(10, y, 380, 40, bm.title:sub(1, 40), 0x2104) then
            url_input = bm.url
            load_page(bm.url)
            return
        end
        y = y + 45
        if y > 450 then break end
    end
    
    if #bookmarks == 0 then
        ui.text(10, 150, "No bookmarks yet", 1, 0xFFFF)
    end
end

-- Инициализация
function setup()
    load_bookmarks()
    
    -- Загружаем последнюю посещенную страницу
    if fs.exists("/last_page.txt") then
        local last_url = fs.load("/last_page.txt")
        if last_url then
            url_input = last_url
            load_page(last_url)
        end
    end
end

-- Основной цикл отрисовки
function draw()
    ui.rect(0, 0, SW, SH, 0x0000)
    
    -- Панель инструментов
    ui.rect(0, 0, SW, 60, 0x2104)
    
    -- Кнопки навигации
    for _, btn in ipairs(buttons) do
        if ui.button(btn.x, btn.y, btn.w, btn.h, btn.name, btn.col) then
            if btn.name == "BACK" and #history > 1 then
                table.remove(history) -- Удаляем текущую
                local prev_url = history[#history]
                if prev_url then
                    url_input = prev_url
                    load_page(prev_url)
                end
            elseif btn.name == "FWD" then
                -- В этой реализации нет вперед, можно добавить
                status_msg = "Forward not implemented"
            elseif btn.name == "RELOAD" and url_input ~= "" then
                load_page(url_input)
            elseif btn.name == "HOME" then
                url_input = "https://www.google.com"
                load_page(url_input)
            elseif btn.name == "ZOOM+" then
                zoom = math.min(zoom + 0.1, 2.0)
                status_msg = "Zoom: " .. math.floor(zoom * 100) .. "%"
            elseif btn.name == "ZOOM-" then
                zoom = math.max(zoom - 0.1, 0.5)
                status_msg = "Zoom: " .. math.floor(zoom * 100) .. "%"
            end
        end
    end
    
    -- Поле ввода URL
    if ui.input(10, 65, 330, 35, url_input, false) then
        -- Активируем клавиатуру для ввода
        -- В реальности нужно открыть экранную клавиатуру
        status_msg = "Press ENTER to go"
    end
    
    -- Кнопка GO
    if ui.button(345, 65, 55, 35, "GO", 0x07E0) then
        load_page(url_input)
    end
    
    -- Отображение статуса
    ui.text(10, 470, status_msg, 1, loading and 0xF800 or 0x07E0)
    
    -- Показываем текущий заголовок
    if current_title ~= "Web Browser" then
        ui.text(10, 490, current_title:sub(1, 50), 1, 0xFFFF)
    end
    
    -- Отображение контента или закладок
    if mode == "bookmarks" then
        show_bookmarks()
    else
        display_content()
    end
    
    -- Нижняя панель
    ui.rect(0, 460, SW, 42, 0x1082)
    
    -- Кнопки нижней панели
    if ui.button(10, 465, 80, 32, "SAVE", 0x6318) then
        save_page()
    end
    
    if ui.button(95, 465, 80, 32, "BOOKMARK", 0xF800) then
        add_bookmark()
    end
    
    if ui.button(180, 465, 80, 32, "BOOKMARKS", 0x07E0) then
        mode = mode == "bookmarks" and "browse" or "bookmarks"
    end
    
    if ui.button(265, 465, 80, 32, "SEARCH", 0x001F) then
        -- Здесь можно добавить поиск
        status_msg = "Search not implemented"
    end
    
    if ui.button(345, 465, 55, 32, "EXIT", 0x4208) then
        -- Возвращаемся в главное меню
        local f = load(fs.load("/main.lua"))
        if f then f() end
    end
    
    -- Индикатор загрузки
    if loading then
        ui.rect(380, 470, 20, 20, 0xF800)
    end
end

-- Обработка касаний для прокрутки
local last_touch_y = 0
local is_scrolling = false

function loop()
    local touch = ui.getTouch()
    
    if touch.touching then
        if not is_scrolling then
            last_touch_y = touch.y
            is_scrolling = true
        else
            local delta = last_touch_y - touch.y
            scroll_pos = scroll_pos + delta * 2
            if scroll_pos < 0 then scroll_pos = 0 end
            if scroll_pos > max_scroll then scroll_pos = max_scroll end
            last_touch_y = touch.y
        end
    else
        is_scrolling = false
    end
    
    -- Обработка клавиш (если есть физическая клавиатура)
    -- Можно добавить для удобства
end

-- Горячие клавиши
function handle_hotkeys()
    -- Здесь можно добавить обработку горячих клавиш
    -- Например, для сенсорной клавиатуры
end

-- Список популярных сайтов для быстрого доступа
local quick_sites = {
    {"Google", "https://www.google.com"},
    {"DuckDuckGo", "https://duckduckgo.com"},
    {"Wikipedia", "https://wikipedia.org"},
    {"GitHub", "https://github.com"},
    {"Hacker News", "https://news.ycombinator.com"},
    {"BBC News", "https://www.bbc.com/news"},
}

-- Функция для отображения быстрого доступа
function show_quick_access()
    ui.rect(0, 100, SW, 350, 0x0000)
    ui.text(10, 110, "=== Quick Access ===", 2, 0x07E0)
    
    local y = 150
    for i, site in ipairs(quick_sites) do
        if ui.button(10, y, 380, 40, site[1], 0x2104) then
            url_input = site[2]
            load_page(site[2])
        end
        y = y + 45
        if y > 400 then break end
    end
end

-- Инициализация при запуске
if not _G._BROWSER_INIT then
    _G._BROWSER_INIT = true
    mode = "browse" -- или "quick" для быстрого доступа
    setup()
end

-- Точки входа для главного меню
function browser_main()
    mode = "browse"
    draw()
end

function quick_access()
    mode = "quick"
    draw_quick_access = function()
        ui.rect(0, 0, SW, SH, 0x0000)
        show_quick_access()
        
        ui.rect(0, 460, SW, 42, 0x1082)
        if ui.button(10, 465, 100, 32, "BACK", 0x4208) then
            mode = "browse"
        end
        ui.text(150, 470, "Quick Access", 1, 0xFFFF)
    end
    draw = draw_quick_access
end
