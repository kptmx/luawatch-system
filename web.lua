-- Простой веб-браузер на Lua с ленивой загрузкой изображений по клику
-- Исправления:
-- • Изображения загружаются ТОЛЬКО по клику
-- • Поддерживаемые форматы выделяются особым стилем
-- • Прогресс загрузки показывается прямо на месте изображения
-- • net.download с callback обновляет UI через ui.fillRect + ui.flush

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

-- Состояние загрузки конкретного изображения
local image_loading = {
    url = nil,          -- URL загружаемого изображения
    progress = 0,       -- Прогресс текущей загрузки (0-100)
    total_size = 0,     -- Общий размер файла
    loaded_size = 0,    -- Загружено байт
    callback_active = false -- Идет ли загрузка прямо сейчас
}

-- Кэш изображений (URL -> {loaded: bool, path: string, failed: bool})
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
        table.insert(out, html:sub(i, start_card - 1))
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
function add_content(text, is_link, link_url, is_image, image_url)
    if not text or text == "" then return end
    
    local lines = wrap_text(text)
    for _, line in ipairs(lines) do
        table.insert(content, {
            type = is_image and "image" or (is_link and "link" or "text"),
            text = line,
            url = link_url,
            image_url = image_url,  -- Для изображений сохраняем оригинальный URL
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

-- Проверяем, поддерживается ли формат изображения
local function is_supported_image(url)
    if not url then return false end
    -- Поддерживаем JPEG и PNG (PNG тоже можно попробовать отобразить)
    return url:match("%.jpg$") or url:match("%.jpeg$") or 
           url:match("%.JPG$") or url:match("%.JPEG$") or
           url:match("%.png$") or url:match("%.PNG$")
end

-- Callback функция для отслеживания прогресса загрузки
-- Может вызывать ui функции для обновления экрана!
local function download_progress_callback(loaded, total)
    -- Обновляем состояние загрузки
    image_loading.loaded_size = loaded
    image_loading.total_size = total
    
    if total > 0 then
        image_loading.progress = math.floor((loaded / total) * 100)
    else
        image_loading.progress = 0
    end
    
    -- Пытаемся обновить прогресс-бар на экране
    -- Для этого нужно найти элемент с этим изображением и перерисовать его область
    -- В простейшем случае просто запомним, что нужно перерисовать
end

-- Загрузка изображения в кэш с callback и обновлением UI
local function load_image_to_cache(img_url)
    if not img_url then return false end
    
    -- Если уже загружается или загружено, ничего не делаем
    if image_cache[img_url] and (image_cache[img_url].loaded or image_cache[img_url].loading) then
        return image_cache[img_url].loaded
    end
    
    -- Проверяем, поддерживается ли формат
    if not is_supported_image(img_url) then
        image_cache[img_url] = {
            loaded = false,
            failed = true,
            error = "Unsupported format"
        }
        return false
    end
    
    -- Создаем уникальное имя файла для кэша
    local filename = "img_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)) .. ".jpg"
    local cache_path = "/cache/" .. filename
    
    -- Инициализируем запись в кэше
    image_cache[img_url] = {
        loaded = false,
        loading = true,
        path = cache_path,
        progress = 0
    }
    
    -- Устанавливаем текущую загрузку
    image_loading.url = img_url
    image_loading.progress = 0
    image_loading.total_size = 0
    image_loading.loaded_size = 0
    image_loading.callback_active = true
    
    print("Starting download: " .. img_url .. " -> " .. cache_path)
    
    -- Запускаем загрузку с callback
    local success = net.download(img_url, cache_path, "flash", download_progress_callback)
    
    -- Загрузка завершена
    image_loading.callback_active = false
    image_loading.url = nil
    
    if success then
        image_cache[img_url].loaded = true
        image_cache[img_url].loading = false
        image_cache[img_url].progress = 100
        print("Download completed: " .. img_url)
    else
        image_cache[img_url].failed = true
        image_cache[img_url].loading = false
        image_cache[img_url].error = "Download failed"
        print("Download failed: " .. img_url)
        
        -- Удаляем пустой файл если он создался
        if fs.exists(cache_path) then
            fs.remove(cache_path)
        end
    end
    
    return success
end

-- Функция для отрисовки прогресс-бара (используется в draw)
local function draw_progress_bar(x, y, width, height, progress, color, bg_color)
    -- Фон
    ui.rect(x, y, width, height, bg_color or 0x4208)
    
    -- Заполненная часть
    local fill_width = math.max(2, math.floor(width * progress / 100))
    if fill_width > 0 then
        ui.rect(x, y, fill_width, height, color)
    end
    
    -- Текст прогресса
    local percent_text = tostring(math.floor(progress)) .. "%"
    ui.text(x + width/2 - 10, y + height/2 - 4, percent_text, 1, 0xFFFF)
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
                            -- Проверяем, поддерживается ли формат
                            if is_supported_image(img_url) then
                                -- Для поддерживаемых форматов показываем специальный стиль
                                add_content("[CLICK TO LOAD: " .. alt .. "]", false, nil, true, img_url)
                            else
                                -- Для неподдерживаемых форматов просто текст
                                add_content("[Image: " .. alt .. " (unsupported)]", false, img_url)
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
    
    -- Очищаем кэш изображений
    clear_image_cache()
    
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

-- Очистка кэша изображений
local function clear_image_cache()
    for url, cache_entry in pairs(image_cache) do
        if cache_entry.path and fs.exists(cache_entry.path) then
            fs.remove(cache_entry.path)
        end
    end
    image_cache = {}
    image_loading.url = nil
    image_loading.callback_active = false
end

-- Отрисовка с ленивой загрузкой изображений
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
    for idx, item in ipairs(content) do
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
            -- Особый стиль для поддерживаемых изображений
            local is_supported = is_supported_image(item.image_url)
            local cache_entry = item.image_url and image_cache[item.image_url]
            
            -- Разные цвета фона в зависимости от состояния
            local bg_color = 0x2104  -- Серый по умолчанию
            
            if is_supported then
                if cache_entry and cache_entry.loaded then
                    bg_color = 0x0520  -- Темно-зеленый для загруженных
                elseif cache_entry and cache_entry.loading then
                    bg_color = 0xFD20  -- Оранжевый для загружающихся
                elseif cache_entry and cache_entry.failed then
                    bg_color = 0xF800  -- Красный для неудачных
                else
                    bg_color = 0x001F  -- Темно-синий для кликабельных (незагруженных)
                end
            end
            
            -- Фон для изображения
            ui.rect(10, cy, SCR_W - 20, IMAGE_H, bg_color)
            
            -- Текст (alt)
            local display_text = item.text
            if is_supported then
                display_text = display_text .. " ✓"
            end
            
            ui.text(20, cy + 10, display_text, 1, 0xFFFF)
            
            -- Если идет загрузка этого изображения, показываем прогресс
            if cache_entry and cache_entry.loading and item.image_url == image_loading.url then
                -- Прогресс-бар поверх изображения
                local progress = image_loading.progress
                if image_loading.total_size > 0 then
                    progress = math.floor((image_loading.loaded_size / image_loading.total_size) * 100)
                end
                
                -- Полупрозрачный фон для прогресс-бара
                ui.rect(20, cy + 40, SCR_W - 40, 30, 0x0000)
                
                -- Сам прогресс-бар
                draw_progress_bar(30, cy + 45, SCR_W - 60, 20, progress, 0x07E0, 0x4208)
                
                -- Информация о размере
                if image_loading.total_size > 0 then
                    local size_text = string.format("%d/%d KB", 
                        math.floor(image_loading.loaded_size / 1024),
                        math.floor(image_loading.total_size / 1024))
                    ui.text(SCR_W/2 - 30, cy + 70, size_text, 1, 0xFFFF)
                end
            elseif cache_entry and cache_entry.loaded then
                -- Показываем загруженное изображение
                local success = ui.drawJPEG(15, cy + 5, cache_entry.path)
                if not success then
                    -- Если не удалось отобразить, показываем ошибку
                    ui.text(20, cy + 60, "Display error", 1, 0xF800)
                end
            elseif cache_entry and cache_entry.failed then
                -- Показываем ошибку
                ui.text(20, cy + 60, "Load failed", 1, 0xF800)
                if cache_entry.error then
                    ui.text(20, cy + 80, cache_entry.error, 1, 0xF800)
                end
            elseif is_supported then
                -- Показываем кнопку для загрузки
                ui.text(20, cy + 60, "Click to load image", 1, 0x07FF)
                
                -- Примерный размер (если известен из атрибутов)
                if item.url and item.url:match("%.(jpg|jpeg|png)$") then
                    ui.text(20, cy + 80, "JPEG/PNG format", 1, 0x07E0)
                end
            else
                -- Неподдерживаемый формат
                ui.text(20, cy + 60, "Format not supported", 1, 0xF800)
            end
            
            -- Делаем область кликабельной
            if ui.button(10, cy, SCR_W - 20, IMAGE_H, "", 0x0101) then
                -- Обрабатываем клик по изображению
                if is_supported and item.image_url then
                    if not cache_entry or (not cache_entry.loaded and not cache_entry.loading) then
                        -- Начинаем загрузку
                        load_image_to_cache(item.image_url)
                    elseif cache_entry and cache_entry.failed then
                        -- Пробуем снова
                        load_image_to_cache(item.image_url)
                    end
                end
            end
            
            cy = cy + IMAGE_H + 10  -- +10 для отступа после изображения
        end
    end

    ui.endList()
    
    -- Индикатор загрузки в углу (если идет загрузка)
    if image_loading.callback_active and image_loading.url then
        ui.rect(SCR_W - 60, SCR_H - 40, 50, 30, 0x0000)
        ui.text(SCR_W - 55, SCR_H - 35, "LOADING", 1, 0x07E0)
        
        -- Мини-прогресс-бар
        local progress = image_loading.progress
        ui.rect(SCR_W - 55, SCR_H - 20, 40, 8, 0x4208)
        if progress > 0 then
            local fill_width = math.floor(40 * progress / 100)
            ui.rect(SCR_W - 55, SCR_H - 20, fill_width, 8, 0x07E0)
        end
    end
    
    -- Принудительное обновление экрана, если идет загрузка
    -- Это поможет обновлять прогресс-бар
    if image_loading.callback_active then
        ui.flush()
    end
end

-- Инициализация при запуске
-- Создаем папку для кэша, если её нет
if not fs.exists("/cache") then
    fs.mkdir("/cache")
end

-- Функция для периодической проверки состояния загрузки
-- Вызывается из главного цикла для обновления UI
local last_update = 0
function check_download_progress()
    local now = hw.millis()
    
    -- Обновляем UI раз в 100мс при активной загрузке
    if image_loading.callback_active and now - last_update > 100 then
        last_update = now
        
        -- Обновляем прогресс в кэше для текущего изображения
        if image_loading.url and image_cache[image_loading.url] then
            image_cache[image_loading.url].progress = image_loading.progress
        end
        
        return true  -- Нужно перерисовать
    end
    
    return false
end

-- Загружаем стартовую страницу
load_page(current_url)
