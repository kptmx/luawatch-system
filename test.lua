-- WebPrimitive 0.1 - Текстовый браузер с T9 клавиатурой
-- Основан на LuaWatch Designer интерфейсе

SCR_W = 410
SCR_H = 502
currentPage = "main"
current_url = "https://google.com"
history = {}
history_pos = 0
web_content_scroll = 0
web_content = {}
web_content_height = 0
MAX_CHARS_PER_LINE = 24
LINE_H = 28
LINK_H = 36

-- T9 клавиатура
local t9_keys = {
    ["1"] = ".,!1",
    ["2"] = "abc2", 
    ["3"] = "def3",
    ["4"] = "ghi4",
    ["5"] = "jkl5",
    ["6"] = "mno6",
    ["7"] = "pqrs7",
    ["8"] = "tuv8", 
    ["9"] = "wxyz9",
    ["*"] = "*",
    ["0"] = " 0",
    ["#"] = "#"
}

local url_input_text = ""
local last_t9_key = ""
local last_t9_time = 0
local t9_char_index = 1

-- ==========================================
-- HTML парсинг (без изображений)
-- ==========================================

local BLOCK_TAGS = {
    p=true, div=true, h1=true, h2=true, h3=true, h4=true, h5=true, h6=true,
    ul=true, ol=true, li=true, br=true, blockquote=true, hr=true, tr=true
}

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

local function decode_html_entities(str)
    if not str then return "" end
    str = str:gsub("&lt;", "<")
    str = str:gsub("&gt;", ">")
    str = str:gsub("&amp;", "&")
    str = str:gsub("&quot;", '"')
    str = str:gsub("&#(%d+);", function(code)
        return string.char(tonumber(code))
    end)
    return str
end

local function clean_text(txt)
    txt = txt:gsub("[%s\r\n]+", " ")
    txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
    return txt
end

local function remove_junk(html)
    html = html:gsub("<!%-%-.-%-%->", "")
    html = html:gsub("<script[^>]*>.-</script>", "")
    html = html:gsub("<style[^>]*>.-</style>", "")
    html = html:gsub("<noscript[^>]*>.-</noscript>", "")
    html = html:gsub("<iframe[^>]*>.-</iframe>", "")
    return html
end

local function utf8_len(str)
    local _, count = string.gsub(str, "[^\128-\193]", "")
    return count
end

local function utf8_sub(str, start_char, end_char)
    local chars = {}
    for uchar in string.gmatch(str, "([%z\1-\127\194-\244][\128-\191]*)") do
        table.insert(chars, uchar)
    end
    
    local result = ""
    end_char = end_char or #chars
    for i = math.max(1, start_char), math.min(end_char, #chars) do
        result = result .. chars[i]
    end
    return result
end

local function wrap_text(text)
    local char_len = utf8_len(text)
    if char_len <= MAX_CHARS_PER_LINE then
        return {text}
    end
    
    local lines = {}
    local current_line = ""
    local current_len = 0
    
    -- Разбиваем на отдельные UTF-8 символы
    local chars = {}
    for uchar in string.gmatch(text, "([%z\1-\127\194-\244][\128-\191]*)") do
        table.insert(chars, uchar)
    end
    
    local i = 1
    while i <= #chars do
        local char = chars[i]
        
        -- Если символ пробел - обрабатываем отдельно
        if char == " " then
            if current_len + 1 <= MAX_CHARS_PER_LINE then
                current_line = current_line .. char
                current_len = current_len + 1
            else
                table.insert(lines, current_line)
                current_line = ""
                current_len = 0
                -- Не увеличиваем i, чтобы пробел попал в новую строку
            end
            i = i + 1
        else
            -- Получаем слово
            local word = ""
            local word_len = 0
            while i <= #chars and chars[i] ~= " " do
                word = word .. chars[i]
                word_len = word_len + 1
                i = i + 1
            end
            
            if word_len == 0 then
                i = i + 1
                goto continue
            end
            
            -- Если слово слишком длинное для одной строки
            if word_len > MAX_CHARS_PER_LINE then
                if current_len > 0 then
                    table.insert(lines, current_line)
                    current_line = ""
                    current_len = 0
                end
                
                -- Разбиваем слишком длинное слово
                local j = 1
                while j <= word_len do
                    local part = ""
                    local part_len = 0
                    while j <= word_len and part_len < MAX_CHARS_PER_LINE do
                        part = part .. chars[j]
                        part_len = part_len + 1
                        j = j + 1
                    end
                    table.insert(lines, part)
                end
            else
                -- Обычное слово
                if current_len == 0 then
                    current_line = word
                    current_len = word_len
                elseif current_len + 1 + word_len <= MAX_CHARS_PER_LINE then
                    current_line = current_line .. " " .. word
                    current_len = current_len + 1 + word_len
                else
                    table.insert(lines, current_line)
                    current_line = word
                    current_len = word_len
                end
            end
        end
        
        ::continue::
    end
    
    if current_len > 0 then
        table.insert(lines, current_line)
    end
    
    return lines
end

local function add_content(text, is_link, link_url)
    if not text or text == "" then return end
    
    local lines = wrap_text(text)
    for _, line in ipairs(lines) do
        table.insert(web_content, {
            type = is_link and "link" or "text",
            text = line,
            url = link_url
        })
        web_content_height = web_content_height + (is_link and LINK_H or LINE_H)
    end
end

local function parse_html(html)
    web_content = {}
    web_content_height = 0
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
                elseif tag_name == "br" then
                    add_content("", false, nil)
                elseif is_block then
                    add_content("", false, nil)
                end
            end
        end
        
        pos = end_tag + 1
    end
    
    -- Минимальная высота для скролла
    if web_content_height < SCR_H - 100 then
        web_content_height = SCR_H - 100
    end
end

-- ==========================================
-- Загрузка страниц
-- ==========================================

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
        web_content_scroll = 0
    else
        web_content = {}
        web_content_height = SCR_H - 100
        add_content("Ошибка загрузки", false)
        add_content("URL: " .. new_url, false)
        add_content("Код: " .. tostring(res.code or "—"), false)
        add_content("Ошибка: " .. tostring(res.err or "нет ответа"), false)
    end
end

function go_back()
    if history_pos > 1 then
        history_pos = history_pos - 1
        load_page(history[history_pos])
    end
end

-- ==========================================
-- T9 логика
-- ==========================================

function handle_t9_key(key)
    local now = hw.millis()
    local chars = t9_keys[key]
    if not chars then return end
    
    -- Если нажата та же клавиша в течение 800мс — меняем символ
    if key == last_t9_key and (now - last_t9_time) < 800 then
        url_input_text = url_input_text:sub(1, -2)
        t9_char_index = (t9_char_index % #chars) + 1
    else
        t9_char_index = 1
    end
    
    url_input_text = url_input_text .. chars:sub(t9_char_index, t9_char_index)
    last_t9_key = key
    last_t9_time = now
end

-- ==========================================
-- Вспомогательные функции для рисования контента
-- ==========================================

function draw_web_content()
    -- Устанавливаем скролл только для контентной области
    local visible_height = SCR_H - 140
    web_content_scroll = ui.beginList(0, 35, SCR_W, visible_height, web_content_scroll, web_content_height)
    
    local cy = 0
    for idx, item in ipairs(web_content) do
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
            if clicked then
                load_page(item.url)
            end
            cy = cy + LINK_H
        end
    end
    
    ui.endList()
end

function draw_interface()
    -- URL строка (кликабельная)
    local display_url = current_url
    if #display_url > 30 then
        display_url = display_url:sub(1, 27) .. "..."
    end
    
    if ui.button(0, 410, SCR_W, 30, display_url, 14823) then
        url_input_text = current_url
        currentPage = "urlenter"
    end
    
    -- Панель управления
    if ui.button(60, 445, 90, 40, "back", 10665) then
        go_back()
    end
    
    if ui.button(155, 445, 80, 40, "reld", 10665) then
        load_page(current_url)
    end
    
    if ui.button(240, 445, 115, 40, "menu", 14792) then
        currentPage = "quickmenu"
    end
    
    -- Статус
    ui.text(110, 485, "Ready", 1, 65535)
    
    -- Батарея и время
    ui.text(240, 0, hw.getBatt() .. "%", 2, 65535)
    
    local time = hw.getTime()
    ui.text(90, 0, string.format("%02d:%02d", time.h, time.m), 2, 65535)
end

function draw_quickmenu()
    -- Добавить в закладки
    if ui.button(20, 100, 180, 60, "add to bm", 10665) then
        -- Сохранить URL в файл закладок
        local bookmarks = fs.load("/bookmarks.txt") or ""
        if not bookmarks:find(current_url) then
            fs.append("/bookmarks.txt", current_url .. "\n")
        end
        currentPage = "main"
    end
    
    -- Показать закладки
    if ui.button(210, 100, 180, 60, "bookmarks", 10665) then
        -- Здесь можно реализовать просмотр закладок
        currentPage = "main"
    end
    
    -- История
    if ui.button(20, 170, 180, 60, "history", 10665) then
        -- Здесь можно реализовать просмотр истории
        currentPage = "main"
    end
    
    -- Очистить историю
    if ui.button(210, 170, 180, 60, "clrhistory", 10665) then
        history = {}
        history_pos = 0
        currentPage = "main"
    end
    
    -- Выход
    if ui.button(30, 405, 140, 45, "exit", 59783) then
        currentPage = "main"
    end
    
    -- Статус PSRAM
    ui.text(25, 245, "free psram: " .. hw.getFreePsram(), 1, 65535)
    
    -- Текущий URL
    ui.text(25, 275, current_url, 1, 65535)
    
    -- Информация
    ui.text(125, 470, "webprimitive 0.1", 1, 65535)
    
    -- Назад
    if ui.button(255, 405, 120, 45, "back", 10665) then
        currentPage = "main"
    end
end

function draw_urlenter()
    -- Отображение вводимого URL
    local display_text = url_input_text
    if #display_text > 40 then
        display_text = "..." .. display_text:sub(-37)
    end
    ui.text(15, 70, display_text, 2, 65535)
    
    -- T9 клавиатура
    local keys = {
        {"1", "2", "3"},
        {"4", "5", "6"},
        {"7", "8", "9"},
        {"*", "0", "#"}
    }
    
    for row = 1, 4 do
        for col = 1, 3 do
            local key = keys[row][col]
            local x = 15 + (col-1)*130
            local y = 175 + (row-1)*65
            
            if ui.button(x, y, 120, 55, key, 10665) then
                handle_t9_key(key)
            end
            
            -- Показываем символы под клавишей
            if t9_keys[key] then
                ui.text(x + 5, y + 35, t9_keys[key]:sub(1, 3), 1, 0xFFFF)
            end
        end
    end
    
    -- Специальные кнопки
    if ui.button(15, 435, 70, 60, "DEL", 0xF800) then
        url_input_text = url_input_text:sub(1, -2)
        last_t9_key = ""
    end
    
    if ui.button(95, 435, 105, 60, "cancel", 10665) then
        currentPage = "main"
    end
    
    if ui.button(210, 435, 110, 60, "go", 0x07E0) then
        if #url_input_text > 0 then
            load_page(url_input_text)
            currentPage = "main"
        end
    end
    
    if ui.button(330, 435, 70, 60, "CLR", 0xFD20) then
        url_input_text = ""
        last_t9_key = ""
    end
end

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0) -- Чёрный фон
    
    if currentPage == "main" then
        -- Рисуем контент страницы (со скроллом)
        draw_web_content()
        -- Рисуем интерфейс поверх (без скролла)
        draw_interface()
        
    elseif currentPage == "quickmenu" then
        draw_quickmenu()
        
    elseif currentPage == "urlenter" then
        draw_urlenter()
    end
end

-- ==========================================
-- Инициализация
-- ==========================================

-- Загружаем стартовую страницу
load_page(current_url)
