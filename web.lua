-- Простой веб-браузер на Lua для вашей прошивки
-- Основные возможности:
-- • Загрузка страниц по HTTP/HTTPS
-- • Простой парсинг HTML (текст + кликабельные ссылки)
-- • Скролл контента
-- • Отображение текста с переносом строк
-- • Переход по ссылкам (клик по синему тексту)
-- • Кнопки Back / Reload / Home
-- • Адресная строка (только отображение, ввод URL вручную пока не реализован — можно добавить T9-клавиатуру по аналогии с bootstrap)

local SCR_W, SCR_H = 410, 502
local LINE_H = 28
local LINK_H = 36
local MAX_CHARS_PER_LINE = 52  -- примерно для size=2 на ширине ~400px

local current_url = "https://news.ycombinator.com"  -- стартовая страница (простая, много текста и ссылок)
local history = {}
local history_pos = 0
local scroll_y = 0

local content = {}          -- массив элементов {type="text"|"link", text="...", url="..."}
local content_height = 0

-- Простое разрешение относительных ссылок
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
            -- ищем последний пробел в строке
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

-- Добавление контента (текст или ссылка)
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

-- Очень простой HTML-парсер (только текст и <a href>)
function parse_html(html)
    content = {}
    content_height = 60  -- отступ сверху

    local pos = 1
    local buffer = ""
    local in_link = false
    local link_url = nil

    while pos <= #html do
        local tag_start, tag_end, closing, tag_name = html:find("<(/?)([%a][%w-]*)", pos)
        if tag_start then
            -- текст до тега
            local text_part = html:sub(pos, tag_start - 1)
            text_part = text_part:gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", "\"")
            buffer = buffer .. text_part
            add_content(buffer, in_link, link_url)
            buffer = ""

            if closing == "" then  -- открывающий тег
                if tag_name:lower() == "a" then
                    local href = html:match('href%s*=%s*["\']([^"\']+)["\']', tag_start)
                    if href then
                        link_url = resolve_url(current_url, href)
                        in_link = true
                    end
                elseif tag_name:lower() == "br" then
                    content_height = content_height + LINE_H
                elseif tag_name:lower() == "p" or tag_name:lower() == "div" then
                    content_height = content_height + LINE_H
                end
            else  -- закрывающий тег
                if tag_name:lower() == "a" then
                    add_content(buffer, true, link_url)
                    buffer = ""
                    in_link = false
                    link_url = nil
                end
            end
            pos = tag_end + 1
        else
            buffer = buffer .. html:sub(pos)
            pos = #html + 1
        end
    end
    add_content(buffer, in_link, link_url)
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
        add_content("Ошибка загрузки страницы", false)
        add_content("URL: " .. new_url, false)
        add_content("Код: " .. tostring(res.code or "—"), false)
        add_content("Ошибка: " .. tostring(res.err or "нет ответа"), false)
    end
end

-- Назад по истории
local function go_back()
    if history_pos > 1 then
        history_pos = history_pos - 1
        load_page(history[history_pos])
    end
end

-- Инициализация (первая загрузка)
load_page(current_url)

-- Основной цикл отрисовки
function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)

    -- Адресная строка + кнопки управления
    ui.text(10, 12, current_url:sub(1, 65), 2, 0xFFFF)  -- обрезанный URL

    if history_pos > 1 then
        if ui.button(10, 52, 100, 40, "Back", 0x4208) then go_back() end
    end
    if ui.button(120, 52, 130, 40, "Reload", 0x4208) then load_page(current_url) end
    if ui.button(260, 52, 130, 40, "Home", 0x4208) then load_page("https://news.ycombinator.com") end

    -- Контент со скроллом
    scroll_y = ui.beginList(0, 100, SCR_W, SCR_H - 100, scroll_y, content_height)

    local cy = 20
    for _, item in ipairs(content) do
        if item.type == "text" then
            ui.text(20, cy, item.text, 2, 0xFFFF)
            cy = cy + LINE_H
        else  -- link
            -- Невидимая кнопка для обработки клика + синий текст
            local clicked = ui.button(10, cy, SCR_W - 20, LINK_H, "", 0)
            ui.text(25, cy + 6, item.text, 2, 0x07FF)  -- ярко-синий для ссылок
            if clicked then
                load_page(item.url)
            end
            cy = cy + LINK_H
        end
    end

    ui.endList()
end
