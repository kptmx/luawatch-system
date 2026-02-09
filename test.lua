-- Веб-браузер на Lua с встроенными в текст ссылками
-- Без поддержки изображений

local SCR_W, SCR_H = 410, 502
local LINE_H = 28
local MAX_CHARS_PER_LINE = 30  -- Увеличим немного для лучшего отображения текста

local current_url = "https://www.furtails.pw"
local history, history_pos = {}, 0
local scroll_y = 0
local content, content_height = {}, 0

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

-- Удаление скриптов, стилей и изображений
local function remove_junk(html)
    -- Удаляем комментарии
    html = html:gsub("<!%-%-.-%-%->", "")
    
    -- Удаляем <script>...</script>
    html = html:gsub("<script[^>]*>.-</script>", "")
    html = html:gsub("<SCRIPT[^>]*>.-</SCRIPT>", "")
    
    -- Удаляем <style>...</style>
    html = html:gsub("<style[^>]*>.-</style>", "")
    html = html:gsub("<STYLE[^>]*>.-</STYLE>", "")
    
    -- Удаляем изображения полностью
    html = html:gsub("<img[^>]*>", "")
    html = html:gsub("<IMG[^>]*>", "")
    
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
local function add_content(text, is_link, link_url)
    if not text or text == "" then return end
    
    local lines = wrap_text(text)
    for _, line in ipairs(lines) do
        table.insert(content, {
            type = is_link and "link" or "text",
            text = line,
            url = link_url
        })
        content_height = content_height + LINE_H
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
    local link_text = ""
    
    while pos <= #html do
        local start_tag = html:find("<", pos)
        
        if not start_tag then
            -- Остаток текста до конца документа
            local text = html:sub(pos)
            text = clean_text(decode_html_entities(text))
            if text ~= "" then
                if in_link then
                    link_text = link_text .. text
                else
                    add_content(text, false, nil)
                end
            end
            break
        end
        
        if start_tag > pos then
            -- Текст перед тегом
            local text = html:sub(pos, start_tag - 1)
            text = clean_text(decode_html_entities(text))
            if text ~= "" then
                if in_link then
                    link_text = link_text .. text
                else
                    add_content(text, false, nil)
                end
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
                    -- Закрывающий тег ссылки
                    if link_text ~= "" and current_link then
                        add_content("[" .. link_text .. "]", true, current_link)
                    end
                    in_link = false
                    current_link = nil
                    link_text = ""
                elseif is_block then
                    -- Добавляем отступ после блочного тега
                    add_content("", false, nil)
                end
            else
                if tag_name == "a" then
                    -- Открывающий тег ссылки
                    local href = tag_raw:match('href%s*=%s*"([^"]+)"') or 
                                 tag_raw:match("href%s*=%s*'([^']+)'")
                    if href then
                        current_link = resolve_url(current_url, href)
                        if current_link then 
                            in_link = true
                            link_text = ""
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
    
    -- Если осталась незакрытая ссылка (плохой HTML)
    if in_link and link_text ~= "" and current_link then
        add_content("[" .. link_text .. "]", true, current_link)
    end
end

-- ==========================================
-- ОСНОВНЫЕ ФУНКЦИИ
-- ==========================================

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
        load_page(current_url)
    end
    if ui.button(260, 52, 130, 40, "Home", 0x4208) then 
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
            -- Встроенная ссылка - это просто цветной текст
            local display_text = item.text
            
            -- Проверяем клик по ссылке
            local text_width = #display_text * 8  -- Примерная ширина символа
            
            -- Создаем "невидимую" кнопку поверх текста ссылки
            if ui.button(15, cy - 5, text_width + 10, LINE_H, "", 0x0000) then
                load_page(item.url)
            end
            
            -- Рисуем текст ссылки синим цветом
            ui.text(20, cy, display_text, 2, 0x07FF)
            
            -- Подчеркивание для ссылок
            ui.rect(20, cy + 18, text_width, 1, 0x07FF)
            
            cy = cy + LINE_H
        end
    end

    ui.endList()
    
    -- Индикатор внизу
    ui.text(10, SCR_H - 15, "Links are blue and clickable", 1, 0x8410)
end

-- ==========================================
-- ИНИЦИАЛИЗАЦИЯ
-- ==========================================

-- Загружаем стартовую страницу
load_page(current_url)
