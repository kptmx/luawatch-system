-- Простой веб-браузер на Lua с поддержкой JPEG и прогресс-баром загрузки
-- Исправления:
-- • Добавлен прогресс-бар загрузки изображений
-- • Callback в net.download для отслеживания прогресса
-- • UI обновляется во время загрузки
-- • Показывается количество загруженных/всего изображений

local SCR_W, SCR_H = 410, 502
local LINE_H = 28
local LINK_H = 36
local IMAGE_H = 120  -- Стандартная высота для изображений
local MAX_CHARS_PER_LINE = 24

local current_url = "https://www.furtails.pw"
local history = {}
local history_pos = 0
local scroll_y = 0

local content = {}
local content_height = 0

-- Состояние загрузки изображений
local image_loading = {
    total = 0,          -- Всего изображений на странице
    loaded = 0,         -- Успешно загружено
    failed = 0,         -- Не удалось загрузить
    current_url = nil,  -- Текущее загружаемое изображение
    current_progress = 0, -- Прогресс текущей загрузки (0-100)
    current_total = 0   -- Общий размер текущего файла
}

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

-- Callback функция для отслеживания прогресса загрузки
local function download_progress_callback(loaded, total)
    -- Обновляем прогресс текущей загрузки
    image_loading.current_progress = loaded
    image_loading.current_total = total

    draw()
    ui.flush()
    -- Принудительно вызываем перерисовку UI
    -- В реальной системе это должно быть через механизм событий
    -- Но здесь мы просто запомним состояние, а draw() проверит его
end

-- Загрузка изображения в кэш с callback
local function load_image_to_cache(img_url, img_index)
    if image_cache[img_url] then
        return image_cache[img_url].loaded
    end
    
    -- Инициализируем запись в кэше
    local cache_path = "/cache/img_" .. tostring(img_index) .. ".jpg"
    image_cache[img_url] = {
        loaded = false,
        path = cache_path,
        loading = true,
        index = img_index
    }
    
    -- Обновляем состояние загрузки
    image_loading.current_url = img_url
    image_loading.current_progress = 0
    image_loading.current_total = 0
    
    print("Starting download: " .. img_url .. " -> " .. cache_path)
    
    -- Запускаем загрузку с callback
    local success = net.download(img_url, cache_path, "flash", download_progress_callback)
    
    -- Обрабатываем результат
    image_cache[img_url].loading = false
    
    if success then
        image_cache[img_url].loaded = true
        image_loading.loaded = imacache_entryge_loading.loaded + 1
        print("Download completed: " .. img_url)
    else
        image_cache[img_url].failed = true
        image_loading.failed = image_loading.failed + 1
        print("Download failed: " .. img_url)
        
        -- Удаляем пустой файл если он создался
        if fs.exists(cache_path) then
            fs.remove(cache_path)
        end
    end
    
    -- Сбрасываем текущую загрузку
    image_loading.current_url = nil
    image_loading.current_progress = 0
    image_loading.current_total = 0
    
    return success
end

-- Функция для последовательной загрузки всех изображений
local function start_image_downloads()
    local image_urls = {}
    
    -- Собираем все URL изображений из контента
    for _, item in ipairs(content) do
        if item.type == "image" and item.url and not image_cache[item.url] then
            table.insert(image_urls, item.url)
        end
    end
    
    -- Инициализируем состояние загрузки
    image_loading.total = #image_urls
    image_loading.loaded = 0
    image_loading.failed = 0
    
    -- Если нет изображений, сразу выходим
    if image_loading.total == 0 then
        return
    end
    
    print("Found " .. image_loading.total .. " images to download")
    
    -- Запускаем загрузку первого изображения
    if #image_urls > 0 then
        local first_url = image_urls[1]
        load_image_to_cache(first_url, 1)
    end
end

-- Функция для проверки и продолжения загрузки следующих изображений
local function continue_image_downloads()
    -- Если ничего не загружается сейчас
    if not image_loading.current_url then
        -- Ищем следующее незагруженное изображение
        local next_index = image_loading.loaded + image_loading.failed + 1
        
        if next_index <= image_loading.total then
            -- Нужно найти URL по индексу
            local image_count = 0
            for _, item in ipairs(content) do
                if item.type == "image" and item.url then
                    image_count = image_count + 1
                    if image_count == next_index then
                        load_image_to_cache(item.url, next_index)
                        break
                    end
                end
            end
        end
    end
end

-- ==========================================
-- ОСНОВНОЙ ПАРСЕР С ПОДДЕРЖКОЙ ИЗОБРАЖЕНИЙ
-- ==========================================

function parse_html(html)
    content = {}
    content_height = 60
    
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
    
    -- Сбрасываем состояние загрузки
    image_loading.total = 0
    image_loading.loaded = 0
    image_loading.failed = 0
    image_loading.current_url = nil
    image_loading.current_progress = 0
    image_loading.current_total = 0
    
    -- Очищаем кэш изображений
    clear_image_cache()
    
    local res = net.get(new_url)
    if res.ok and res.code == 200 then
        current_url = new_url
        table.insert(history, current_url)
        history_pos = #history
        parse_html(res.body)
        scroll_y = 0
        
        -- Запускаем загрузку изображений после парсинга
        start_image_downloads()
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

-- Очистка кэша изображений
local function clear_image_cache()
    for url, cache_entry in pairs(image_cache) do
        if cache_entry.path and fs.exists(cache_entry.path) then
            fs.remove(cache_entry.path)
        end
    end
    image_cache = {}
end

-- Функция для отрисовки прогресс-бара
local function draw_progress_bar(x, y, width, height, progress, color)
    ui.rect(x, y, width, height, 0x4208)  -- Фон
    local fill_width = math.floor(width * progress / 100)
    if fill_width > 0 then
        ui.rect(x, y, fill_width, height, color)
    end
end

-- Отрисовка с поддержкой изображений и прогресс-баром
function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)

    -- URL
    local display_url = current_url
    if utf8_len(display_url) > 50 then
        display_url = utf8_sub(display_url, 1, 47) .. "..."
    end
    ui.text(10, 12, display_url, 2, 0xFFFF)

    -- Проверяем, нужно ли загружать следующее изображение
    continue_image_downloads()
    
    -- Статус загрузки изображений (если есть)
    local status_y = 52
    if image_loading.total > 0 then
        -- Фон для статуса
        ui.rect(0, status_y, SCR_W, 50, 0x2104)
        
        -- Информация о загрузке
        local status_text = string.format("Images: %d/%d", 
            image_loading.loaded, image_loading.total)
        
        if image_loading.failed > 0 then
            status_text = status_text .. string.format(" (%d failed)", image_loading.failed)
        end
        
        ui.text(10, status_y + 5, status_text, 1, 0xFFFF)
        
        -- Прогресс-бар общего прогресса
        local total_progress = 0
        if image_loading.total > 0 then
            total_progress = ((image_loading.loaded + image_loading.failed) / image_loading.total) * 100
        end
        draw_progress_bar(10, status_y + 25, SCR_W - 20, 8, total_progress, 0x07E0)
        
        -- Если идет загрузка конкретного изображения
        if image_loading.current_url then
            local current_progress = 0
            if image_loading.current_total > 0 then
                current_progress = (image_loading.current_progress / image_loading.current_total) * 100
            end
            
            -- Имя текущего файла
            local filename = image_loading.current_url:match("/([^/]+)$") or image_loading.current_url
            if utf8_len(filename) > 40 then
                filename = utf8_sub(filename, 1, 37) .. "..."
            end
            
            ui.text(10, status_y + 35, filename, 1, 0x07FF)
            draw_progress_bar(10, status_y + 45, SCR_W - 20, 6, current_progress, 0x07FF)
            
            -- Процент
            local percent_text = string.format("%d%%", math.floor(current_progress))
            ui.text(SCR_W - 40, status_y + 35, percent_text, 1, 0x07E0)
        end
        
        status_y = status_y + 60  -- Сдвигаем кнопки ниже
    end

    -- Кнопки (сдвигаем вниз если есть статус загрузки)
    local button_y = status_y
    
    if history_pos > 1 then
        if ui.button(10, button_y, 100, 40, "Back", 0x4208) then go_back() end
    end
    if ui.button(120, button_y, 130, 40, "Reload", 0x4208) then 
        clear_image_cache()
        load_page(current_url) 
    end
    if ui.button(260, button_y, 130, 40, "Home", 0x4208) then 
        clear_image_cache()
        load_page("https://www.furtails.pw") 
    end

    -- Контент (сдвигаем ниже кнопок и статуса)
    local content_start_y = button_y + 50
    scroll_y = ui.beginList(0, content_start_y, SCR_W, SCR_H - content_start_y, scroll_y, content_height)

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
                ui.text(20, cy + 30, "Loading...", 2, 0x07E0)
                
                -- Прогресс-бар для этого конкретного изображения
                if item.url == image_loading.current_url then
                    local progress = 0
                    if image_loading.current_total > 0 then
                        progress = (image_loading.current_progress / image_loading.current_total) * 100
                    end
                    draw_progress_bar(50, cy + 60, SCR_W - 100, 6, progress, 0x07E0)
                end
            else
                -- Показываем alt текст
                ui.text(20, cy + 50, "[Image: " .. item.text .. "]", 1, 0xFFFF)
            end
            
            -- Делаем изображение кликабельным (для принудительной перезагрузки)
            if ui.button(10, cy, SCR_W - 20, IMAGE_H, "", 0x0101) then
                -- При клике удаляем из кэша и начинаем загрузку заново
                if cache_entry then
                    if cache_entry.path and fs.exists(cache_entry.path) then
                        fs.remove(cache_entry.path)
                    end
                    image_cache[item.url] = nil
                    image_loading.loaded = math.max(0, image_loading.loaded - 1)
                end
                
                -- Начинаем загрузку этого изображения
                load_image_to_cache(item.url, image_loading.loaded + image_loading.failed + 1)
            end
            
            cy = cy + IMAGE_H + 10  -- +10 для отступа после изображения
        end
    end

    ui.endList()
    
    -- Индикатор в углу экрана
    if image_loading.total > 0 then
        local indicator_text = string.format("%d/%d", image_loading.loaded, image_loading.total)
        ui.text(SCR_W - 70, SCR_H - 20, indicator_text, 1, 0x07E0)
        
        -- Красный индикатор если есть ошибки
        if image_loading.failed > 0 then
            ui.text(SCR_W - 30, SCR_H - 20, "!", 2, 0xF800)
        end
    end
end

-- Инициализация при запуске
-- Создаем папку для кэша, если её нет
if not fs.exists("/cache") then
    fs.mkdir("/cache")
end

-- Загружаем стартовую страницу
load_page(current_url)
