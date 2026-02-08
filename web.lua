-- Минимальный веб-браузер
local SCR_W, SCR_H = 410, 502
local url = "https://www.google.com"
local scroll = 0
local lines = {}
local loading = false
local history = {}
local history_idx = 0

function fetch(url)
    loading = true
    local res = net.get(url)
    
    if res and res.ok then
        -- Простейший парсинг: убираем теги
        local text = res.body:gsub("<[^>]+>", " ")
        text = text:gsub("%s+", " ")
        
        lines = {}
        for line in text:gmatch("[^\r\n]+") do
            if #line > 3 then
                for i = 1, #line, 60 do
                    table.insert(lines, line:sub(i, i+59))
                end
            end
        end
        
        if #lines == 0 then
            lines = {"[Page loaded]", "[No text content found]", "[Try another site]"}
        end
        
        table.insert(history, url)
        history_idx = #history
    else
        lines = {"[Error loading page]", "URL: " .. url}
        if res then
            table.insert(lines, "Code: " .. tostring(res.code))
        end
    end
    
    loading = false
end

-- Загружаем первую страницу
fetch(url)

while true do
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
    
    -- Панель URL
    ui.rect(0, 0, SCR_W, 40, 0x2104)
    
    -- Поле URL
    if ui.input(10, 5, 250, 30, url, false) then
        -- При тапе показываем диалог
        local new_url = url
        -- Здесь можно добавить простой ввод
    end
    
    -- Кнопка Go
    if ui.button(265, 5, 40, 30, "Go", 0x07E0) then
        fetch(url)
        scroll = 0
    end
    
    -- Кнопки навигации
    if history_idx > 1 and ui.button(310, 5, 30, 30, "<", 0x528A) then
        history_idx = history_idx - 1
        url = history[history_idx]
        fetch(url)
        scroll = 0
    end
    
    if history_idx < #history and ui.button(345, 5, 30, 30, ">", 0x528A) then
        history_idx = history_idx + 1
        url = history[history_idx]
        fetch(url)
        scroll = 0
    end
    
    if ui.button(380, 5, 25, 30, "R", 0x528A) then
        fetch(url)
    end
    
    -- Контент со скроллингом
    local content_h = #lines * 20 + 20
    local new_scroll = ui.beginList(0, 45, SCR_W, SCR_H - 45, scroll, content_h)
    if new_scroll ~= scroll then
        scroll = new_scroll
    end
    
    local y = 45 - scroll
    for i, line in ipairs(lines) do
        if y > 45 and y < SCR_H then
            ui.text(10, y, line, 1, 0xFFFF)
        end
        y = y + 20
    end
    
    -- Показываем конец страницы
    if y < SCR_H then
        ui.text(10, y, "[End of page]", 1, 0x7BEF)
    end
    
    ui.endList()
    
    -- Индикатор загрузки
    if loading then
        ui.rect(SCR_W/2 - 40, SCR_H/2 - 20, 80, 40, 0x0000)
        ui.text(SCR_W/2 - 35, SCR_H/2 - 10, "Loading...", 2, 0xFFE0)
    end
    
    ui.flush()
end
