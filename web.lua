-- Простой веб-браузер на Lua (улучшенная версия с поддержкой JPEG)
-- Исправления:
-- • Полностью удаляются <script>, <style> и комментарии <!-- -->
-- • Теги правильно захватываются целиком (с атрибутами), больше никаких остатков тегов в тексте
-- • Лучшая обработка HTML-сущностей (&nbsp;, &amp;, &lt;, &#123; и т.д.)
-- • Игнорируются все теги кроме <a> и блочных (<p>, <div>, <br>, <li>, заголовки)
-- • Блочные теги добавляют отступ (новая строка)
-- • Текст очищается от лишних пробелов
-- • Добавлена поддержка JPEG изображений через теги <img>

local SCR_W, SCR_H = 410, 502
local LINE_H = 28
local LINK_H = 36
local IMAGE_H = 120  -- Стандартная высота для изображений
local MAX_CHARS_PER_LINE = 24

local current_url = "https://furaffinity.net"
local history = {}
local history_pos = 0
local scroll_y = 0

local content = {}
local content_height = 0

-- Кэш изображений (URL -> {loaded: bool, path: string})
local image_cache = {}

-- Разрешение относительных ссылок
-- ==========================================
-- ИНСТРУМЕНТЫ ПАРСИНГА
-- ==========================================

-- Список тегов, которые вызывают перенос строки
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
    if not proto then return href end -- fallback
    
    if href:sub(1,1) == "/" then
        return proto .. domain .. href
    end
    
    local path = base:match("^https?://[^/]+(.*/)") or "/"
    return proto .. domain .. path .. href
end

-- Вспомогательная функция для конвертации Unicode-кода в UTF-8 строку
local function utf8_from_code(code)
    code = math.floor(code)
    if code < 128 then
        return string.char(code)
    elseif code < 2048 then
        -- 2 байта
        return string.char(192 + math.floor(code/64), 128 + (code % 64))
    elseif code < 65536 then
        -- 3 байта (базовая многоязычная плоскость, включая кириллицу)
        return string.char(224 + math.floor(code/4096), 128 + math.floor((code/64)%64), 128 + (code%64))
    elseif code < 1114112 then
        -- 4 байта (эмодзи и редкие символы)
        return string.char(240 + math.floor(code/262144), 128 + math.floor((code/4096)%64), 128 + math.floor((code/64)%64), 128 + (code%64))
    end
    return "?" -- Если код некорректен
end

-- Исправленная функция декодирования
local function decode_html_entities(str)
    if not str then return "" end
    local map = {
        amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = " ",
        copy = "©", reg = "®", trade = "™", mdash = "—", ndash = "–",
        laquo = "«", raquo = "»"
    }
    
    return str:gsub("&(#?x?)(%w+);", function(type, val)
        if type == "" then 
            -- Если сущность именованная (&amp;), берем из таблицы
            -- Если нет в таблице, возвращаем как было, чтобы не терять текст
            return map[val] or ("&" .. val .. ";")
        end
        
        local code
        if type == "#" then 
            code = tonumber(val) 
        elseif type == "#x" then 
            code = tonumber(val, 16) 
        end
        
        if code then
            return utf8_from_code(code)
        end
    end)
end

-- Очистка текста от мусора
local function clean_text(txt)
    -- Заменяем любые пробельные символы (табы, переносы) на пробел
    txt = txt:gsub("[%s\r\n]+", " ")
    return txt
end

-- Полное удаление скриптов и стилей
local function remove_junk(html)
    -- Удаляем комментарии
    local out = {}
    local i = 1
    while i <= #html do
        local start_c = html:find("<!%-%-", i)
        if not start_c then
            table.insert(out, html:sub(i))
            break
        end
        table.insert(out, html:sub(i, start_c - 1))
        local end_c = html:find("%-%->", start_c + 4)
        if not end_c then break end -- не закрыт комментарий
        i = end_c + 3
    end
    html = table.concat(out)

    -- Удаляем <script>...</script> и <style>...</style>
    local function strip_tag_content(text, tagname)
        local res = {}
        local pos = 1
        while true do
            -- Ищем начало <tag
            local s_tag, e_tag = text:find("<" .. tagname, pos) -- упрощенный поиск
            if not s_tag then
                table.insert(res, text:sub(pos))
                break
            end
            
            -- Сохраняем то, что было ДО тега
            table.insert(res, text:sub(pos, s_tag - 1))
            
            -- Ищем конец </tag>
            local end_s, end_e = text:find("</" .. tagname .. ">", e_tag)
            if not end_s then
                -- Если закрывающего нет, обрезаем все до конца
                break 
            end
            pos = end_e + 1
        end
        return table.concat(res)
    end

    html = strip_tag_content(html, "script")
    html = strip_tag_content(html, "style")
    html = strip_tag_content(html, "SCRIPT") -- на всякий случай
    
    return html
end

-- ==========================================
-- ПОДДЕРЖКА КИРИЛЛИЦЫ (UTF-8)
-- ==========================================

-- Функция для подсчета реального количества символов (а не байт)
local function utf8_len(str)
    local _, count = string.gsub(str, "[^\128-\191]", "")
    return count
end

-- Функция для получения подстроки с учетом UTF-8 (аналог string.sub)
local function utf8_sub(str, i, j)
    local start_byte = 1
    local end_byte = #str
    local char_idx = 0
    
    local byte_idx = 1
    while byte_idx <= #str do
        char_idx = char_idx + 1
        
        if char_idx == i then start_byte = byte_idx end
        
        -- Определяем размер текущего символа
        local b = string.byte(str, byte_idx)
        local char_len = 1
        if b >= 240 then char_len = 4
        elseif b >= 224 then char_len = 3
        elseif b >= 192 then char_len = 2
        end
        
        if char_idx == j then 
            end_byte = byte_idx + char_len - 1 
            break 
        end
        
        byte_idx = byte_idx + char_len
    end
    
    return string.sub(str, start_byte, end_byte)
end

-- Умный перенос текста (Word Wrap) с поддержкой русского языка
local function wrap_text(text)
    if utf8_len(text) <= MAX_CHARS_PER_LINE then
        return {text}
    end

    local lines = {}
    local current_line = ""
    local current_len = 0 -- длина в символах

    -- Разбиваем текст на слова (по пробелам)
    for word in text:gmatch("%S+") do
        local word_len = utf8_len(word)
        
        -- Если слово само по себе длиннее всей строки, придется его резать
        if word_len > MAX_CHARS_PER_LINE then
            -- Если в буфере что-то было, сбрасываем
            if current_len > 0 then
                table.insert(lines, current_line)
                current_line = ""
                current_len = 0
            end
            table.insert(lines, word) -- Тут можно добавить жесткую резку, но пока оставим так
        
        -- Если слово влезает в текущую строку
        elseif current_len + word_len + (current_len > 0 and 1 or 0) <= MAX_CHARS_PER_LINE then
            if current_len > 0 then
                current_line = current_line .. " " .. word
                current_len = current_len + 1 + word_len
            else
                current_line = word
                current_len = word_len
            end
        else
            -- Слово не влезает, отправляем текущую строку в архив и начинаем новую
            table.insert(lines, current_line)
            current_line = word
            current_len = word_len
        end
    end
    
    -- Добавляем остаток
    if current_len > 0 then
        table.insert(lines, current_line)
    end
    
    return lines
end

-- Добавление контента (обновленная версия с поддержкой изображений)
function add_content(text, is_link, link_url, is_image)
    if not text or text == "" then return end
    
    local lines = wrap_text(text)
    for _, line in ipairs(lines) do
        table.insert(content, {
            type = is_image and "image" or (is_link and "link" or "text"),
            text = line,
            url = link_url,
            alt_text = text  -- Для изображений сохраняем alt текст
        })
        if is_image then
            content_height = content_height + IMAGE_H + 10  -- +10 для отступа
        else
            content_height = content_height + (is_link and LINK_H or LINE_H)
        end
    end
end

-- Добавление новой строки (отступа)
local function add_newline()
    -- Добавляем пустой отступ только если предыдущий элемент не был отступом
    if #content > 0 and content[#content].text ~= "" then
         table.insert(content, { type = "text", text = "", url = nil })
         content_height = content_height + (LINE_H / 2)
    end
end

-- Загрузка изображения в кэш
local function load_image_to_cache(img_url)
    if image_cache[img_url] then
        return image_cache[img_url].loaded
    end
    
    -- Инициализируем запись в кэше
    image_cache[img_url] = {
        loaded = false,
        path = "/cache/" .. tostring(#image_cache + 1) .. ".jpg",
        loading = false
    }
    
    -- Начинаем асинхронную загрузку
    local cache_entry = image_cache[img_url]
    cache_entry.loading = true
    
    -- Функция для загрузки изображения
    local function download_image()
        local result = net.download(img_url, cache_entry.path, "flash")
        cache_entry.loading = false
        if result then
            cache_entry.loaded = true
            print("Image loaded: " .. img_url)
        else
            print("Failed to load image: " .. img_url)
        end
    end
    
    -- Запускаем загрузку (в идеале в отдельном потоке, но в Lua просто вызовем)
    -- В реальности нужно использовать корутины или отложенную загрузку
    download_image()
    
    return false  -- Пока не загружено
end

-- ==========================================
-- ОСНОВНОЙ ПАРСЕР С ПОДДЕРЖКОЙ ИЗОБРАЖЕНИЙ
-- ==========================================

function parse_html(html)
    content = {}
    content_height = 60
    image_cache = {}  -- Очищаем кэш изображений при новой странице
    
    html = remove_junk(html)

    local pos = 1
    local in_link = false
    local current_link = nil
    
    while pos <= #html do
        -- 1. Ищем начало следующего тега "<"
        local start_tag = html:find("<", pos)
        
        if not start_tag then
            -- Тегов больше нет, добавляем остаток текста
            local text = html:sub(pos)
            text = clean_text(decode_html_entities(text))
            add_content(text, in_link, current_link)
            break
        end
        
        -- 2. Обрабатываем ТЕКСТ до тега
        if start_tag > pos then
            local text = html:sub(pos, start_tag - 1)
            text = clean_text(decode_html_entities(text))
            add_content(text, in_link, current_link)
        end
        
        -- 3. Разбираем сам ТЕГ
        -- Ищем закрывающую ">"
        local end_tag = html:find(">", start_tag)
        if not end_tag then break end -- Обрыв HTML
        
        local tag_raw = html:sub(start_tag + 1, end_tag - 1)
        
        -- Определяем имя тега
        local is_closing, tag_name = tag_raw:match("^(/?)([%w%-]+)")
        
        if tag_name then
            tag_name = tag_name:lower()
            local is_block = BLOCK_TAGS[tag_name]
            
            if is_closing == "/" then
                -- Закрывающий тег (</a>, </div>)
                if tag_name == "a" then
                    in_link = false
                    current_link = nil
                elseif is_block then
                    add_newline()
                end
            else
                -- Открывающий тег
                if tag_name == "a" then
                    -- Ищем href. Поддержка " и '
                    local href = tag_raw:match('href%s*=%s*"([^"]+)"') or 
                                 tag_raw:match("href%s*=%s*'([^']+)'")
                    
                    if href then
                        current_link = resolve_url(current_url, href)
                        if current_link then in_link = true end
                    end
                elseif tag_name == "img" then
                    -- Обработка тега изображения
                    local src = tag_raw:match('src%s*=%s*"([^"]+)"') or 
                               tag_raw:match("src%s*=%s*'([^']+)'") or
                               tag_raw:match('src%s*=%s*([^%s>]+)')
                    
                    local alt = tag_raw:match('alt%s*=%s*"([^"]+)"') or 
                               tag_raw:match("alt%s*=%s*'([^']+)'") or
                               "[Image]"
                    
                    if src then
                        local img_url = resolve_url(current_url, src)
                        if img_url then
                            -- Проверяем, это JPEG или другое изображение
                            if img_url:match("%.jpg$") or img_url:match("%.jpeg$") or 
                               img_url:match("%.JPG$") or img_url:match("%.JPEG$") then
                                -- Добавляем элемент изображения
                                add_content(alt, false, img_url, true)
                                -- Начинаем загрузку в кэш
                                load_image_to_cache(img_url)
                            else
                                -- Для не-JPEG изображений показываем только alt текст
                                add_content("[Image: " .. alt .. "]", false, img_url)
                            end
                        end
                    end
                elseif tag_name == "br" then
                    add_newline()
                elseif is_block then
                    add_newline()
                end
            end
        end
        
        pos = end_tag + 1
    end
end

-- Загрузка страницы
function load_page(new_url)
    if not new_url:match("^https?://") then
        new_url = "https://" .. new_url
    end
    local res = net.get(new_url)
    if res.ok and res.code == 200 then
        current_url = new_url
        table.insert(history, current_url)
        history_pos = #history
        parse_html(res.body)
        scroll_y = 0
    else
        content = {}
        content_height = 200
        add_content("Ошибка загрузки", false)
        add_content("URL: " .. new_url, false)
        add_content("Код: " .. tostring(res.code or "—"), false)
        add_content("Ошибка: " .. tostring(res.err or "нет ответа"), false)
    end
end

-- Назад
local function go_back()
    if history_pos > 1 then
        history_pos = history_pos - 1
        load_page(history[history_pos])
    end
end

-- Очистка кэша изображений при перезагрузке
local function clear_image_cache()
    for _, cache_entry in pairs(image_cache) do
        if cache_entry.path then
            fs.remove(cache_entry.path)
        end
    end
    image_cache = {}
end

-- Отрисовка с поддержкой изображений
function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)

    -- URL
    local display_url = current_url
    if utf8_len(display_url) > 50 then
        display_url = utf8_sub(display_url, 1, 47) .. "..."
    end
    ui.text(10, 12, display_url, 2, 0xFFFF)

    -- Кнопки
    if history_pos > 1 then
        if ui.button(10, 52, 100, 40, "Back", 0x4208) then go_back() end
    end
    if ui.button(120, 52, 130, 40, "Reload", 0x4208) then 
        clear_image_cache()
        load_page(current_url) 
    end
    if ui.button(260, 52, 130, 40, "Home", 0x4208) then 
        clear_image_cache()
        load_page("https://www.furtails.pw") 
    end

    -- Контент
    scroll_y = ui.beginList(0, 100, SCR_W, SCR_H - 100, scroll_y, content_height)

    local cy = 20
    for _, item in ipairs(content) do
        if item.type == "text" then
            if item.text ~= "" then
                ui.text(20, cy, item.text, 2, 0xFFFF)
                cy = cy + LINE_H
            else
                cy = cy + LINE_H / 2  -- Пустой отступ
            end
        elseif item.type == "link" then
            local clicked = ui.button(10, cy, SCR_W - 20, LINK_H, "", 0x0101)
            ui.text(25, cy + 6, item.text, 2, 0x07FF)
            if clicked then
                clear_image_cache()
                load_page(item.url)
            end
            cy = cy + LINK_H
        elseif item.type == "image" then
            -- Фон для изображения
            ui.rect(10, cy, SCR_W - 20, IMAGE_H, 0x2104)
            
            -- Проверяем, загружено ли изображение
            local cache_entry = image_cache[item.url]
            if cache_entry and cache_entry.loaded then
                -- Показываем JPEG изображение
                local success = ui.drawJPEG(15, cy + 5, cache_entry.path)
                if not success then
                    -- Если не удалось отобразить, показываем placeholder
                    ui.text(20, cy + 50, "[Image: " .. item.text .. "]", 1, 0xFFFF)
                end
            elseif cache_entry and cache_entry.loading then
                -- Показываем индикатор загрузки
                ui.text(20, cy + 50, "Loading image...", 1, 0x07E0)
            else
                -- Показываем alt текст
                ui.text(20, cy + 50, "[Image: " .. item.text .. "]", 1, 0xFFFF)
            end
            
            -- Делаем изображение кликабельным (для просмотра или загрузки)
            if ui.button(10, cy, SCR_W - 20, IMAGE_H, "", 0x0101) then
                -- При клике на изображение можно открыть его в полный размер
                -- или начать принудительную загрузку
                if cache_entry and not cache_entry.loaded and not cache_entry.loading then
                    load_image_to_cache(item.url)
                end
            end
            
            cy = cy + IMAGE_H + 10  -- +10 для отступа после изображения
        end
    end

    ui.endList()
    
    -- Информация о кэше
    local loaded_count = 0
    for _, cache_entry in pairs(image_cache) do
        if cache_entry.loaded then loaded_count = loaded_count + 1 end
    end
    if loaded_count > 0 then
        ui.text(SCR_W - 100, SCR_H - 20, "Images: " .. loaded_count, 1, 0x07E0)
    end
end

-- Инициализация при запуске
-- Создаем папку для кэша, если её нет
if not fs.exists("/cache") then
    fs.mkdir("/cache")
end

-- Загружаем стартовую страницу
load_page(current_url)
