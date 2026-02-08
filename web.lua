-- Простой веб-браузер на Lua с ленивой загрузкой изображений по клику
-- Полная версия с парсингом HTML

local SCR_W, SCR_H = 410, 502
local LINE_H = 28
local LINK_H = 36
local IMAGE_H = 120
local MAX_CHARS_PER_LINE = 24

local current_url = "https://furaffinity.net"
local history, history_pos = {}, 0
local scroll_y = 0
local content, content_height = {}, 0

-- Кэш изображений
local image_cache = {}
local currently_downloading = nil  -- URL текущей загрузки

-- ==========================================
-- ПАРСИНГ HTML
-- ==========================================

local BLOCK_TAGS = {
    p=true, div=true, h1=true, h2=true, h3=true, h4=true, h5=true, h6=true,
    ul=true, ol=true, li=true, br=true, blockquote=true, hr=true, tr=true
}

-- Разрешение относительных ссылок
local function resolve_url(base, href)
    if not href then return base end
    href = href:gsub("^%s+", ""):gsub("%s+$", "")
    
    if href:sub(1,2) == "//" then return "https:" .. href end
    if href:match("^https?://") then return href end
    if href:match("^mailto:") or href:match("^javascript:") then return nil end
    
    local proto, domain = base:match("^(https?://)([^/]+)")
    if not proto then return href end
    
    if href:sub(1,1) == "/" then
        return proto .. domain .. href
    end
    
    local path = base:match("^https?://[^/]+(.*/)") or "/"
    return proto .. domain .. path .. href
end

-- Декодирование HTML-сущностей (упрощенное)
local function decode_html_entities(str)
    if not str then return "" end
    str = str:gsub("&lt;", "<")
    str = str:gsub("&gt;", ">")
    str = str:gsub("&amp;", "&")
    str = str:gsub("&quot;", '"')
    str = str:gsub("&#(%d+);", function(code)
        return string.char(tonumber(code))
    end)
    str = str:gsub("&#x(%x+);", function(code)
        return string.char(tonumber(code, 16))
    end)
    return str
end

-- Очистка текста
local function clean_text(txt)
    txt = txt:gsub("[%s\r\n]+", " ")
    txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
    return txt
end

-- Удаление скриптов и стилей
local function remove_junk(html)
    -- Удаляем комментарии
    html = html:gsub("<!%-%-.-%-%->", "")
    
    -- Удаляем <script>...</script>
    html = html:gsub("<script[^>]*>.-</script>", "")
    html = html:gsub("<SCRIPT[^>]*>.-</SCRIPT>", "")
    
    -- Удаляем <style>...</style>
    html = html:gsub("<style[^>]*>.-</style>", "")
    html = html:gsub("<STYLE[^>]*>.-</STYLE>", "")
    
    -- Удаляем другие ненужные теги
    html = html:gsub("<noscript[^>]*>.-</noscript>", "")
    html = html:gsub("<iframe[^>]*>.-</iframe>", "")
    html = html:gsub("<svg[^>]*>.-</svg>", "")
    
    return html
end

-- Обертка текста
local function wrap_text(text)
    if #text <= MAX_CHARS_PER_LINE then
        return {text}
    end
    
    local lines = {}
    local current = ""
    local words = {}
    
    -- Разбиваем на слова
    for word in text:gmatch("%S+") do
        table.insert(words, word)
    end
    
    for i, word in ipairs(words) do
        if #current + #word + 1 <= MAX_CHARS_PER_LINE or #current == 0 then
            if #current > 0 then
                current = current .. " " .. word
            else
                current = word
            end
        else
            table.insert(lines, current)
            current = word
        end
    end
    
    if #current > 0 then
        table.insert(lines, current)
    end
    
    return lines
end

-- Добавление контента
local function add_content(text, is_link, link_url, is_image, image_url)
    if not text or text == "" then return end
    
    local lines = wrap_text(text)
    for _, line in ipairs(lines) do
        table.insert(content, {
            type = is_image and "image" or (is_link and "link" or "text"),
            text = line,
            url = link_url,
            image_url = image_url,
            alt_text = text
        })
        if is_image then
            content_height = content_height + IMAGE_H + 10
        else
            content_height = content_height + (is_link and LINK_H or LINE_H)
        end
    end
end

-- Парсинг HTML
local function parse_html(html)
    content = {}
    content_height = 60
    
    html = remove_junk(html)

    local pos = 1
    local in_link = false
    local current_link = nil
    
    while pos <= #html do
        local start_tag = html:find("<", pos)
        
        if not start_tag then
            local text = html:sub(pos)
            text = clean_text(decode_html_entities(text))
            if text ~= "" then
                add_content(text, in_link, current_link)
            end
            break
        end
        
        if start_tag > pos then
            local text = html:sub(pos, start_tag - 1)
            text = clean_text(decode_html_entities(text))
            if text ~= "" then
                add_content(text, in_link, current_link)
            end
        end
        
        local end_tag = html:find(">", start_tag)
        if not end_tag then break end
        
        local tag_raw = html:sub(start_tag + 1, end_tag - 1)
        local is_closing, tag_name = tag_raw:match("^(/?)([%w%-]+)")
        
        if tag_name then
            tag_name = tag_name:lower()
            local is_block = BLOCK_TAGS[tag_name]
            
            if is_closing == "/" then
                if tag_name == "a" then
                    in_link = false
                    current_link = nil
                elseif is_block then
                    -- Добавляем отступ после блочного тега
                    add_content("", false, nil)
                end
            else
                if tag_name == "a" then
                    local href = tag_raw:match('href%s*=%s*"([^"]+)"') or 
                                 tag_raw:match("href%s*=%s*'([^']+)'")
                    if href then
                        current_link = resolve_url(current_url, href)
                        if current_link then in_link = true end
                    end
                elseif tag_name == "img" then
                    local src = tag_raw:match('src%s*=%s*"([^"]+)"') or 
                               tag_raw:match("src%s*=%s*'([^']+)'") or
                               tag_raw:match('src%s*=%s*([^%s>]+)')
                    
                    local alt = tag_raw:match('alt%s*=%s*"([^"]+)"') or 
                               tag_raw:match("alt%s*=%s*'([^']+)'") or
                               "[Image]"
                    
                    if src then
                        local img_url = resolve_url(current_url, src)
                        if img_url then
                            add_content("[IMG: " .. alt .. "]", false, nil, true, img_url)
                        end
                    end
                elseif tag_name == "br" then
                    add_content("", false, nil)
                elseif is_block then
                    add_content("", false, nil)
                end
            end
        end
        
        pos = end_tag + 1
    end
end

-- ==========================================
-- ЗАГРУЗКА ИЗОБРАЖЕНИЙ
-- ==========================================

-- Проверяем, поддерживается ли формат изображения
local function is_supported_image(url)
    if not url then return false end
    return url:match("%.jpg$") or url:match("%.jpeg$") or 
           url:match("%.JPG$") or url:match("%.JPEG$")
end

-- Коллбэк для обновления прогресса
local function download_progress_callback(loaded, total)
    if not currently_downloading then return true end
    
    local cache_entry = image_cache[currently_downloading]
    if not cache_entry then return true end
    
    cache_entry.loaded_bytes = loaded
    cache_entry.total_bytes = total
    cache_entry.progress = total > 0 and math.floor((loaded / total) * 100) or 0
    
    -- Сразу обновляем экран!
    draw()
    ui.flush()
    
    return true
end

-- Загрузка изображения
local function load_image_to_cache(img_url)
    if not img_url or currently_downloading then return false end
    
    if not is_supported_image(img_url) then
        image_cache[img_url] = {
            loaded = false,
            failed = true,
            error = "Unsupported format"
        }
        return false
    end
    
    if image_cache[img_url] and image_cache[img_url].loaded then
        return true
    end
    
    local filename = "img_" .. os.time() .. "_" .. math.random(1000, 9999)
    if img_url:match("%.png$") or img_url:match("%.PNG$") then
        filename = filename .. ".png"
    else
        filename = filename .. ".jpg"
    end
    
    local cache_path = "/cache/" .. filename
    
    image_cache[img_url] = {
        loaded = false,
        loading = true,
        failed = false,
        path = cache_path,
        progress = 0,
        loaded_bytes = 0,
        total_bytes = 0
    }
    
    currently_downloading = img_url
    
    print("Starting download: " .. img_url)
    
    local success = net.download(img_url, cache_path, "flash", download_progress_callback)
    
    if success then
        image_cache[img_url].loaded = true
        image_cache[img_url].loading = false
        image_cache[img_url].progress = 100
        print("Download completed!")
    else
        image_cache[img_url].failed = true
        image_cache[img_url].loading = false
        image_cache[img_url].error = "Download failed"
        print("Download failed")
        
        if fs.exists(cache_path) then
            fs.remove(cache_path)
        end
    end
    
    currently_downloading = nil
    
    draw()
    ui.flush()
    
    return success
end

-- ==========================================
-- УТИЛИТЫ ДЛЯ ОТРИСОВКИ
-- ==========================================

local function draw_progress_bar(x, y, width, height, progress, color, bg_color)
    ui.rect(x, y, width, height, bg_color or 0x4208)
    
    local fill_width = math.max(2, math.floor(width * progress / 100))
    if fill_width > 0 then
        ui.rect(x, y, fill_width, height, color or 0x07E0)
    end
    
    local percent_text = tostring(math.floor(progress)) .. "%"
    ui.text(x + width/2 - 10, y + height/2 - 4, percent_text, 1, 0xFFFF)
end

-- ==========================================
-- ОСНОВНЫЕ ФУНКЦИИ
-- ==========================================

-- Загрузка страницы
function load_page(new_url)
    if not new_url:match("^https?://") then
        new_url = "https://" .. new_url
    end
    
    -- Очищаем только кэш изображений, не останавливаем текущую загрузку
    if not currently_downloading then
        for url, cache in pairs(image_cache) do
            if cache.path and fs.exists(cache.path) then
                fs.remove(cache.path)
            end
        end
        image_cache = {}
    end
    
    local res = net.get(new_url)
    if res.ok and res.code == 200 then
        current_url = new_url
        table.insert(history, current_url)
        history_pos = #history
        parse_html(res.body)
        scroll_y = 0
        draw()
        ui.flush()
    else
        content = {}
        content_height = 200
        add_content("Ошибка загрузки", false)
        add_content("URL: " .. new_url, false)
        add_content("Код: " .. tostring(res.code or "—"), false)
        add_content("Ошибка: " .. tostring(res.err or "нет ответа"), false)
        draw()
        ui.flush()
    end
end

-- Назад
local function go_back()
    if history_pos > 1 then
        history_pos = history_pos - 1
        load_page(history[history_pos])
    end
end

-- ==========================================
-- ОТРИСОВКА
-- ==========================================

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)

    -- URL строка
    local display_url = current_url
    if #display_url > 50 then
        display_url = display_url:sub(1, 47) .. "..."
    end
    ui.text(10, 12, display_url, 2, 0xFFFF)

    -- Панель управления
    if history_pos > 1 then
        if ui.button(10, 52, 100, 40, "Back", 0x4208) then 
            go_back()
        end
    end
    if ui.button(120, 52, 130, 40, "Reload", 0x4208) then 
        if not currently_downloading then
            for url, cache in pairs(image_cache) do
                if cache.path and fs.exists(cache.path) then
                    fs.remove(cache.path)
                end
            end
            image_cache = {}
        end
        load_page(current_url)
    end
    if ui.button(260, 52, 130, 40, "Home", 0x4208) then 
        if not currently_downloading then
            for url, cache in pairs(image_cache) do
                if cache.path and fs.exists(cache.path) then
                    fs.remove(cache.path)
                end
            end
            image_cache = {}
        end
        load_page("https://www.furtails.pw")
    end

    -- Контент
    scroll_y = ui.beginList(0, 100, SCR_W, SCR_H - 100, scroll_y, content_height)

    local cy = 20
    for idx, item in ipairs(content) do
        if item.type == "text" then
            if item.text ~= "" then
                ui.text(20, cy, item.text, 2, 0xFFFF)
                cy = cy + LINE_H
            else
                cy = cy + LINE_H / 2
            end
        elseif item.type == "link" then
            local clicked = ui.button(10, cy, SCR_W - 20, LINK_H, "", 0x0101)
            ui.text(25, cy + 6, item.text, 2, 0x07FF)
            if clicked and not currently_downloading then
                load_page(item.url)
            end
            cy = cy + LINK_H
        elseif item.type == "image" then
            local img_url = item.image_url
            local cache_entry = img_url and image_cache[img_url]
            local is_supported = is_supported_image(img_url)
            local clicked = ui.button(10, cy, SCR_W - 20, IMAGE_H, "", 0x0101)
            
            -- Цвет фона
            local bg_color = 0x2104
            
            if is_supported then
                if cache_entry then
                    if cache_entry.loaded then
                        bg_color = 0x0520  -- Загружено
                    elseif cache_entry.loading then
                        bg_color = 0xFD20  -- Загружается
                    elseif cache_entry.failed then
                        bg_color = 0xF800  -- Ошибка
                    else
                        bg_color = 0x001F  -- Можно загрузить
                    end
                else
                    bg_color = 0x001F  -- Не загружалось
                end
            else
                bg_color = 0x4A69  -- Неподдерживаемый
            end
            
            -- Фон блока
            ui.rect(10, cy, SCR_W - 20, IMAGE_H, bg_color)
            
            -- Текст
            ui.text(20, cy + 10, item.text, 1, 0xFFFF)
            
            -- Состояние
            if cache_entry then
                if cache_entry.loading then
                    -- Прогресс загрузки
                    local progress = cache_entry.progress or 0
                    local loaded_kb = math.floor((cache_entry.loaded_bytes or 0) / 1024)
                    local total_kb = math.floor((cache_entry.total_bytes or 0) / 1024)
                    
                    ui.rect(20, cy + 40, SCR_W - 40, 30, 0x0000)
                    draw_progress_bar(30, cy + 45, SCR_W - 60, 20, progress)
                    
                    if total_kb > 0 then
                        ui.text(SCR_W/2 - 40, cy + 70, 
                               loaded_kb .. "/" .. total_kb .. " KB", 1, 0xFFFF)
                    end
                elseif cache_entry.loaded then
                    -- Показываем изображение
                    if cache_entry.path and fs.exists(cache_entry.path) then
                        local success = ui.drawJPEG(15, cy + 5, cache_entry.path)
                        if not success then
                            ui.text(20, cy + 60, "Display error", 1, 0xF800)
                        end
                    end
                elseif cache_entry.failed then
                    ui.text(20, cy + 60, "Load failed", 1, 0xF800)
                    if cache_entry.error then
                        ui.text(20, cy + 80, cache_entry.error, 1, 0xF800)
                    end
                end
            elseif is_supported then
                ui.text(20, cy + 60, "Click to load", 1, 0x07FF)
            else
                ui.text(20, cy + 60, "Format not supported", 1, 0xF800)
            end
            
            -- Кнопка для загрузки
            if clicked and is_supported and img_url and not currently_downloading then
                if not cache_entry or (not cache_entry.loading and not cache_entry.loaded) then
                    load_image_to_cache(img_url)
                end
            end
            
            cy = cy + IMAGE_H + 10
        end
    end

    ui.endList()
    
    -- Индикатор загрузки в углу
    if currently_downloading then
        ui.rect(SCR_W - 60, SCR_H - 40, 50, 30, 0x0000)
        ui.text(SCR_W - 55, SCR_H - 35, "LOADING", 1, 0x07E0)
        
        local progress = image_cache[currently_downloading] and 
                        image_cache[currently_downloading].progress or 0
        ui.rect(SCR_W - 55, SCR_H - 20, 40, 8, 0x4208)
        if progress > 0 then
            local fill_width = math.floor(40 * progress / 100)
            ui.rect(SCR_W - 55, SCR_H - 20, fill_width, 8, 0x07E0)
        end
    end
end

-- ==========================================
-- ИНИЦИАЛИЗАЦИЯ
-- ==========================================

-- Создаем папку для кэша
if not fs.exists("/cache") then
    fs.mkdir("/cache")
end

-- Загружаем стартовую страницу
load_page(current_url)
