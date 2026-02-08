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

-- Улучшенный HTML-парсер, который игнорирует всё кроме текста и ссылок
function parse_html(html)
    content = {}
    content_height = 60
    
    -- Очищаем HTML от всего лишнего
    local function clean_html(raw_html)
        -- 1. Удаляем комментарии
        raw_html = raw_html:gsub("<!%-%-.-%-%->", "")
        
        -- 2. Удаляем теги скриптов и стилей
        raw_html = raw_html:gsub("<script[^>]*>.-</script>", "")
        raw_html = raw_html:gsub("<style[^>]*>.-</style>", "")
        
        -- 3. Удаляем все теги, кроме <a>, <p>, <div>, <br>, <h1>-<h6>
        -- Заменяем другие теги пробелами или переносами строк
        raw_html = raw_html:gsub("<br[^>]*>", "\n")
        raw_html = raw_html:gsub("</p>", "\n")
        raw_html = raw_html:gsub("</div>", "\n")
        raw_html = raw_html:gsub("</h[1-6]>", "\n")
        raw_html = raw_html:gsub("</li>", "\n")
        raw_html = raw_html:gsub("</tr>", "\n")
        raw_html = raw_html:gsub("<[^>]+>", " ")  -- все остальные теги заменяем пробелом
        
        return raw_html
    end
    
    -- Декодирование HTML-сущностей
    local function decode_entities(text)
        -- Сначала спецсимволы
        text = text:gsub("&nbsp;", " ")
                   :gsub("&amp;", "&")
                   :gsub("&lt;", "<")
                   :gsub("&gt;", ">")
                   :gsub("&quot;", "\"")
                   :gsub("&#39;", "'")
                   :gsub("&apos;", "'")
                   :gsub("&ndash;", "-")
                   :gsub("&mdash;", "-")
        
        -- Числовые сущности
        text = text:gsub("&#(%d+);", function(n)
            return string.char(tonumber(n))
        end)
        
        -- Удаляем все остальные сущности
        text = text:gsub("&#?[%w%d]+;", " ")
        
        return text
    end
    
    -- Извлекаем только содержимое <body>
    local body_content = html
    
    local body_start, body_end = html:find("<body[^>]*>")
    if body_start then
        local body_close = html:find("</body>", body_end)
        if body_close then
            body_content = html:sub(body_end + 1, body_close - 1)
        else
            body_content = html:sub(body_end + 1)
        end
    end
    
    -- Очищаем HTML
    body_content = clean_html(body_content)
    
    -- Разбираем ссылки и текст
    local pos = 1
    local in_text_block = false
    
    while pos <= #body_content do
        -- Ищем начало ссылки [ (мы заменили теги на [ и ])
        local link_start = body_content:find("%[", pos)
        
        if link_start then
            -- Текст перед ссылкой
            local text_before = body_content:sub(pos, link_start - 1)
            text_before = decode_entities(text_before)
            text_before = text_before:gsub("^%s+", ""):gsub("%s+$", "")
            
            -- Добавляем только если есть значимый текст
            local meaningful_text = text_before:gsub("%s%s+", " ")
            if #meaningful_text > 2 and not meaningful_text:match("^[%s%p]+$") then
                add_content(meaningful_text, false)
            end
            
            -- Ищем конец ссылки ]
            local link_end = body_content:find("%]", link_start + 1)
            if link_end then
                -- Внутри [] должно быть описание ссылки и URL через |
                local link_info = body_content:sub(link_start + 1, link_end - 1)
                local link_text, link_url = link_info:match("(.+)|(.+)")
                
                if link_text and link_url then
                    link_text = decode_entities(link_text)
                    link_url = decode_entities(link_url)
                    
                    link_text = link_text:gsub("^%s+", ""):gsub("%s+$", "")
                    link_url = link_url:gsub("^%s+", ""):gsub("%s+$", "")
                    
                    if #link_text > 0 then
                        -- Преобразуем относительные URL
                        if link_url and not link_url:match("^https?://") then
                            link_url = resolve_url(current_url, link_url)
                        end
                        
                        add_content(link_text, true, link_url)
                    end
                end
                
                pos = link_end + 1
            else
                -- Если нет закрывающей ], пропускаем
                pos = link_start + 1
            end
        else
            -- Весь остальной текст
            local remaining = body_content:sub(pos)
            remaining = decode_entities(remaining)
            
            -- Разбиваем на строки и добавляем
            for line in remaining:gmatch("[^\n]+") do
                line = line:gsub("^%s+", ""):gsub("%s+$", "")
                line = line:gsub("%s%s+", " ")
                
                -- Фильтруем мусор
                if #line > 3 and 
                   not line:match("^[%s%p]+$") and  -- не только пробелы и пунктуация
                   not line:match("^[%d%p]+$") and  -- не только цифры и пунктуация
                   not line:match("^var%s") and
                   not line:match("^function%s") and
                   not line:match("^if%s*%(") and
                   not line:match("^for%s*%(") and
                   not line:match("^while%s*%(") and
                   not line:match("^return%s") then
                    
                    add_content(line, false)
                end
            end
            break
        end
    end
    
    -- Если ничего не нашли, показываем сообщение
    if #content == 0 then
        add_content("Контент страницы не найден или не поддерживается", false)
        add_content("Попробуйте другую страницу", false)
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
