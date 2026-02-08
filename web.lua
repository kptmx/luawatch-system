-- Enhanced Web Browser for LuaWatch with Rounded Screen
local SW, SH = 410, 502
local SCREEN_RADIUS = 20  -- Радиус закругления углов

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
local images = {}  -- Кэш загруженных изображений
local links = {}   -- Ссылки на странице
local hover_link = nil

-- Элементы управления (отступы от краев)
local buttons = {
    {name = "←", x = 15, y = 15, w = 50, h = 40, col = 0x2104, tooltip = "Back"},
    {name = "→", x = 70, y = 15, w = 50, h = 40, col = 0x2104, tooltip = "Forward"},
    {name = "↻", x = 125, y = 15, w = 50, h = 40, col = 0x07E0, tooltip = "Reload"},
    {name = "🏠", x = 180, y = 15, w = 50, h = 40, col = 0x6318, tooltip = "Home"},
    {name = "+", x = 310, y = 15, w = 40, h = 40, col = 0x2104, tooltip = "Zoom In"},
    {name = "-", x = 355, y = 15, w = 40, h = 40, col = 0x2104, tooltip = "Zoom Out"},
}

-- Безопасные координаты (избегаем углов)
function safe_x(x)
    return math.max(SCREEN_RADIUS, math.min(SW - SCREEN_RADIUS, x))
end

function safe_y(y)
    return math.max(SCREEN_RADIUS, math.min(SH - SCREEN_RADIUS, y))
end

-- Рисуем скругленный прямоугольник
function rounded_rect(x, y, w, h, color, radius)
    radius = radius or SCREEN_RADIUS
    -- Основной прямоугольник
    ui.rect(x + radius, y, w - 2*radius, h, color)
    ui.rect(x, y + radius, w, h - 2*radius, color)
    
    -- Углы (рисуем маленькие прямоугольники вместо кругов)
    ui.rect(x, y, radius, radius, color)
    ui.rect(x + w - radius, y, radius, radius, color)
    ui.rect(x, y + h - radius, radius, radius, color)
    ui.rect(x + w - radius, y + h - radius, radius, radius, color)
end

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
        status_msg = "✓ Bookmark added"
    end
end

-- Загрузка изображения
function load_image(img_url, x, y)
    if images[img_url] then return true end  -- Уже в кэше
    
    status_msg = "Loading image..."
    
    local res = net.get(img_url)
    if res and res.ok and res.code == 200 then
        -- Сохраняем временно
        local temp_path = "/temp_img.jpg"
        fs.save(temp_path, res.body)
        
        -- Проверяем, что это JPEG
        images[img_url] = {
            path = temp_path,
            x = x,
            y = y,
            loaded = true
        }
        status_msg = "Image loaded"
        return true
    end
    
    return false
end

-- Улучшенный парсер HTML с поддержкой ссылок и изображений
function parse_html(content, base_url)
    local result = {}
    links = {}
    images = {}
    
    -- Извлекаем заголовок
    local title = content:match("<title[^>]*>(.-)</title>")
    if title then
        current_title = title:gsub("&nbsp;", " "):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&"):sub(1, 50)
        table.insert(result, {type = "title", text = "=== " .. current_title .. " ==="})
    end
    
    -- Извлекаем основной текст
    local body = content:match("<body[^>]*>(.-)</body>") or content
    
    -- Упрощенный парсинг с поддержкой ссылок и изображений
    local pos = 1
    while pos <= #body do
        -- Ищем теги
        local tag_start, tag_end = body:find("<[^>]+>", pos)
        
        if not tag_start then
            -- Оставшийся текст
            local text = body:sub(pos)
            if text:match("%S") then  -- Если не пустой
                table.insert(result, {type = "text", text = text})
            end
            break
        end
        
        -- Текст перед тегом
        local text_before = body:sub(pos, tag_start - 1)
        if text_before:match("%S") then
            table.insert(result, {type = "text", text = text_before})
        end
        
        -- Обрабатываем тег
        local tag = body:sub(tag_start, tag_end)
        
        if tag:match("^<a[^>]*href") then
            -- Ссылка
            local link_text = body:match(">(.-)</a>", tag_end) or ""
            local href = tag:match('href%s*=%s*["\']([^"\']+)["\']')
            
            if href and link_text:match("%S") then
                -- Абсолютный URL
                if href:match("^https?://") then
                    -- уже абсолютный
                elseif href:match("^//") then
                    href = "https:" .. href
                elseif href:match("^/") then
                    local domain = base_url:match("(https?://[^/]+)")
                    if domain then href = domain .. href end
                else
                    -- относительный
                    local base = base_url:match("(.-/)[^/]*$")
                    if base then href = base .. href end
                end
                
                if href and href:match("^https?://") then
                    table.insert(links, {
                        url = href,
                        text = link_text:gsub("<[^>]+>", ""):sub(1, 100),
                        index = #result + 1
                    })
                    table.insert(result, {
                        type = "link",
                        text = "[" .. link_text:gsub("<[^>]+>", ""):sub(1, 50) .. "]",
                        url = href
                    })
                end
            end
            
            -- Пропускаем текст ссылки
            local link_end = body:find("</a>", tag_end)
            if link_end then
                pos = link_end + 4
            else
                pos = tag_end + 1
            end
            
        elseif tag:match("^<img[^>]*src") then
            -- Изображение
            local src = tag:match('src%s*=%s*["\']([^"\']+)["\']')
            local alt = tag:match('alt%s*=%s*["\']([^"\']+)["\']') or "Image"
            
            if src then
                -- Абсолютный URL для изображения
                if not src:match("^https?://") then
                    if src:match("^//") then
                        src = "https:" .. src
                    elseif src:match("^/") then
                        local domain = base_url:match("(https?://[^/]+)")
                        if domain then src = domain .. src end
                    else
                        local base = base_url:match("(.-/)[^/]*$")
                        if base then src = base .. src end
                    end
                end
                
                if src and src:match("^https?://") then
                    table.insert(result, {
                        type = "image",
                        url = src,
                        alt = alt,
                        placeholder = "[IMG: " .. alt:sub(1, 30) .. "]"
                    })
                end
            end
            pos = tag_end + 1
            
        elseif tag:match("^<br") or tag:match("^<p") or tag:match("^<div") then
            table.insert(result, {type = "newline"})
            pos = tag_end + 1
            
        elseif tag:match("^<h[1-6]") then
            local heading_text = body:match(">(.-)</h[1-6]>", tag_end)
            if heading_text then
                table.insert(result, {type = "heading", text = "## " .. heading_text})
                local closing_tag = body:find("</h[1-6]>", tag_end)
                if closing_tag then
                    pos = closing_tag + 5
                else
                    pos = tag_end + 1
                end
            else
                pos = tag_end + 1
            end
            
        else
            -- Игнорируем другие теги
            pos = tag_end + 1
        end
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
    page_content = {}
    links = {}
    images = {}
    
    -- Добавляем в историю
    if #history == 0 or history[#history] ~= url then
        table.insert(history, url)
        if #history > 20 then
            table.remove(history, 1)
        end
    end
    
    local res = net.get(url)
    
    if res and res.ok and res.code == 200 then
        page_content = parse_html(res.body, url)
        scroll_pos = 0
        status_msg = "✓ Loaded"
        
        -- Сохраняем последнюю посещенную страницу
        fs.save("/last_page.txt", url)
        
        -- Загружаем favicon
        local favicon_url = get_favicon_url(url)
        if favicon_url then
            -- Асинхронно загружаем favicon
            -- (можно добавить в отдельную задачу)
        end
    else
        table.insert(page_content, {type = "text", text = "Error loading page"})
        if res and res.code then
            table.insert(page_content, {type = "text", text = "HTTP Code: " .. res.code})
        end
        status_msg = "✗ Load failed"
    end
    
    loading = false
end

-- Получение favicon URL
function get_favicon_url(url)
    local domain = url:match("https?://([^/]+)")
    if domain then
        return "http://" .. domain .. "/favicon.ico"
    end
    return nil
end

-- Отображение контента с поддержкой элементов
function display_content()
    if #page_content == 0 then
        ui.text(safe_x(50), safe_y(150), "Enter URL and press GO", 2, 0xFFFF)
        return
    end
    
    local content_start_y = 110
    local content_width = 380
    local line_height = 20 * zoom
    local current_y = content_start_y - scroll_pos
    hover_link = nil
    
    -- Рассчитываем максимальную прокрутку
    local total_height = 0
    for _, element in ipairs(page_content) do
        if element.type == "text" or element.type == "link" or element.type == "heading" then
            local lines = math.ceil(#element.text / (content_width / (8 * zoom)))
            total_height = total_height + lines * line_height
        elseif element.type == "title" then
            total_height = total_height + 30 * zoom
        elseif element.type == "newline" then
            total_height = total_height + line_height
        elseif element.type == "image" then
            total_height = total_height + 100 * zoom  -- Место под изображение
        end
    end
    max_scroll = math.max(0, total_height - 350)
    
    -- Отображаем видимые элементы
    local touch = ui.getTouch()
    
    for _, element in ipairs(page_content) do
        if current_y < SH and current_y + line_height > content_start_y then
            if element.type == "title" then
                ui.text(safe_x(10), safe_y(current_y), element.text, 2, 0x07E0)
                current_y = current_y + 30 * zoom
                
            elseif element.type == "heading" then
                ui.text(safe_x(10), safe_y(current_y), element.text, 1, 0xF800)
                current_y = current_y + 25 * zoom
                
            elseif element.type == "text" then
                -- Обрезаем текст по ширине
                local display_text = element.text:sub(1, math.floor(content_width / (8 * zoom)))
                ui.text(safe_x(10), safe_y(current_y), display_text, 1, 0xFFFF)
                current_y = current_y + line_height
                
            elseif element.type == "link" then
                local display_text = element.text
                local text_color = 0x07FF  -- Голубой для ссылок
                
                -- Проверяем наведение
                if touch.touching then
                    local text_width = #display_text * 8 * zoom
                    if touch.x >= 10 and touch.x <= 10 + text_width and
                       touch.y >= current_y and touch.y <= current_y + line_height then
                        text_color = 0xFFFF  -- Белый при наведении
                        hover_link = element.url
                        
                        -- Обрабатываем клик
                        if touch.pressed then
                            load_page(element.url)
                            return
                        end
                    end
                end
                
                ui.text(safe_x(10), safe_y(current_y), display_text, 1, text_color)
                current_y = current_y + line_height
                
            elseif element.type == "image" then
                -- Отображаем плейсхолдер
                ui.rect(safe_x(10), safe_y(current_y), 100, 80, 0x2104)
                ui.text(safe_x(15), safe_y(current_y + 30), element.placeholder, 1, 0xFFFF)
                
                -- Проверяем наведение на кнопку загрузки
                if touch.touching and touch.x >= 120 and touch.x <= 220 and
                   touch.y >= current_y and touch.y <= current_y + 30 then
                    if touch.pressed then
                        -- Загружаем изображение
                        if load_image(element.url, 10, current_y) then
                            status_msg = "Loading image..."
                        end
                    end
                end
                
                -- Кнопка загрузки изображения
                ui.button(120, current_y, 100, 30, "Load Image", 0x6318)
                
                current_y = current_y + 100 * zoom
                
            elseif element.type == "newline" then
                current_y = current_y + line_height
            end
        else
            -- Пропускаем невидимые элементы, но считаем их высоту
            if element.type == "text" or element.type == "link" or element.type == "heading" then
                local lines = math.ceil(#element.text / (content_width / (8 * zoom)))
                current_y = current_y + lines * line_height
            elseif element.type == "title" then
                current_y = current_y + 30 * zoom
            elseif element.type == "newline" then
                current_y = current_y + line_height
            elseif element.type == "image" then
                current_y = current_y + 100 * zoom
            end
        end
        
        if current_y > SH + scroll_pos then
            break
        end
    end
    
    -- Отображаем загруженные изображения
    for img_url, img_data in pairs(images) do
        if img_data.loaded and img_data.y - scroll_pos >= content_start_y and 
           img_data.y - scroll_pos <= SH - 50 then
            if ui.drawJPEG(img_data.x, img_data.y - scroll_pos, img_data.path) then
                -- Успешно отображено
            else
                ui.text(safe_x(img_data.x + 5), safe_y(img_data.y - scroll_pos + 40), 
                       "[Failed to display]", 1, 0xF800)
            end
        end
    end
    
    -- Индикатор прокрутки (справа, с отступом)
    if max_scroll > 0 then
        local scroll_bar_height = 350 * 350 / (total_height + 50)
        local scroll_bar_pos = 350 * scroll_pos / (total_height + 50)
        rounded_rect(SW - 25, content_start_y + scroll_bar_pos, 15, 
                    math.max(20, scroll_bar_height), 0x6318, 5)
    end
end

-- Отображение закладок
function show_bookmarks()
    local y = 120
    ui.text(safe_x(20), safe_y(y), "★ Bookmarks", 2, 0xFFE0)
    y = y + 40
    
    for i, bm in ipairs(bookmarks) do
        if y < 400 then
            if ui.button(safe_x(20), safe_y(y), 360, 35, 
                        bm.title:sub(1, 35), 0x2104) then
                url_input = bm.url
                load_page(bm.url)
                return
            end
            ui.text(safe_x(25), safe_y(y + 25), bm.url:sub(1, 40), 1, 0x8C71)
            y = y + 60
        end
    end
    
    if #bookmarks == 0 then
        ui.text(safe_x(20), safe_y(200), "No bookmarks yet", 1, 0xFFFF)
        ui.text(safe_x(20), safe_y(220), "Press ★ on any page to add", 1, 0x8C71)
    end
end

-- Главное меню браузера
function show_main_menu()
    local y = 120
    ui.text(safe_x(20), safe_y(y), "🌐 Web Browser", 3, 0x07E0)
    y = y + 60
    
    -- Быстрые ссылки
    local quick_links = {
        {"Google", "https://www.google.com"},
        {"DuckDuckGo", "https://duckduckgo.com"},
        {"Wikipedia", "https://wikipedia.org"},
        {"GitHub", "https://github.com"},
        {"Hacker News", "https://news.ycombinator.com"},
        {"BBC News", "https://www.bbc.com/news"},
    }
    
    for _, link in ipairs(quick_links) do
        if y < 350 then
            if ui.button(safe_x(20), safe_y(y), 360, 35, link[1], 0x2104) then
                url_input = link[2]
                load_page(link[2])
                mode = "browse"
                return
            end
            y = y + 45
        end
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
    -- Фон с учетом закругленных углов
    rounded_rect(0, 0, SW, SH, 0x0000, SCREEN_RADIUS)
    
    -- Панель инструментов (закругленная сверху)
    rounded_rect(0, 0, SW, 70, 0x2104, SCREEN_RADIUS)
    
    -- Кнопки навигации (с отступами от краев)
    for _, btn in ipairs(buttons) do
        if ui.button(btn.x, btn.y, btn.w, btn.h, btn.name, btn.col) then
            if btn.name == "←" and #history > 1 then
                table.remove(history) -- Удаляем текущую
                local prev_url = history[#history]
                if prev_url then
                    url_input = prev_url
                    load_page(prev_url)
                end
            elseif btn.name == "→" then
                -- В этой реализации нет вперед
                status_msg = "Forward: Not implemented"
            elseif btn.name == "↻" and url_input ~= "" then
                load_page(url_input)
            elseif btn.name == "🏠" then
                url_input = "https://www.google.com"
                load_page(url_input)
            elseif btn.name == "+" then
                zoom = math.min(zoom + 0.1, 2.0)
                status_msg = "Zoom: " .. math.floor(zoom * 100) .. "%"
            elseif btn.name == "-" then
                zoom = math.max(zoom - 0.1, 0.5)
                status_msg = "Zoom: " .. math.floor(zoom * 100) .. "%"
            end
        end
    end
    
    -- Поле ввода URL (с отступами)
    rounded_rect(10, 65, 320, 35, 0x0000, 5)
    ui.text(15, 72, url_input:sub(-30), 1, 0xFFFF)
    
    -- Кнопка GO
    if ui.button(335, 65, 60, 35, "GO", 0x07E0) then
        load_page(url_input)
        mode = "browse"
    end
    
    -- Текущий заголовок (если есть)
    if current_title ~= "Web Browser" then
        ui.text(safe_x(20), 75, current_title:sub(1, 30), 1, 0xCE79)
    end
    
    -- Отображение контента в зависимости от режима
    if mode == "menu" then
        show_main_menu()
    elseif mode == "bookmarks" then
        show_bookmarks()
    else
        display_content()
    end
    
    -- Статус бар (снизу, с отступами от углов)
    rounded_rect(0, SH - 50, SW, 50, 0x1082, SCREEN_RADIUS)
    
    -- Кнопки нижней панели
    if mode == "browse" then
        if ui.button(15, SH - 45, 70, 35, "★", hover_link and 0xFFE0 or 0x8C71) then
            if hover_link then
                url_input = hover_link
                load_page(hover_link)
            else
                add_bookmark()
            end
        end
        
        if ui.button(90, SH - 45, 70, 35, "📖", 0x6318) then
            mode = "bookmarks"
        end
        
        if ui.button(165, SH - 45, 70, 35, "💾", 0x07E0) then
            save_page()
        end
        
        if ui.button(240, SH - 45, 70, 35, "🏠", 0x001F) then
            mode = "menu"
        end
        
        if ui.button(315, SH - 45, 80, 35, "Exit", 0xF800) then
            -- Очищаем временные файлы
            for _, img_data in pairs(images) do
                if img_data.path and fs.exists(img_data.path) then
                    fs.remove(img_data.path)
                end
            end
            -- Возвращаемся в главное меню
            local f = load(fs.load("/main.lua"))
            if f then f() end
        end
    else
        -- Кнопка возврата в режиме не-browse
        if ui.button(15, SH - 45, 380, 35, "← Back to Browser", 0x2104) then
            mode = "browse"
        end
    end
    
    -- Статус сообщение
    ui.text(safe_x(20), SH - 15, status_msg, 1, 
           loading and 0xF800 or (status_msg:sub(1,1) == "✓" and 0x07E0 or 0xFFFF))
    
    -- Индикатор загрузки
    if loading then
        local pulse = math.floor((hw.millis() % 1000) / 500)
        ui.rect(safe_x(SW - 40), SH - 40, 20, 20, pulse == 0 and 0xF800 or 0x0000)
    end
    
    -- Подсказка для ссылки при наведении
    if hover_link and mode == "browse" then
        ui.rect(safe_x(10), SH - 90, 390, 25, 0x0000)
        ui.text(safe_x(12), SH - 85, hover_link:sub(1, 48), 1, 0x07FF)
    end
end

-- Сохранение страницы
function save_page()
    if current_title and #page_content > 0 then
        local filename = "/pages/" .. current_title:gsub("[^%w]", "_") .. ".txt"
        fs.mkdir("/pages")
        
        local content = ""
        for _, element in ipairs(page_content) do
            if element.type == "text" or element.type == "title" or element.type == "heading" then
                content = content .. element.text .. "\n"
            elseif element.type == "link" then
                content = content .. element.text .. " -> " .. element.url .. "\n"
            elseif element.type == "image" then
                content = content .. "[Image: " .. element.alt .. " -> " .. element.url .. "]\n"
            end
        end
        
        fs.save(filename, content)
        status_msg = "✓ Page saved"
    end
end

-- Прокрутка с учетом касаний
local last_touch_y = 0
local is_scrolling = false

function loop()
    local touch = ui.getTouch()
    
    if touch.touching and touch.y > 70 and touch.y < SH - 60 then
        if not is_scrolling then
            last_touch_y = touch.y
            is_scrolling = true
        else
            local delta = last_touch_y - touch.y
            scroll_pos = scroll_pos + delta * 2
            scroll_pos = math.max(0, math.min(max_scroll, scroll_pos))
            last_touch_y = touch.y
        end
    else
        is_scrolling = false
    end
    
    -- Автоматическая очистка старых изображений
    for img_url, img_data in pairs(images) do
        if img_data.path and not fs.exists(img_data.path) then
            images[img_url] = nil
        end
    end
end

-- Инициализация при запуске
if not _G._BROWSER_INIT then
    _G._BROWSER_INIT = true
    mode = "menu"  -- Начинаем с меню
    setup()
end
