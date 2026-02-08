-- Простой веб-браузер для LuaWatch
-- Автор: DeepSeek

local SCR_W, SCR_H = 410, 502
local PAGE_W, PAGE_H = SCR_W, 400  -- Область для отображения страницы
local KEYBOARD_Y = 300            -- Начало клавиатуры

-- Состояние браузера
local browser = {
    url = "https://raw.githubusercontent.com/kptmx/luawatch/main/main.lua",
    history = {},
    history_index = 0,
    current_page = "",
    page_pos = 0,  -- Прокрутка страницы
    loading = false,
    status = "Готов",
    zoom = 1.0,
    cache = {},    -- Кэш загруженных страниц
    images = {}    -- Кэш изображений
}

-- T9 клавиатура
local t9 = {
    [".,!1"] = ".,!1", ["abc2"] = "abc2", ["def3"] = "def3",
    ["ghi4"] = "ghi4", ["jkl5"] = "jkl5", ["mno6"] = "mno6",
    ["pqrs7"] = "pqrs7", ["tuv8"] = "tuv8", ["wxyz9"] = "wxyz9",
    ["*"] = "://.-+=", ["0"] = " ", ["#"] = "#/?"
}

local keys = {
    ".,!1", "abc2", "def3",
    "ghi4", "jkl5", "mno6",
    "pqrs7", "tuv8", "wxyz9",
    "*", "0", "#",
    "DEL", "CLR", "OK"
}

-- Ввод URL
local input_mode = false
local input_text = ""
local last_key, last_time, char_idx = "", 0, 0
local cursor_blink = true
local cursor_timer = 0

-- Прокрутка страницы
local scroll_speed = 20
local scroll_btn_size = 40

-- Загрузка изображений из кэша
function load_cached_image(url)
    if browser.images[url] then
        return true
    end
    
    -- Проверяем, есть ли изображение в памяти
    local filename = "/cache/" .. string.gsub(url, "[^%w]", "_") .. ".jpg"
    if fs.exists(filename) then
        browser.images[url] = filename
        return true
    end
    
    return false
end

-- Кэширование изображения
function cache_image(url, data)
    local filename = "/cache/" .. string.gsub(url, "[^%w]", "_") .. ".jpg"
    fs.save(filename, data)
    browser.images[url] = filename
end

-- Скачивание страницы
function download_page(url)
    browser.loading = true
    browser.status = "Загрузка..."
    ui.flush()
    
    -- Проверяем кэш
    if browser.cache[url] then
        browser.current_page = browser.cache[url]
        browser.loading = false
        browser.status = "Загружено из кэша"
        table.insert(browser.history, url)
        browser.history_index = #browser.history
        return
    end
    
    local res = net.get(url)
    
    if res and res.ok then
        browser.current_page = res.body
        browser.cache[url] = res.body  -- Кэшируем
        browser.status = "Загружено"
        
        -- Сохраняем в историю
        table.insert(browser.history, url)
        browser.history_index = #browser.history
        
        -- Пытаемся найти и загрузить изображения
        extract_and_load_images(res.body, url)
    else
        browser.status = "Ошибка: " .. (res and res.code or "нет соединения")
        browser.current_page = "<h1>Ошибка загрузки</h1><p>Не удалось загрузить: " .. url .. "</p>"
    end
    
    browser.loading = false
end

-- Извлечение и загрузка изображений из HTML
function extract_and_load_images(html, base_url)
    local base_domain = string.match(base_url, "https?://[^/]+")
    
    -- Ищем все теги img
    for img_url in string.gmatch(html, '<img[^>]+src="([^"]+)"') do
        -- Преобразуем относительные URL в абсолютные
        if string.sub(img_url, 1, 1) == "/" then
            img_url = base_domain .. img_url
        elseif not string.find(img_url, "https?://") then
            img_url = base_domain .. "/" .. img_url
        end
        
        -- Проверяем, JPEG ли это
        if string.find(string.lower(img_url), "%.jpg$") or 
           string.find(string.lower(img_url), "%.jpeg$") then
           
            -- Проверяем кэш
            if not load_cached_image(img_url) then
                -- Загружаем в фоновом режиме
                local download_res = net.get(img_url)
                if download_res and download_res.ok then
                    cache_image(img_url, download_res.body)
                end
            end
        end
    end
end

-- Обработка T9 ввода
function handle_t9_input(k)
    local now = hw.millis()
    local chars = t9[k]
    if not chars then return end
    
    -- Если нажата та же клавиша в течение 800мс — меняем символ
    if k == last_key and (now - last_time) < 800 then
        input_text = input_text:sub(1, -2)
        char_idx = (char_idx % #chars) + 1
    else
        char_idx = 1
    end
    
    input_text = input_text .. chars:sub(char_idx, char_idx)
    last_key, last_time = k, now
end

-- Простой парсер HTML для отображения
function render_simple_html(html)
    -- Удаляем теги script и style
    html = string.gsub(html, "<script[^>]*>.-</script>", "")
    html = string.gsub(html, "<style[^>]*>.-</style>", "")
    
    -- Заменяем теги заголовков
    html = string.gsub(html, "<h1[^>]*>(.-)</h1>", "\n=== %1 ===\n")
    html = string.gsub(html, "<h2[^>]*>(.-)</h2>", "\n== %1 ==\n")
    html = string.gsub(html, "<h3[^>]*>(.-)</h3>", "\n= %1 =\n")
    
    -- Обрабатываем параграфы
    html = string.gsub(html, "<p[^>]*>(.-)</p>", "%1\n")
    
    -- Извлекаем текст из ссылок
    html = string.gsub(html, '<a[^>]+href="([^"]+)"[^>]*>(.-)</a>', 
        function(url, text)
            return "[LINK:" .. url .. "]" .. text .. "[/LINK]"
        end)
    
    -- Удаляем остальные теги
    html = string.gsub(html, "<[^>]+>", "")
    
    -- Декодируем HTML-сущности
    html = string.gsub(html, "&lt;", "<")
    html = string.gsub(html, "&gt;", ">")
    html = string.gsub(html, "&amp;", "&")
    html = string.gsub(html, "&quot;", '"')
    
    -- Ограничиваем длину для производительности
    if #html > 5000 then
        html = string.sub(html, 1, 5000) .. "\n[... текст обрезан ...]"
    end
    
    return html
end

-- Отображение страницы
function render_page()
    if browser.current_page == "" then return end
    
    -- Простой рендеринг текста
    local text = render_simple_html(browser.current_page)
    
    -- Разбиваем на строки
    local lines = {}
    for line in string.gmatch(text .. "\n", "(.-)\n") do
        table.insert(lines, line)
    end
    
    -- Отображаем с прокруткой
    local start_line = math.floor(browser.page_pos / 20)
    local y_offset = 100 - (browser.page_pos % 20)
    
    for i = start_line + 1, math.min(#lines, start_line + 20) do
        local line = lines[i]
        local x = 10
        
        -- Парсим ссылки в строке
        while true do
            local link_start, link_end, url, link_text = 
                string.find(line, "%[LINK:([^%]]+)%]([^%[]+)%[/LINK%]")
            
            if not link_start then break end
            
            -- Текст до ссылки
            ui.text(x, y_offset, string.sub(line, 1, link_start-1), 1, 65535)
            x = x + (link_start-1) * 8
            
            -- Сама ссылка (подчеркнутая)
            ui.text(x, y_offset, link_text, 1, 2016)
            
            -- Проверяем, нажата ли ссылка
            local touch = ui.getTouch()
            if touch.touching then
                local tx, ty = touch.x, touch.y
                if tx >= x and tx <= x + #link_text * 8 and
                   ty >= y_offset and ty <= y_offset + 20 then
                    ui.rect(x, y_offset + 18, #link_text * 8, 2, 2016)  -- Подчеркивание
                    
                    if touch.released then
                        browser.url = url
                        download_page(url)
                        browser.page_pos = 0
                        return
                    end
                end
            else
                ui.rect(x, y_offset + 18, #link_text * 8, 2, 2016)  -- Подчеркивание
            end
            
            x = x + #link_text * 8
            line = string.sub(line, link_end + 1)
        end
        
        -- Остаток строки
        ui.text(x, y_offset, line, 1, 65535)
        
        y_offset = y_offset + 20
        if y_offset > PAGE_H then break end
    end
end

-- Поиск изображений в странице и их отображение
function render_images()
    local base_domain = string.match(browser.url, "https?://[^/]+")
    local y_offset = 100 - (browser.page_pos % 20)
    
    -- Ищем все изображения в HTML
    for img_url in string.gmatch(browser.current_page, '<img[^>]+src="([^"]+)"') do
        -- Преобразуем относительные URL
        if string.sub(img_url, 1, 1) == "/" then
            img_url = base_domain .. img_url
        elseif not string.find(img_url, "https?://") then
            img_url = base_domain .. "/" .. img_url
        end
        
        -- Показываем только JPEG
        if string.find(string.lower(img_url), "%.jpg$") or 
           string.find(string.lower(img_url), "%.jpeg$") then
           
            if load_cached_image(img_url) then
                -- Пробуем отобразить с SD-карты
                local success = ui.drawJPEG_SD(10, y_offset, browser.images[img_url])
                if not success then
                    -- Пробуем из flash
                    success = ui.drawJPEG(10, y_offset, browser.images[img_url])
                end
                
                if success then
                    y_offset = y_offset + 100  -- Отступ для следующего изображения
                end
            else
                -- Показываем плейсхолдер
                ui.rect(10, y_offset, 100, 100, 2114)
                ui.text(15, y_offset + 40, "Загрузка...", 1, 65535)
                y_offset = y_offset + 110
            end
        end
    end
end

-- Отображение интерфейса браузера
function draw_browser()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, 0)
    
    -- Панель статуса
    ui.rect(0, 0, SCR_W, 40, 2114)  -- Темно-серый
    ui.text(10, 10, browser.status, 1, 65535)
    
    if browser.loading then
        ui.text(SCR_W - 80, 10, "⌛", 2, 65535)
    else
        ui.text(SCR_W - 80, 10, "✓", 2, 2016)
    end
    
    -- Поле адреса
    ui.rect(0, 45, SCR_W, 45, 2114)
    if ui.input(10, 50, SCR_W - 20, 35, browser.url, false) then
        input_mode = true
        input_text = browser.url
    end
    
    -- Кнопки навигации
    if ui.button(10, 100, 60, 35, "← Назад", 1040) and browser.history_index > 1 then
        browser.history_index = browser.history_index - 1
        browser.url = browser.history[browser.history_index]
        download_page(browser.url)
        browser.page_pos = 0
    end
    
    if ui.button(80, 100, 60, 35, "→ Вперед", 1040) and 
       browser.history_index < #browser.history then
        browser.history_index = browser.history_index + 1
        browser.url = browser.history[browser.history_index]
        download_page(browser.url)
        browser.page_pos = 0
    end
    
    if ui.button(150, 100, 80, 35, "Обновить", 2016) then
        download_page(browser.url)
        browser.page_pos = 0
    end
    
    if ui.button(240, 100, 70, 35, "Домой", 63488) then
        browser.url = "https://raw.githubusercontent.com/kptmx/luawatch/main/main.lua"
        download_page(browser.url)
        browser.page_pos = 0
    end
    
    -- Область содержимого
    ui.rect(0, 140, SCR_W, PAGE_H, 0)
    render_page()
    render_images()
    
    -- Прокрутка
    if #browser.current_page > 0 then
        local content_height = #browser.current_page / 3
        local scrollbar_height = math.max(20, PAGE_H * PAGE_H / content_height)
        local scrollbar_pos = (browser.page_pos / content_height) * (PAGE_H - scrollbar_height)
        
        ui.rect(SCR_W - 10, 140, 10, PAGE_H, 2114)  -- Дорожка
        ui.rect(SCR_W - 10, 140 + scrollbar_pos, 10, scrollbar_height, 8452)  -- Ползунок
        
        -- Кнопки прокрутки
        if ui.button(SCR_W - 60, 140, 50, scroll_btn_size, "↑", 1040) then
            browser.page_pos = math.max(0, browser.page_pos - scroll_speed)
        end
        
        if ui.button(SCR_W - 60, 140 + PAGE_H - scroll_btn_size, 50, scroll_btn_size, "↓", 1040) then
            browser.page_pos = browser.page_pos + scroll_speed
        end
    end
end

-- Отображение T9 клавиатуры для ввода
function draw_keyboard()
    -- Фон клавиатуры
    ui.rect(0, KEYBOARD_Y, SCR_W, SCR_H - KEYBOARD_Y, 2114)
    
    -- Поле ввода
    ui.rect(10, KEYBOARD_Y + 10, SCR_W - 20, 40, 0)
    
    -- Мигающий курсор
    local cursor_time = hw.millis() - cursor_timer
    if cursor_time > 1000 then
        cursor_blink = not cursor_blink
        cursor_timer = hw.millis()
    end
    
    local display_text = input_text
    if cursor_blink and cursor_time % 1000 < 500 then
        display_text = display_text .. "|"
    end
    
    ui.text(15, KEYBOARD_Y + 25, display_text, 2, 65535)
    
    -- Клавиши T9
    for i, k in ipairs(keys) do
        local r = math.floor((i - 1) / 3)
        local c = (i - 1) % 3
        
        local btn_color = 8452
        if k == "OK" then btn_color = 2016 end
        if k == "DEL" or k == "CLR" then btn_color = 63488 end
        
        if ui.button(10 + c * 130, KEYBOARD_Y + 60 + r * 45, 125, 40, k, btn_color) then
            if k == "DEL" then
                input_text = input_text:sub(1, -2)
            elseif k == "CLR" then
                input_text = ""
            elseif k == "OK" then
                if #input_text > 0 then
                    browser.url = input_text
                    if not string.find(browser.url, "https?://") then
                        browser.url = "https://" .. browser.url
                    end
                    download_page(browser.url)
                    browser.page_pos = 0
                end
                input_mode = false
            else
                handle_t9_input(k)
            end
        end
    end
    
    -- Кнопка отмены
    if ui.button(SCR_W - 100, KEYBOARD_Y - 50, 90, 40, "Отмена", 2114) then
        input_mode = false
    end
end

-- Основной цикл отрисовки
function draw()
    if input_mode then
        draw_browser()
        draw_keyboard()
    else
        draw_browser()
        
        -- Кнопка для открытия клавиатуры
        if ui.button(SCR_W - 120, 50, 110, 35, "Ввод URL", 1040) then
            input_mode = true
            input_text = browser.url
            cursor_timer = hw.millis()
        end
    end
end

-- Загрузка начальной страницы
function init_browser()
    -- Создаем папку для кэша
    if not fs.exists("/cache") then
        fs.mkdir("/cache")
    end
    
    -- Загружаем домашнюю страницу
    download_page(browser.url)
end

-- Инициализация при старте
init_browser()

-- Основной цикл (вызывается из C++)
-- function draw() уже определена выше
