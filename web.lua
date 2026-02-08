-- Веб-браузер для устройства с ESP32 и Lua интерпретатором
-- Поддерживает прокрутку, текст, ссылки и изображения

local SCR_W, SCR_H = 410, 502
local page_content = ""
local page_images = {}
local scroll_y = 0
local max_scroll_y = 0
local touch_start_y = 0
local touch_start_time = 0
local velocity_y = 0
local is_scrolling = false
local current_url = "https://httpbin.org/html"
local url_input = ""
local url_input_active = false
local status_msg = "Ready"
local loading = false
local links = {}
local images = {}

-- Функция для извлечения URL из HTML тега <a>
local function extract_links(html)
    links = {}
    for url, text in html:gmatch('<a[^>]+href%=["\']([^"\']+)["\'][^>]*>([^<]*)</a>') do
        table.insert(links, {url = url, text = text:gsub("&%w+;", function(entity)
            -- Простая замена некоторых HTML сущностей
            if entity == "&amp;" then return "&"
            elseif entity == "&lt;" then return "<"
            elseif entity == "&gt;" then return ">"
            elseif entity == "&quot;" then return "\""
            else return entity
            end
        end)})
    end
    return links
end

-- Функция для извлечения URL изображений из HTML
local function extract_images(html)
    images = {}
    for url in html:gmatch('<img[^>]+src%=["\']([^"\']+)["\'][^>]*>') do
        table.insert(images, url)
    end
    return images
end

-- Функция для удаления HTML тегов, но сохранения структуры
local function strip_html(html)
    -- Замена <br> и <p> на переносы строк
    html = html:gsub("<br%s*/?>", "\n")
    html = html:gsub("<p[^>]*>", "\n")
    html = html:gsub("</p>", "\n")
    
    -- Удаление всех остальных тегов
    local text = html:gsub("<[^>]*>", "")
    
    -- Замена HTML сущностей
    text = text:gsub("&%w+;", function(entity)
        if entity == "&amp;" then return "&"
        elseif entity == "&lt;" then return "<"
        elseif entity == "&gt;" then return ">"
        elseif entity == "&quot;" then return "\""
        elseif entity == "&apos;" then return "'"
        else return entity
        end
    end)
    
    -- Удаление лишних переносов строк
    text = text:gsub("\n+", "\n")
    text = text:gsub("^\n+", "")
    
    return text
end

-- Функция для загрузки страницы
local function load_page(url)
    loading = true
    status_msg = "Loading..."
    
    -- Проверяем, является ли URL относительным
    if not url:find("http") and current_url then
        local base_url = current_url:match("^(https?://[^/]+)")
        if base_url then
            url = base_url .. (url:sub(1,1) == "/" and "" or "/") .. url
        end
    end
    
    -- Загружаем страницу
    local response = net.get(url)
    
    if response and response.ok then
        page_content = response.body
        current_url = url
        status_msg = "Loaded"
        
        -- Извлекаем ссылки и изображения
        extract_links(page_content)
        extract_images(page_content)
        
        -- Подготавливаем текст для отображения
        local text = strip_html(page_content)
        
        -- Разбиваем текст на строки для отображения
        local lines = {}
        for line in text:gmatch("[^\n]+") do
            -- Разбиваем длинные строки на более короткие
            while #line > 40 do
                table.insert(lines, line:sub(1, 40))
                line = line:sub(41)
            end
            table.insert(lines, line)
        end
        
        -- Сохраняем обработанный текст
        page_content = table.concat(lines, "\n")
        
        -- Сбрасываем прокрутку
        scroll_y = 0
        velocity_y = 0
        is_scrolling = false
        
        -- Вычисляем максимальную прокрутку
        local line_count = #lines
        max_scroll_y = math.max(0, (line_count * 20) - SCR_H + 100)
        
        -- Загружаем изображения
        page_images = {}
        for i, img_url in ipairs(images) do
            -- Проверяем, является ли URL относительным
            if not img_url:find("http") and current_url then
                local base_url = current_url:match("^(https?://[^/]+)")
                if base_url then
                    img_url = base_url .. (img_url:sub(1,1) == "/" and "" or "/") .. img_url
                end
            end
            
            -- Загружаем изображение
            local img_response = net.get(img_url)
            if img_response and img_response.ok then
                -- Сохраняем изображение на SD-карту
                local img_path = "/temp_img_" .. i .. ".jpg"
                local file = fs.open(img_path, "w")
                if file then
                    file.write(img_response.body)
                    file.close()
                    table.insert(page_images, {path = img_url, local_path = img_path, y = 0})
                end
            end
        end
        
        loading = false
        return true
    else
        status_msg = "Load failed"
        loading = false
        return false
    end
end

-- Функция для отрисовки страницы
local function draw_page()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, 0)
    
    -- Заголовок с URL
    ui.rect(0, 0, SCR_W, 40, 0x2104)
    ui.text(5, 10, url_input_active and url_input or current_url, 1, 0xFFFF)
    
    -- Статус
    ui.text(5, 25, status_msg, 1, loading and 0xF800 or 0x07E0)
    
    -- Кнопка "GO" для ввода URL
    if ui.button(SCR_W - 40, 5, 35, 30, "GO", 0x07E0) then
        if url_input_active then
            load_page(url_input)
            url_input_active = false
        else
            url_input = current_url
            url_input_active = true
        end
    end
    
    -- Область содержимого
    ui.beginList(0, 40, SCR_W, SCR_H - 80, scroll_y, max_scroll_y)
    
    -- Отображение текста страницы
    local y = 45
    local line_height = 20
    local lines = {}
    
    -- Разбиваем текст на строки
    for line in page_content:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    -- Отображаем строки
    for i, line in ipairs(lines) do
        local line_y = 45 + (i-1) * line_height - scroll_y
        
        -- Проверяем, является ли строка ссылкой
        local is_link = false
        local link_url = nil
        
        for _, link in ipairs(links) do
            if line:find(link.text, 1, true) then
                is_link = true
                link_url = link.url
                break
            end
        end
        
        -- Отображаем строку
        if is_link then
            ui.text(5, line_y, line, 1, 0x001F)
            
            -- Обработка нажатия на ссылку
            if ui.button(5, line_y - 5, SCR_W - 10, line_height, "", 0) then
                if link_url then
                    load_page(link_url)
                end
            end
        else
            ui.text(5, line_y, line, 1, 0xFFFF)
        end
    end
    
    -- Отображение изображений
    for i, img in ipairs(page_images) do
        local img_y = 100 + i * 150 - scroll_y
        if img_y > 40 and img_y < SCR_H - 40 then
            ui.drawJPEG(5, img_y, img.local_path)
        end
    end
    
    ui.endList()
    
    -- Нижняя панель управления
    ui.rect(0, SCR_H - 40, SCR_W, 40, 0x2104)
    
    -- Кнопка "Back"
    if ui.button(5, SCR_H - 35, 60, 30, "Back", 0xF800) then
        -- Простая навигация назад (можно улучшить с историей)
        load_page("https://httpbin.org/html")
    end
end
