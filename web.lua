-- Простой веб-браузер для LuaWatch
-- Сохранить как /main.lua или запустить через recovery mode

-- Константы экрана
local SCR_W, SCR_H = 410, 502

-- Состояние браузера
local state = {
    url = "https://text.npr.org/",  -- Начнем с текстовой версии NPR
    content = "",
    links = {},                    -- Массив ссылок {text=..., url=...}
    scroll = 0,
    max_scroll = 0,
    page_height = 0,
    status = "Ready",
    history = {},                  -- История URL
    history_index = 1,
    loading = false,
    page_title = ""
}

-- Цвета
local COLORS = {
    bg = 0x0000,        -- Черный
    text = 0xFFFF,      -- Белый
    link = 0x07FF,      -- Голубой
    visited = 0xA81F,   -- Фиолетовый
    title_bg = 0x3186,  -- Темно-синий
    status_bg = 0x632C, -- Темно-серый
    button = 0x8410,    -- Серый
    button_active = 0x07E0, -- Зеленый
    scrollbar = 0x8410
}

-- Размеры UI
local UI = {
    title_h = 30,
    status_h = 30,
    scrollbar_w = 8,
    padding = 10
}

-- Кэш посещенных ссылок
local visited_urls = {}

-- Основной экран браузера
function draw_browser()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, COLORS.bg)
    
    -- Заголовок (URL бар)
    ui.rect(0, 0, SCR_W, UI.title_h, COLORS.title_bg)
    local display_url = state.url
    if #display_url > 40 then
        display_url = "..." .. display_url:sub(-37)
    end
    ui.text(UI.padding, 8, display_url, 1, COLORS.text)
    
    -- Кнопка НАЗАД
    if ui.button(SCR_W - 50, 5, 45, 20, "BACK", COLORS.button) then
        go_back()
    end
    
    -- Область контента (с отступами для скроллбара)
    local content_x = UI.padding
    local content_y = UI.title_h + UI.padding
    local content_w = SCR_W - UI.padding * 2 - UI.scrollbar_w
    local content_h = SCR_H - UI.title_h - UI.status_h - UI.padding * 2
    
    -- Область скролла контента
    local scroll_y = ui.beginList(content_x, content_y, content_w, content_h, 
                                 state.scroll, state.page_height)
    if scroll_y ~= state.scroll then
        state.scroll = scroll_y
    end
    
    -- Отрисовка текста контента
    if state.content ~= "" then
        local y = 0
        local line_h = 12
        local wrap_w = content_w - UI.padding
        
        -- Парсим контент по строкам
        local lines = {}
        for line in state.content:gmatch("[^\n]+") do
            -- Проверяем, не ссылка ли это
            local is_link = false
            local link_text, link_url = "", ""
            
            for _, link in ipairs(state.links) do
                if line:find(link.text, 1, true) then
                    is_link = true
                    link_text = link.text
                    link_url = link.url
                    break
                end
            end
            
            if is_link then
                -- Рисуем ссылку
                local color = visited_urls[link_url] and COLORS.visited or COLORS.link
                if ui.button(0, y, wrap_w, line_h, link_text, color) then
                    navigate_to(link_url)
                end
                y = y + line_h + 2
            else
                -- Обертка текста
                local words = {}
                for word in line:gmatch("%S+") do
                    table.insert(words, word)
                end
                
                local current_line = ""
                for _, word in ipairs(words) do
                    -- Проверяем ширину текста (грубое приближение)
                    local test_line = current_line .. (current_line == "" and "" or " ") .. word
                    if #test_line * 6 > wrap_w then
                        -- Выводим текущую строку
                        ui.text(0, y, current_line, 1, COLORS.text)
                        y = y + line_h
                        current_line = word
                    else
                        current_line = test_line
                    end
                end
                
                if current_line ~= "" then
                    ui.text(0, y, current_line, 1, COLORS.text)
                    y = y + line_h
                end
            end
        end
        
        -- Обновляем высоту страницы
        state.page_height = y
    else
        ui.text(0, 0, "No content", 2, COLORS.text)
        state.page_height = 0
    end
    
    ui.endList()
    
    -- Скроллбар
    if state.page_height > content_h then
        local scrollbar_h = math.max(20, content_h * content_h / state.page_height)
        local scrollbar_y = content_y + (state.scroll * (content_h - scrollbar_h) / 
                                       (state.page_height - content_h))
        
        ui.rect(SCR_W - UI.scrollbar_w - UI.padding, scrollbar_y, 
                UI.scrollbar_w, scrollbar_h, COLORS.scrollbar)
    end
    
    -- Статус бар
    local status_y = SCR_H - UI.status_h
    ui.rect(0, status_y, SCR_W, UI.status_h, COLORS.status_bg)
    
    if state.loading then
        ui.text(UI.padding, status_y + 8, "Loading...", 1, 0x07E0)
    else
        local status_text = state.status
        if #status_text > 50 then
            status_text = status_text:sub(1, 47) .. "..."
        end
        ui.text(UI.padding, status_y + 8, status_text, 1, COLORS.text)
    end
    
    -- Кнопки управления внизу
    local btn_y = status_y - 35
    if ui.button(UI.padding, btn_y, 80, 30, "RELOAD", COLORS.button) then
        load_page(state.url)
    end
    
    if ui.button(UI.padding + 90, btn_y, 80, 30, "HOME", COLORS.button) then
        navigate_to("https://text.npr.org/")
    end
    
    -- Кнопка ввода URL
    if ui.button(UI.padding + 180, btn_y, 120, 30, "ENTER URL", COLORS.button_active) then
        show_url_input()
    end
end

-- Загрузка страницы
function load_page(url)
    state.loading = true
    state.status = "Loading " .. url
    
    local result = net.get(url)
    
    state.loading = false
    
    if result and result.ok and result.code == 200 then
        state.content = result.body or ""
        state.url = url
        state.scroll = 0
        state.status = "Loaded " .. url
        visited_urls[url] = true
        
        -- Парсим ссылки (упрощенный парсинг для текстовых страниц)
        parse_links(state.content)
        
        -- Сохраняем в историю
        table.insert(state.history, url)
        state.history_index = #state.history
        
        -- Пытаемся извлечь заголовок
        local title = state.content:match("<title>(.-)</title>")
        if title then
            state.page_title = title:gsub("%s+", " "):sub(1, 50)
            state.status = state.status .. " - " .. state.page_title
        end
        
    else
        local err = result and result.err or "Unknown error"
        state.status = "Error: " .. err
        if result and result.code then
            state.status = state.status .. " (Code: " .. result.code .. ")"
        end
    end
end

-- Упрощенный парсинг ссылок
function parse_links(html)
    state.links = {}
    
    -- Ищем ссылки в формате <a href="...">текст</a>
    for link_text, link_url in html:gmatch('<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>') do
        -- Убираем лишние пробелы
        link_text = link_text:gsub("%s+", " "):trim()
        link_url = link_url:trim()
        
        -- Делаем абсолютный URL если нужно
        if not link_url:find("^https?://") then
            if link_url:find("^//") then
                link_url = "https:" .. link_url
            elseif link_url:find("^/") then
                local base = state.url:match("(https?://[^/]+)")
                if base then
                    link_url = base .. link_url
                end
            else
                -- Относительный URL
                local base = state.url:match("(.-/[^/]*)$")
                if base then
                    link_url = base .. link_url
                end
            end
        end
        
        if link_text ~= "" and link_url ~= "" then
            table.insert(state.links, {
                text = link_text,
                url = link_url
            })
        end
    end
    
    -- Также ищем ссылки в текстовом формате (для text.npr.org)
    for link_url in html:gmatch("(https?://[%w%.%-/_?=%%&]+)") do
        -- Берем последний сегмент как текст
        local text = link_url:match("/([^/]+)$") or link_url:match("://([^/]+)") or link_url
        text = text:sub(1, 40)
        
        table.insert(state.links, {
            text = text,
            url = link_url
        })
    end
    
    state.status = state.status .. string.format(" (%d links found)", #state.links)
end

-- Навигация на URL
function navigate_to(url)
    if url and url ~= "" and url ~= state.url then
        load_page(url)
    end
end

-- Назад по истории
function go_back()
    if state.history_index > 1 then
        state.history_index = state.history_index - 1
        load_page(state.history[state.history_index])
    end
end

-- Экран ввода URL
function show_url_input()
    local input_url = state.url
    local input_active = true
    
    while input_active do
        -- Фон
        ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
        ui.rect(0, 0, SCR_W, 40, 0x3186)
        ui.text(10, 12, "Enter URL:", 2, 0xFFFF)
        
        -- Поле ввода
        if ui.input(10, 50, SCR_W - 20, 40, input_url, true) then
            -- Обновление URL при клике (простейший ввод)
            input_url = string_input(input_url, "URL")
        end
        
        -- Кнопки
        if ui.button(10, 100, 120, 40, "GO", 0x07E0) then
            if input_url ~= "" then
                if not input_url:find("^https?://") then
                    input_url = "https://" .. input_url
                end
                state.url = input_url
                input_active = false
            end
        end
        
        if ui.button(140, 100, 120, 40, "CANCEL", 0xF800) then
            input_active = false
        end
        
        -- Предложения
        ui.text(10, 160, "Suggestions:", 2, 0xFFFF)
        
        local suggestions = {
            "text.npr.org",
            "lite.cnn.com",
            "www.bbc.com",
            "news.ycombinator.com",
            "wikipedia.org"
        }
        
        for i, sug in ipairs(suggestions) do
            local x = 10 + ((i-1) % 2) * 200
            local y = 190 + math.floor((i-1)/2) * 45
            
            if ui.button(x, y, 190, 40, sug, 0x8410) then
                input_url = "https://" .. sug
            end
        end
        
        ui.flush()
    end
    
    -- Загружаем выбранную страницу
    if state.url ~= input_url then
        load_page(state.url)
    end
end

-- Простейший ввод строки (симуляция клавиатуры)
function string_input(current, label)
    local result = current
    local keys = {
        {"q","w","e","r","t","y","u","i","o","p","DEL"},
        {"a","s","d","f","g","h","j","k","l",";","'"}, 
        {"z","x","c","v","b","n","m",".",",","/","BS"},
        {"SPACE","https://","www.",".com",".org","OK"}
    }
    
    while true do
        -- Фон
        ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
        ui.rect(0, 0, SCR_W, 60, 0x3186)
        ui.text(10, 20, label .. ":", 2, 0xFFFF)
        ui.text(10, 40, result, 1, 0xFFFF)
        
        -- Клавиатура
        local key_w = 35
        local key_h = 40
        local start_y = 70
        
        for row_idx, row in ipairs(keys) do
            for col_idx, key in ipairs(row) do
                local x = 5 + (col_idx-1) * (key_w + 5)
                local y = start_y + (row_idx-1) * (key_h + 5)
                local w = key_w
                
                -- Широкие клавиши
                if key == "DEL" or key == "BS" then w = w + 20 end
                if key == "SPACE" then w = w * 3 + 10 end
                if key:find("%.") then w = w + 15 end
                if key == "OK" then w = w + 20 end
                
                if ui.button(x, y, w, key_h, key, 0x8410) then
                    if key == "DEL" then
                        result = result:sub(1, -2)
                    elseif key == "BS" then
                        result = ""
                    elseif key == "SPACE" then
                        result = result .. " "
                    elseif key == "OK" then
                        return result
                    elseif key:find("^https?://") or key:find("^www%.") or key:find("^%.") then
                        result = result .. key
                    else
                        result = result .. key
                    end
                end
            end
        end
        
        ui.flush()
    end
    
    return result
end

-- Инициализация
function init()
    state.status = "Initializing..."
    
    -- Проверяем соединение
    local wifi_status = net.status()
    if wifi_status == 3 then
        state.status = "Connected to WiFi, loading page..."
        load_page(state.url)
    else
        state.status = "Not connected to WiFi. Use recovery mode to setup."
        
        -- Предлагаем перейти в recovery mode
        if ui.button(100, 200, 200, 50, "RECOVERY MODE", 0xF800) then
            -- Сбрасываем в recovery (через перезагрузку с зажатой кнопкой)
            hw.reboot()
        end
    end
end

-- Главный цикл
function draw()
    if state.url then
        draw_browser()
    else
        -- Экран приветствия
        ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
        ui.text(100, 50, "Simple Browser", 3, 0xFFFF)
        ui.text(50, 100, "Press any key to start", 2, 0xFFFF)
        
        if ui.button(100, 200, 200, 50, "START", 0x07E0) then
            init()
        end
    end
end

-- Запуск
init()
