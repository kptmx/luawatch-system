-- Простой веб-браузер с парсером HTML и поддержкой T9 ввода
-- Основан на интерфейсе LuaWatch Designer

currentPage = "main"
local content = {}
local content_height = 0
local scroll_y = 0
local current_url = "https://www.google.com"
local history = {}
local history_pos = 0

-- Настройки парсера
local MAX_CHARS_PER_LINE = 45
local LINE_H = 22
local LINK_H = 36

-- T9 клавиатура
local t9_mode = "url" -- url, search
local t9_text = ""
local t9_target = 1 -- текущий символ для выбора
local t9_last_key = ""
local t9_last_time = 0
local t9_keys = {
    {"1", ".,!?"},
    {"2", "abc"},
    {"3", "def"},
    {"4", "ghi"},
    {"5", "jkl"},
    {"6", "mno"},
    {"7", "pqrs"},
    {"8", "tuv"},
    {"9", "wxyz"},
    {"*", "-_=/"},
    {"0", " "},
    {"#", "#@%&"}
}

-- Парсинг HTML
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
    if not txt then return "" end
    txt = txt:gsub("[%s\r\n]+", " ")
    txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
    return txt
end

local function wrap_text(text)
    if #text <= MAX_CHARS_PER_LINE then
        return {text}
    end
    
    local lines = {}
    local current = ""
    
    for word in text:gmatch("%S+") do
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

local function add_content(text, is_link, link_url)
    if not text or text == "" then return end
    
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

local function parse_html(html)
    content = {}
    content_height = 0
    
    -- Удаляем скрипты и стили
    html = html:gsub("<script[^>]*>.-</script>", "")
    html = html:gsub("<style[^>]*>.-</style>", "")
    html = html:gsub("<noscript[^>]*>.-</noscript>", "")
    
    local pos = 1
    local in_link = false
    local current_link = nil
    local link_text = ""
    
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
        local tag_name = tag_raw:match("^/?([%w%-]+)")
        
        if tag_name then
            tag_name = tag_name:lower()
            
            if tag_raw:sub(1, 1) == "/" then -- Закрывающий тег
                if tag_name == "a" then
                    in_link = false
                    current_link = nil
                elseif tag_name == "p" or tag_name == "div" or tag_name == "br" then
                    add_content("", false, nil)
                end
            else -- Открывающий тег
                if tag_name == "a" then
                    local href = tag_raw:match('href%s*=%s*"([^"]+)"') or 
                                 tag_raw:match("href%s*=%s*'([^']+)'") or
                                 tag_raw:match('href%s*=%s*([^%s>]+)')
                    if href then
                        if not href:match("^https?://") then
                            if href:sub(1, 1) == "/" then
                                local domain = current_url:match("^https?://([^/]+)")
                                if domain then
                                    href = "https://" .. domain .. href
                                end
                            else
                                href = current_url .. (current_url:sub(-1) == "/" and "" or "/") .. href
                            end
                        end
                        current_link = href
                        in_link = true
                    end
                elseif tag_name == "p" or tag_name == "div" or tag_name == "br" then
                    add_content("", false, nil)
                end
            end
        end
        
        pos = end_tag + 1
    end
end

-- Загрузка страницы
local function load_page(url)
    if not url:match("^https?://") then
        url = "https://" .. url
    end
    
    current_url = url
    table.insert(history, url)
    history_pos = #history
    
    local res = net.get(url)
    if res and res.ok then
        parse_html(res.body)
        scroll_y = 0
    else
        content = {}
        add_content("Error loading page", false)
        add_content("URL: " .. url, false)
        if res then
            add_content("Code: " .. tostring(res.code), false)
        end
    end
end

-- T9 обработка
local function handle_t9_key(key)
    local now = os.time()
    
    if key == "DEL" then
        t9_text = t9_text:sub(1, -2)
        t9_target = 1
        t9_last_key = ""
        return
    elseif key == "CLR" then
        t9_text = ""
        t9_target = 1
        t9_last_key = ""
        return
    elseif key == "OK" then
        if t9_mode == "url" then
            load_page(t9_text)
            currentPage = "main"
        elseif t9_mode == "search" then
            load_page("https://www.google.com/search?q=" .. t9_text:gsub(" ", "+"))
            currentPage = "main"
        end
        t9_text = ""
        t9_target = 1
        return
    end
    
    -- Ищем кнопку
    for _, k in ipairs(t9_keys) do
        if k[1] == key then
            local chars = k[2]
            if t9_last_key == key and (now - t9_last_time) < 1.5 then
                -- Меняем символ на той же кнопке
                t9_text = t9_text:sub(1, -2)
                t9_target = (t9_target % #chars) + 1
            else
                t9_target = 1
            end
            
            t9_text = t9_text .. chars:sub(t9_target, t9_target)
            t9_last_key = key
            t9_last_time = now
            break
        end
    end
end

-- Отрисовка T9 клавиатуры
local function draw_t9_keyboard()
    -- Поле ввода
    ui.rect(10, 100, 390, 50, 0x0000)
    ui.rect(12, 102, 386, 46, 0x2104)
    ui.text(20, 115, t9_text, 2, 0xFFFF)
    
    -- Индикатор режима
    ui.text(20, 85, "Mode: " .. t9_mode:upper(), 1, 0x07E0)
    
    -- Клавиатура
    local y_start = 170
    for i, key in ipairs(t9_keys) do
        local row = math.floor((i-1)/3)
        local col = (i-1) % 3
        local x = 20 + col * 130
        local y = y_start + row * 60
        
        if ui.button(x, y, 120, 50, key[1], 0x2104) then
            handle_t9_key(key[1])
        end
        ui.text(x + 10, y + 55, key[2], 1, 0xCE79)
    end
    
    -- Специальные кнопки
    local y_special = y_start + 180
    if ui.button(20, y_special, 120, 50, "DEL", 0x4208) then handle_t9_key("DEL") end
    if ui.button(150, y_special, 120, 50, "CLR", 0x4208) then handle_t9_key("CLR") end
    if ui.button(280, y_special, 120, 50, "OK", 0x07E0) then handle_t9_key("OK") end
end

-- Основной экран браузера
function draw_main()
    -- URL строка (кнопка для ввода)
    local display_url = current_url
    if #display_url > 50 then
        display_url = display_url:sub(1, 47) .. "..."
    end
    
    if ui.button(0, 410, 410, 30, display_url, 0x4208) then
        t9_text = current_url
        t9_mode = "url"
        currentPage = "urlenter"
    end
    
    -- Кнопки управления
    if history_pos > 1 then
        if ui.button(60, 445, 90, 40, "Back", 0x2104) then
            if history_pos > 1 then
                history_pos = history_pos - 1
                load_page(history[history_pos])
            end
        end
    end
    
    if ui.button(155, 445, 80, 40, "Reload", 0x2104) then
        load_page(current_url)
    end
    
    if ui.button(240, 445, 115, 40, "Menu", 0x2104) then
        currentPage = "quickmenu"
    end
    
    ui.text(95, 485, "Web Browser", 1, 65535)
    
    -- Контент страницы
    scroll_y = ui.beginList(0, 35, 410, 370, scroll_y, content_height)
    
    local cy = 10
    for _, item in ipairs(content) do
        if item.type == "text" then
            if item.text ~= "" then
                ui.text(10, cy, item.text, 2, 0xFFFF)
                cy = cy + LINE_H
            end
        elseif item.type == "link" then
            if ui.button(5, cy, 400, LINK_H - 5, "", 0x2104) then
                load_page(item.url)
            end
            ui.text(20, cy + 10, "▶ " .. item.text, 2, 0x07FF)
            cy = cy + LINK_H
        end
    end
    
    ui.endList()
    
    -- Статус
    ui.text(240, 0, "100%", 2, 65535)
    ui.text(90, 0, os.date("%H:%M"), 2, 65535)
end

-- Меню быстрого доступа
function draw_quickmenu()
    if ui.button(20, 100, 180, 60, "Google", 0x2104) then
        load_page("https://www.google.com")
        currentPage = "main"
    end
    
    if ui.button(210, 100, 180, 60, "Search", 0x2104) then
        t9_text = ""
        t9_mode = "search"
        currentPage = "urlenter"
    end
    
    if ui.button(20, 170, 180, 60, "History", 0x2104) then
        -- Показываем историю
        content = {}
        for i, url in ipairs(history) do
            add_content(i .. ". " .. url, true, url)
        end
        currentPage = "main"
    end
    
    if ui.button(210, 170, 180, 60, "Clear", 0x2104) then
        content = {}
        add_content("Cleared", false)
        currentPage = "main"
    end
    
    if ui.button(30, 405, 140, 45, "Exit", 0xF800) then
        -- Возвращаемся к загрузчику
        _G.draw = nil
        _G.loop = nil
        dofile("/main.lua")
        return
    end
    
    ui.text(25, 245, "Current URL:", 1, 65535)
    ui.text(25, 265, current_url, 1, 0x07FF)
    
    ui.text(125, 470, "Web Browser 1.0", 1, 65535)
    
    if ui.button(255, 405, 120, 45, "Back", 0x2104) then
        currentPage = "main"
    end
end

-- Ввод URL с T9
function draw_urlenter()
    draw_t9_keyboard()
    
    -- Кнопки управления
    if ui.button(90, 10, 105, 60, "Cancel", 0x4208) then
        currentPage = "main"
    end
    
    if ui.button(205, 10, 110, 60, "Go", 0x07E0) then
        handle_t9_key("OK")
    end
    
    -- Быстрые ссылки
    local quick_sites = {
        {"Google", "https://www.google.com"},
        {"DuckDuckGo", "https://duckduckgo.com"},
        {"Wikipedia", "https://en.m.wikipedia.org"},
        {"GitHub", "https://github.com"},
        {"Reddit", "https://old.reddit.com"}
    }
    
    local y = 360
    for i, site in ipairs(quick_sites) do
        if ui.button(20 + ((i-1) % 3) * 130, y + math.floor((i-1)/3) * 60, 120, 50, site[1], 0x2104) then
            load_page(site[2])
            currentPage = "main"
        end
    end
end

-- Главная функция отрисовки
function draw()
    ui.rect(0, 0, 410, 502, 0)
    
    if currentPage == "main" then
        draw_main()
    elseif currentPage == "quickmenu" then
        draw_quickmenu()
    elseif currentPage == "urlenter" then
        draw_urlenter()
    end
end

-- Инициализация при первом запуске
if not _G.browser_initialized then
    _G.browser_initialized = true
    load_page(current_url)
end

-- Функция loop (можно добавить автообновление)
function loop()
    -- Можно добавить периодические обновления
end
