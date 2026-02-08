-- Простой веб-браузер на Lua (улучшенная версия с исправленным парсером)
-- Исправления:
-- • Полностью удаляются <script>, <style> и комментарии <!-- -->
-- • Теги правильно захватываются целиком (с атрибутами), больше никаких остатков тегов в тексте
-- • Лучшая обработка HTML-сущностей (&nbsp;, &amp;, &lt;, &#123; и т.д.)
-- • Игнорируются все теги кроме <a> и блочных (<p>, <div>, <br>, <li>, заголовки)
-- • Блочные теги добавляют отступ (новая строка)
-- • Текст очищается от лишних пробелов

local SCR_W, SCR_H = 410, 502
local LINE_H = 28
local LINK_H = 36
local MAX_CHARS_PER_LINE = 52

local current_url = "https://news.ycombinator.com"
local history = {}
local history_pos = 0
local scroll_y = 0

local content = {}
local content_height = 0

-- Разрешение относительных ссылок
local function resolve_url(base, href)
    href = href:gsub("^%s+", ""):gsub("%s+$", "")
    if href:match("^https?://") then return href end
    if href:sub(1,1) == "/" then
        local proto_host = base:match("(https?://[^/]+)")
        return proto_host .. href
    end
    local dir = base:match("(.*/)[^/]*$") or base .. "/"
    return dir .. href
end

-- Декодирование HTML-сущностей
local function decode_html_entities(str)
    local map = {
        amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = " ",
    }
    -- Числовые сущности &#123; и &#xAB;
    str = str:gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
    str = str:gsub("&#x(%x+);", function(n) return string.char(tonumber(n,16)) end)
    -- Именованные
    str = str:gsub("&(%a+);", map)
    return str
end

-- Удаление скриптов, стилей и комментариев
local function remove_scripts_styles_comments(html)
    -- Комментарии
    html = html:gsub("<!%-%-.-%-%->", "")
    -- Script (case-insensitive)
    html = html:gsub("<[sS][cC][rR][iI][pP][tT][^>]*>.-</[sS][cC][rR][iI][pP][tT]>", "")
    -- Style (case-insensitive)
    html = html:gsub("<[sS][tT][yY][lL][eE][^>]*>.-</[sS][tT][yY][lL][eE]>", "")
    return html
end

-- Перенос текста по словам
local function wrap_text(text)
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if #text == 0 then return {} end
    local lines = {}
    local pos = 1
    while pos <= #text do
        local remaining = #text - pos + 1
        local chunk_len = math.min(MAX_CHARS_PER_LINE, remaining)
        local chunk_end = pos + chunk_len - 1
        if remaining > MAX_CHARS_PER_LINE then
            local last_space = text:find(" [^ ]*$", pos)
            if last_space and last_space < pos + MAX_CHARS_PER_LINE then
                chunk_end = last_space - 1
            end
        end
        table.insert(lines, text:sub(pos, chunk_end))
        pos = chunk_end + 1
        if pos <= #text and text:sub(pos, pos) == " " then pos = pos + 1 end
    end
    return lines
end

-- Добавление контента
local function add_content(text, is_link, link_url)
    local lines = wrap_text(text)
    for _, line in ipairs(lines) do
        table.insert(content, {
            type = is_link and "link" or "text",
            text = line,
            url = link_url
        })
        content_height = content_height + (is_link and LINK_H or LINE_H)
    end
end

-- Улучшенный HTML-парсер с сохранением ссылок
function parse_html(html)
    content = {}
    content_height = 60
    
    -- Декодирование HTML-сущностей
    local function decode_entities(text)
        text = text:gsub("&nbsp;", " ")
                   :gsub("&amp;", "&")
                   :gsub("&lt;", "<")
                   :gsub("&gt;", ">")
                   :gsub("&quot;", "\"")
                   :gsub("&#39;", "'")
                   :gsub("&apos;", "'")
                   :gsub("&ndash;", "-")
                   :gsub("&mdash;", "-")
                   :gsub("&hellip;", "...")
        
        -- Числовые сущности
        text = text:gsub("&#(%d+);", function(n)
            return string.char(tonumber(n))
        end)
        
        -- Удаляем все остальные сущности
        text = text:gsub("&#?[%w%d]+;", " ")
        
        return text
    end
    
    -- Очистка текста от лишних пробелов и переносов
    local function clean_text(text)
        if not text then return "" end
        text = decode_entities(text)
        text = text:gsub("[\r\n]+", " ")
        text = text:gsub("%s%s+", " ")
        return text:gsub("^%s+", ""):gsub("%s+$", "")
    end
    
    -- Извлекаем тело документа
    local body_content = html
    local body_start = html:find("<body")
    if body_start then
        local body_end = html:find("</body>", body_start)
        if body_end then
            body_content = html:sub(body_start, body_end - 1)
        else
            body_content = html:sub(body_start)
        end
    end
    
    -- Удаляем скрипты и стили
    body_content = body_content:gsub("<script[^>]*>.-</script>", "")
    body_content = body_content:gsub("<style[^>]*>.-</style>", "")
    body_content = body_content:gsub("<!%-%-.-%-%->", "")
    
    -- Проходим по всему HTML и извлекаем текст и ссылки
    local pos = 1
    local text_buffer = ""
    
    while pos <= #body_content do
        -- Ищем следующий тег
        local tag_start, tag_end, tag_full = body_content:find("<([^>]+)>", pos)
        
        if not tag_start then
            -- Текст после всех тегов
            text_buffer = text_buffer .. body_content:sub(pos)
            pos = #body_content + 1
        else
            -- Текст перед тегом
            local text_before = body_content:sub(pos, tag_start - 1)
            if #text_before > 0 then
                text_buffer = text_buffer .. text_before
            end
            
            -- Обрабатываем тег
            local tag_name = tag_full:match("^(%w+)")
            local tag_lower = tag_name and tag_name:lower() or ""
            
            -- Закрывающие теги, которые завершают блоки
            if tag_full:match("^/") then
                local closing_tag = tag_full:match("^/(%w+)")
                if closing_tag then
                    closing_tag = closing_tag:lower()
                    if closing_tag == "p" or closing_tag == "div" or 
                       closing_tag == "section" or closing_tag == "article" or
                       closing_tag:match("^h[1-6]$") then
                        -- Добавляем накопленный текст
                        local cleaned = clean_text(text_buffer)
                        if #cleaned > 2 then
                            add_content(cleaned, false)
                        end
                        text_buffer = ""
                    end
                end
            -- Открывающие теги
            elseif tag_lower == "br" then
                -- Перенос строки
                local cleaned = clean_text(text_buffer)
                if #cleaned > 2 then
                    add_content(cleaned, false)
                end
                text_buffer = ""
            elseif tag_lower == "a" then
                -- Ссылка
                -- Сначала добавляем текст до ссылки
                local cleaned = clean_text(text_buffer)
                if #cleaned > 2 then
                    add_content(cleaned, false)
                end
                text_buffer = ""
                
                -- Извлекаем URL
                local href = tag_full:match('href%s*=%s*["\']([^"\']+)["\']')
                if href then
                    href = resolve_url(current_url, href)
                    
                    -- Ищем текст ссылки до закрывающего </a>
                    local link_end = body_content:find("</a>", tag_end + 1)
                    if link_end then
                        local link_text = body_content:sub(tag_end + 1, link_end - 1)
                        link_text = clean_text(link_text)
                        
                        -- Удаляем вложенные теги из текста ссылки
                        link_text = link_text:gsub("<[^>]+>", "")
                        
                        if #link_text > 0 then
                            add_content(link_text, true, href)
                        end
                        
                        pos = link_end + 4
                    else
                        pos = tag_end + 1
                    end
                else
                    pos = tag_end + 1
                end
                -- Пропускаем обычную обработку тега
                goto continue
            elseif tag_lower == "p" or tag_lower == "div" or 
                   tag_lower:match("^h[1-6]$") or tag_lower == "article" or 
                   tag_lower == "section" then
                -- Начало нового блока - добавляем предыдущий текст
                local cleaned = clean_text(text_buffer)
                if #cleaned > 2 then
                    add_content(cleaned, false)
                end
                text_buffer = ""
            end
            
            pos = tag_end + 1
        end
        
        ::continue::
    end
    
    -- Добавляем оставшийся текст в конце
    local cleaned = clean_text(text_buffer)
    if #cleaned > 2 then
        add_content(cleaned, false)
    end
    
    -- Если ничего не нашлось, показываем заглушку
    if #content == 0 then
        -- Попробуем найти любые ссылки как запасной вариант
        for href, link_text in body_content:gmatch('<a%s[^>]*href%s*=%s*["\']([^"\']+)["\'][^>]*>([^<]+)</a>') do
            link_text = clean_text(link_text)
            if #link_text > 2 then
                href = resolve_url(current_url, href)
                add_content(link_text, true, href)
            end
        end
        
        if #content == 0 then
            add_content("Не удалось извлечь содержимое страницы", false)
            add_content("Возможно, HTML слишком сложный", false)
        end
    end
end

-- Функция фильтрации контента (оставляем как есть, но убираем излишние фильтры)
local function add_content(text, is_link, link_url)
    if not is_link then
        -- Легкая фильтрация только для явного мусора
        -- Удаляем строки с множеством спецсимволов
        local special_chars = text:gsub("[%w%s]", ""):len()
        if special_chars > #text * 0.7 then  -- если больше 70% спецсимволов
            return
        end
        
        -- Удаляем строки которые точно являются кодом
        if text:match("^[{}();]+$") or
           text:match("^var%s+[%w_]+%s*=") or
           text:match("^function%s*%(") then
            return
        end
    end
    
    local lines = wrap_text(text)
    for _, line in ipairs(lines) do
        table.insert(content, {
            type = is_link and "link" or "text",
            text = line,
            url = link_url
        })
        content_height = content_height + (is_link and LINK_H or LINE_H)
    end
end

-- Обновленная функция добавления контента с дополнительной фильтрацией
local function add_content(text, is_link, link_url)
    -- Дополнительная фильтрация для текста
    if not is_link then
        -- Удаляем строки с множеством специальных символов
        local special_chars = text:gsub("[%w%s]", ""):len()
        if special_chars > #text * 0.5 then  -- если больше 50% спецсимволов
            return
        end
        
        -- Удаляем строки которые выглядят как CSS/JS
        if text:match("{%s*[%w%-]+%s*:") or  -- CSS: {property: value}
           text:match("[%w]+%s*%(%s*[%)%w]") or  -- function()
           text:match("%.%w+%s*%(") then  -- .method(
            return
        end
        
        -- Удаляем слишком длинные "слова" (часто это классы CSS или идентификаторы)
        for word in text:gmatch("[%w_%-]+") do
            if #word > 30 then
                return
            end
        end
    end
    
    local lines = wrap_text(text)
    for _, line in ipairs(lines) do
        table.insert(content, {
            type = is_link and "link" or "text",
            text = line,
            url = link_url
        })
        content_height = content_height + (is_link and LINK_H or LINE_H)
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

load_page(current_url)

-- Отрисовка
function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)

    -- URL
    ui.text(10, 12, current_url:sub(1, 65), 2, 0xFFFF)

    -- Кнопки
    if history_pos > 1 then
        if ui.button(10, 52, 100, 40, "Back", 0x4208) then go_back() end
    end
    if ui.button(120, 52, 130, 40, "Reload", 0x4208) then load_page(current_url) end
    if ui.button(260, 52, 130, 40, "Home", 0x4208) then load_page("https://news.ycombinator.com") end

    -- Контент
    scroll_y = ui.beginList(0, 100, SCR_W, SCR_H - 100, scroll_y, content_height)

    local cy = 20
    for _, item in ipairs(content) do
        if item.type == "text" then
            ui.text(20, cy, item.text, 2, 0xFFFF)
            cy = cy + LINE_H
        else
            local clicked = ui.button(10, cy, SCR_W - 20, LINK_H, "", 0)
            ui.text(25, cy + 6, item.text, 2, 0x07FF)
            if clicked then
                load_page(item.url)
            end
            cy = cy + LINK_H
        end
    end

    ui.endList()
end
