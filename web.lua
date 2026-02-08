-- Простой веб-браузер для LuaWatch с HTML парсером
-- Сохранить как /main.lua или запустить через recovery mode

-- Константы экрана
local SCR_W, SCR_H = 410, 502

-- Состояние браузера
local state = {
    url = "https://text.npr.org/",  -- Начнем с текстовой версии
    content = "",
    elements = {},                  -- Парсированные элементы {type=, text=, url=, indent=}
    scroll = 0,
    max_scroll = 0,
    page_height = 0,
    status = "Ready",
    history = {},                  -- История URL
    history_index = 1,
    loading = false,
    page_title = "",
    line_spacing = 14,
    text_size = 1
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
    scrollbar = 0x8410,
    h1 = 0xF800,        -- Красный
    h2 = 0xFD20,        -- Оранжевый
    h3 = 0xFFE0,        -- Желтый
    bold = 0xFFE0,      -- Желтый для жирного
    code = 0x07E0       -- Зеленый для кода
}

-- Размеры UI
local UI = {
    title_h = 30,
    status_h = 30,
    scrollbar_w = 8,
    padding = 10,
    indent_size = 15
}

-- Кэш посещенных ссылок
local visited_urls = {}

-- Простой HTML парсер
function parse_html(html)
    local elements = {}
    local pos = 1
    local len = #html
    
    -- Удаляем скрипты и стили
    html = html:gsub("<script[^>]*>.-</script>", "")
    html = html:gsub("<style[^>]*>.-</style>", "")
    html = html:gsub("<noscript[^>]*>.-</noscript>", "")
    
    -- Заменяем HTML сущности
    local entities = {
        ["&nbsp;"] = " ",
        ["&lt;"] = "<",
        ["&gt;"] = ">",
        ["&amp;"] = "&",
        ["&quot;"] = '"',
        ["&apos;"] = "'",
        ["&#160;"] = " ",
        ["&rsquo;"] = "'",
        ["&lsquo;"] = "'",
        ["&rdquo;"] = '"',
        ["&ldquo;"] = '"'
    }
    
    for entity, replacement in pairs(entities) do
        html = html:gsub(entity, replacement)
    end
    
    -- Основной цикл парсинга
    while pos <= len do
        -- Ищем тег
        local tag_start = html:find("<", pos)
        
        if not tag_start then
            -- Текст до конца документа
            local text = html:sub(pos):gsub("%s+", " "):trim()
            if text ~= "" then
                table.insert(elements, {type = "text", text = text})
            end
            break
        end
        
        -- Текст перед тегом
        if tag_start > pos then
            local text = html:sub(pos, tag_start - 1):gsub("%s+", " "):trim()
            if text ~= "" then
                table.insert(elements, {type = "text", text = text})
            end
        end
        
        -- Ищем конец тега
        local tag_end = html:find(">", tag_start)
        if not tag_end then break end
        
        local full_tag = html:sub(tag_start, tag_end)
        
        -- Определяем тип тега
        local tag_name = full_tag:match("<(%w+)")
        
        if tag_name then
            tag_name = tag_name:lower()
            
            -- Закрывающие теги
            if full_tag:match("^</") then
                table.insert(elements, {type = "end_tag", tag = tag_name})
            
            -- Открывающие теги
            else
                -- Извлекаем атрибуты
                local attributes = {}
                for attr, value in full_tag:gmatch('(%w+)="([^"]*)"') do
                    attributes[attr:lower()] = value
                end
                for attr, value in full_tag:gmatch("(%w+)='([^']*)'") do
                    attributes[attr:lower()] = value
                end
                
                -- Извлекаем текст из простых тегов без закрывающих
                local is_self_closing = full_tag:match("/>$")
                local text_content = ""
                
                if is_self_closing then
                    -- Самозакрывающиеся теги
                    if tag_name == "br" then
                        table.insert(elements, {type = "br"})
                    elseif tag_name == "hr" then
                        table.insert(elements, {type = "hr"})
                    end
                else
                    -- Блочные и текстовые теги
                    if tag_name == "a" then
                        table.insert(elements, {
                            type = "link_start",
                            url = attributes.href or "",
                            target = attributes.target
                        })
                    elseif tag_name == "h1" then
                        table.insert(elements, {type = "h1_start"})
                    elseif tag_name == "h2" then
                        table.insert(elements, {type = "h2_start"})
                    elseif tag_name == "h3" then
                        table.insert(elements, {type = "h3_start"})
                    elseif tag_name == "p" then
                        table.insert(elements, {type = "p_start"})
                    elseif tag_name == "div" then
                        table.insert(elements, {type = "div_start"})
                    elseif tag_name == "span" then
                        table.insert(elements, {type = "span_start"})
                    elseif tag_name == "b" or tag_name == "strong" then
                        table.insert(elements, {type = "bold_start"})
                    elseif tag_name == "i" or tag_name == "em" then
                        table.insert(elements, {type = "italic_start"})
                    elseif tag_name == "code" or tag_name == "pre" then
                        table.insert(elements, {type = "code_start"})
                    elseif tag_name == "ul" then
                        table.insert(elements, {type = "ul_start"})
                    elseif tag_name == "ol" then
                        table.insert(elements, {type = "ol_start"})
                    elseif tag_name == "li" then
                        table.insert(elements, {type = "li_start"})
                    end
                end
            end
        end
        
        pos = tag_end + 1
    end
    
    -- Обрабатываем вложенность и извлекаем текст
    local processed = {}
    local stack = {}
    local indent_level = 0
    local in_link = false
    local link_url = ""
    local link_text = ""
    local current_style = {}
    
    for i, elem in ipairs(elements) do
        if elem.type == "text" then
            -- Обрабатываем текст с учетом текущего стиля
            local style = {
                bold = false,
                italic = false,
                code = false,
                indent = indent_level * UI.indent_size
            }
            
            -- Проверяем стек для определения стиля
            for _, tag in ipairs(stack) do
                if tag == "bold" or tag == "strong" then
                    style.bold = true
                elseif tag == "italic" or tag == "em" then
                    style.italic = true
                elseif tag == "code" or tag == "pre" then
                    style.code = true
                elseif tag == "li" then
                    style.indent = style.indent + UI.indent_size
                end
            end
            
            -- Добавляем элемент с текстом
            if in_link then
                table.insert(processed, {
                    type = "link",
                    text = elem.text,
                    url = link_url,
                    style = style
                })
            else
                table.insert(processed, {
                    type = "text",
                    text = elem.text,
                    style = style
                })
            end
        
        elseif elem.type:find("_start$") then
            local base_tag = elem.type:gsub("_start$", "")
            table.insert(stack, base_tag)
            
            if base_tag == "link" then
                in_link = true
                link_url = elem.url or ""
            elseif base_tag == "ul" or base_tag == "ol" then
                indent_level = indent_level + 1
            end
        
        elseif elem.type == "end_tag" then
            local last_tag = stack[#stack]
            if last_tag then
                table.remove(stack, #stack)
                
                if last_tag == "link" then
                    in_link = false
                    link_url = ""
                elseif last_tag == "ul" or last_tag == "ol" then
                    indent_level = math.max(0, indent_level - 1)
                end
            end
        
        elseif elem.type == "br" then
            table.insert(processed, {type = "br"})
        
        elseif elem.type == "hr" then
            table.insert(processed, {type = "hr"})
        end
    end
    
    -- Объединяем последовательные текстовые элементы
    local merged = {}
    local last_text = nil
    
    for i, elem in ipairs(processed) do
        if elem.type == "text" or elem.type == "link" then
            if last_text and 
               last_text.type == elem.type and
               last_text.url == elem.url and
               not (elem.text:match("^%s") or last_text.text:match("%s$")) then
                -- Объединяем с предыдущим
                last_text.text = last_text.text .. " " .. elem.text
            else
                if last_text then
                    table.insert(merged, last_text)
                end
                last_text = elem
            end
        else
            if last_text then
                table.insert(merged, last_text)
                last_text = nil
            end
            table.insert(merged, elem)
        end
    end
    
    if last_text then
        table.insert(merged, last_text)
    end
    
    return merged
end

-- Разбивка текста по строкам с учетом ширины
function wrap_text(text, max_width, size)
    -- Примерная ширина символа (6 пикселей для размера 1, 12 для размера 2)
    local char_width = 6 * size
    local max_chars = math.floor(max_width / char_width)
    
    if #text <= max_chars then
        return {text}
    end
    
    local lines = {}
    local start_pos = 1
    
    while start_pos <= #text do
        -- Ищем последний пробел в пределах max_chars
        local end_pos = start_pos + max_chars - 1
        if end_pos > #text then
            end_pos = #text
        else
            -- Отступаем назад до пробела
            while end_pos > start_pos and text:sub(end_pos, end_pos) ~= " " do
                end_pos = end_pos - 1
            end
            
            if end_pos == start_pos then
                -- Не нашли пробел, режем по max_chars
                end_pos = start_pos + max_chars - 1
            end
        end
        
        local line = text:sub(start_pos, end_pos):trim()
        if line ~= "" then
            table.insert(lines, line)
        end
        
        start_pos = end_pos + 1
    end
    
    return lines
end

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
    
    -- Область контента
    local content_x = UI.padding
    local content_y = UI.title_h + UI.padding
    local content_w = SCR_W - UI.padding * 2 - UI.scrollbar_w
    local content_h = SCR_H - UI.title_h - UI.status_h - UI.padding * 2 - 40
    
    -- Область скролла контента
    local scroll_y = ui.beginList(content_x, content_y, content_w, content_h, 
                                 state.scroll, state.page_height)
    if scroll_y ~= state.scroll then
        state.scroll = scroll_y
    end
    
    -- Отрисовка парсированного контента
    local y = 0
    local line_h = state.line_spacing
    
    for i, elem in ipairs(state.elements) do
        if y - state.scroll > content_h then
            break -- Выходим если ниже видимой области
        end
        
        if y - state.scroll + line_h >= -line_h then -- Рисуем с запасом
            if elem.type == "text" then
                local color = COLORS.text
                if elem.style.bold then color = COLORS.bold end
                if elem.style.code then color = COLORS.code end
                
                local lines = wrap_text(elem.text, content_w - elem.style.indent, state.text_size)
                for _, line in ipairs(lines) do
                    ui.text(elem.style.indent, y, line, state.text_size, color)
                    y = y + line_h
                end
            
            elseif elem.type == "link" then
                local color = visited_urls[elem.url] and COLORS.visited or COLORS.link
                
                local lines = wrap_text(elem.text, content_w - elem.style.indent, state.text_size)
                for _, line in ipairs(lines) do
                    if ui.button(elem.style.indent, y, 
                                #line * 6 * state.text_size, line_h, 
                                line, color) then
                        navigate_to(elem.url)
                    end
                    y = y + line_h
                end
            
            elseif elem.type == "br" then
                y = y + line_h / 2
            
            elseif elem.type == "hr" then
                ui.rect(0, y + line_h/2, content_w, 1, COLORS.text)
                y = y + line_h
            end
        else
            -- Пропускаем невидимые элементы, но считаем их высоту
            if elem.type == "text" or elem.type == "link" then
                local lines = wrap_text(elem.text, content_w, state.text_size)
                y = y + #lines * line_h
            elseif elem.type == "br" then
                y = y + line_h / 2
            elseif elem.type == "hr" then
                y = y + line_h
            end
        end
    end
    
    -- Обновляем высоту страницы
    state.page_height = y
    
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
    local status_y = SCR_H - UI.status_h - 40
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
    
    -- Панель управления
    local controls_y = SCR_H - 35
    
    if ui.button(UI.padding, controls_y, 60, 30, "RELOAD", COLORS.button) then
        load_page(state.url)
    end
    
    if ui.button(UI.padding + 70, controls_y, 60, 30, "HOME", COLORS.button) then
        navigate_to("https://text.npr.org/")
    end
    
    if ui.button(UI.padding + 140, controls_y, 90, 30, "ENTER URL", COLORS.button_active) then
        show_url_input()
    end
    
    -- Настройки отображения
    if ui.button(UI.padding + 240, controls_y, 40, 30, "A+", COLORS.button) then
        state.text_size = math.min(3, state.text_size + 1)
        state.line_spacing = 10 + state.text_size * 4
    end
    
    if ui.button(UI.padding + 290, controls_y, 40, 30, "A-", COLORS.button) then
        state.text_size = math.max(1, state.text_size - 1)
        state.line_spacing = 10 + state.text_size * 4
    end
end

-- Загрузка страницы
function load_page(url)
    state.loading = true
    state.status = "Loading " .. url
    
    local result = net.get(url)
    
    state.loading = false
    
    if result and result.ok and result.code == 200 then
        state.url = url
        state.scroll = 0
        state.status = "Parsing HTML..."
        
        -- Парсим HTML
        state.elements = parse_html(result.body)
        state.status = "Loaded " .. url
        visited_urls[url] = true
        
        -- Сохраняем в историю
        table.insert(state.history, url)
        state.history_index = #state.history
        
        -- Пытаемся извлечь заголовок
        local title = result.body:match("<title>(.-)</title>")
        if title then
            state.page_title = title:gsub("%s+", " "):trim():sub(1, 50)
            state.status = state.status .. " - " .. state.page_title
        end
        
        -- Статистика
        local text_count, link_count = 0, 0
        for _, elem in ipairs(state.elements) do
            if elem.type == "text" then text_count = text_count + 1
            elseif elem.type == "link" then link_count = link_count + 1 end
        end
        state.status = state.status .. string.format(" (%d texts, %d links)", text_count, link_count)
        
    else
        local err = result and result.err or "Unknown error"
        state.status = "Error: " .. err
        if result and result.code then
            state.status = state.status .. " (Code: " .. result.code .. ")"
        end
    end
end

-- Навигация на URL
function navigate_to(url)
    if not url or url == "" or url == state.url then
        return
    end
    
    -- Проверяем и нормализуем URL
    if not url:find("^https?://") then
        if url:find("^//") then
            url = "https:" .. url
        elseif url:find("^/") then
            local base = state.url:match("(https?://[^/]+)")
            if base then
                url = base .. url
            else
                url = "https://" .. url
            end
        else
            -- Относительный URL
            local base = state.url:match("(.-/[^/]*)$")
            if base then
                url = base .. url
            else
                url = "https://" .. url
            end
        end
    end
    
    load_page(url)
end

-- Назад по истории
function go_back()
    if state.history_index > 1 then
        state.history_index = state.history_index - 1
        load_page(state.history[state.history_index])
    end
end

-- Экран ввода URL (без ui.flush внутри цикла)
function show_url_input()
    local input_url = state.url
    local input_active = true
    local last_draw = 0
    
    while input_active do
        local now = hw.millis()
        
        -- Рисуем только раз в 50мс (20 FPS)
        if now - last_draw > 50 then
            -- Фон
            ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
            ui.rect(0, 0, SCR_W, 40, 0x3186)
            ui.text(10, 12, "Enter URL:", 2, 0xFFFF)
            
            -- Поле ввода
            ui.input(10, 50, SCR_W - 20, 40, input_url, true)
            
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
                "wikipedia.org",
                "example.com"
            }
            
            for i, sug in ipairs(suggestions) do
                local x = 10 + ((i-1) % 2) * 200
                local y = 190 + math.floor((i-1)/2) * 45
                
                if ui.button(x, y, 190, 40, sug, 0x8410) then
                    input_url = "https://" .. sug
                end
            end
            
            last_draw = now
        end
        
        -- Обработка тача ввода URL (простая симуляция)
        local touch = ui.getTouch()
        if touch.touching and touch.y > 50 and touch.y < 90 then
            -- Показываем простую клавиатуру для URL
            input_url = simple_keyboard(input_url, "URL")
        end
    end
    
    -- Загружаем выбранную страницу
    if state.url ~= input_url then
        load_page(state.url)
    end
end

-- Упрощенная клавиатура (без ui.flush внутри)
function simple_keyboard(current, label)
    local result = current
    local keys = {
        {"q","w","e","r","t","y","u","i","o","p"},
        {"a","s","d","f","g","h","j","k","l"},
        {"z","x","c","v","b","n","m",".","-","/"},
        {"SPACE","www.",".com",".org",".net","DEL","OK"}
    }
    
    local active = true
    local last_draw = 0
    
    while active do
        local now = hw.millis()
        
        -- Рисуем с ограниченной частотой
        if now - last_draw > 50 then
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
                    if key == "SPACE" then w = w * 2 + 5 end
                    if key:find("%.") then w = w + 10 end
                    if key == "DEL" or key == "OK" then w = w + 15 end
                    
                    if ui.button(x, y, w, key_h, key, 0x8410) then
                        if key == "DEL" then
                            result = result:sub(1, -2)
                        elseif key == "OK" then
                            active = false
                            return result
                        elseif key == "SPACE" then
                            result = result .. " "
                        else
                            result = result .. key
                        end
                    end
                end
            end
            
            last_draw = now
        end
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
        state.status = "WiFi not connected"
    end
end

-- Главный цикл отрисовки
local last_frame = 0
local frame_count = 0
local fps = 0

function draw()
    local now = hw.millis()
    
    -- Ограничиваем FPS до ~30 кадров в секунду
    if now - last_frame >= 33 then
        frame_count = frame_count + 1
        
        -- Считаем FPS раз в секунду
        if now - last_frame >= 1000 then
            fps = frame_count
            frame_count = 0
            last_frame = now
        end
        
        -- Основная отрисовка
        draw_browser()
        
        -- Показываем FPS в углу (для отладки)
        ui.text(SCR_W - 40, SCR_H - 30, fps .. "fps", 1, 0x07E0)
        
        -- flush вызываем ТОЛЬКО здесь, один раз за кадр
        ui.flush()
    end
end

-- Запуск
init()
