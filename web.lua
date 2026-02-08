-- webbrowser.lua
-- Простой веб-браузер с T9-клавиатурой для ESP32-S3 (410×502)

local current_url = "http://example.com"
local history = {}
local history_pos = 0
local page_content = ""
local scroll_y = 0
local max_scroll = 0

-- Цветовая схема
local COLOR_BG      = 0x000000
local COLOR_TEXT    = 0xFFFFFF
local COLOR_LINK    = 0x88CCFF
local COLOR_BTN     = 0x444488
local COLOR_BTN_ACT = 0x6666CC
local COLOR_INPUT   = 0x222244
local COLOR_INPUT_T = 0x88FF88

-- T9 клавиатура
local t9_layout = {
    {"1",".,?!","@","#","$","%","^","&","*","(",")"},
    {"2","a","b","c"},
    {"3","d","e","f"},
    {"4","g","h","i"},
    {"5","j","k","l"},
    {"6","m","n","o"},
    {"7","p","q","r","s"},
    {"8","t","u","v"},
    {"9","w","x","y","z"},
    {"0"," ","_","-","/"},
    {"*","←"},      -- backspace
    {"#","OK"}      -- enter
}

local t9_current_key = nil
local t9_char_index = 1
local t9_timer = 0
local T9_TIMEOUT = 1200     -- ms

-- Состояние ввода
local input_text = current_url
local input_focused = false

-- Кнопки интерфейса
local buttons = {
    {x=10,  y=SCR_H-80, w=90, h=70, text="Back",    action="back"},
    {x=110, y=SCR_H-80, w=90, h=70, text="Home",    action="home"},
    {x=210, y=SCR_H-80, w=90, h=70, text="Refresh", action="refresh"},
    {x=310, y=SCR_H-80, w=90, h=70, text="Go",      action="go"}
}

-- История навигации
local function push_history(url)
    if history_pos < #history then
        for i = history_pos+1, #history do
            history[i] = nil
        end
    end
    table.insert(history, url)
    history_pos = #history
end

local function go_back()
    if history_pos > 1 then
        history_pos = history_pos - 1
        current_url = history[history_pos]
        load_page(current_url)
    end
end

local function go_home()
    current_url = "http://example.com"
    push_history(current_url)
    load_page(current_url)
end

-- Упрощённый загрузчик страницы
function load_page(url)
    if not url or url == "" then return end
    
    ui.flush()
    ui.text(10, 10, "Loading...", 24, 0xFFFF00)
    ui.flush()
    
    local resp = net.get(url)
    
    if not resp.ok then
        page_content = "Error: " .. (resp.err or "Unknown error") .. "\nCode: " .. (resp.code or "???")
        max_scroll = 0
        scroll_y = 0
        return
    end
    
    page_content = resp.body or ""
    
    -- Очень простой подсчёт строк для скролла
    local line_count = 0
    for _ in page_content:gmatch("\n") do line_count = line_count + 1 end
    max_scroll = math.max(0, line_count * 28 - (SCR_H - 140))
    
    scroll_y = 0
end

-- ======================================
--  Отрисовка T9 клавиатуры
-- ======================================
local function draw_t9_keyboard()
    local kx, ky = 10, SCR_H - 340
    local key_w, key_h = 75, 75
    local spacing = 10
    
    for row = 1, #t9_layout do
        for col = 1, #t9_layout[row] do
            local key = t9_layout[row][col]
            local x = kx + (col-1)*(key_w + spacing)
            local y = ky + (row-1)*(key_h + spacing)
            
            local color = COLOR_BTN
            if t9_current_key == row*10 + col then
                color = COLOR_BTN_ACT
            end
            
            ui.rect(x, y, key_w, key_h, color)
            ui.rect(x+2, y+2, key_w-4, key_h-4, COLOR_BG)
            
            -- Отображаем текущий символ при наборе
            local display_text = key
            if row >= 2 and row <= 9 and t9_current_key == row*10 + col and t9_char_index > 1 then
                display_text = t9_layout[row][t9_char_index]
            end
            
            ui.text(x + key_w/2 - #display_text*7, y + key_h/2 - 12, display_text, 28, COLOR_TEXT)
        end
    end
end

-- ======================================
--  Отрисовка поля ввода URL
-- ======================================
local function draw_url_bar()
    ui.rect(10, 10, SCR_W-20, 70, COLOR_INPUT)
    ui.rect(15, 15, SCR_W-30, 60, COLOR_BG)
    
    local display_text = input_text
    if input_focused then
        display_text = display_text .. (hw.millis() % 1000 < 500 and "|" or "")
    end
    
    ui.text(30, 35, display_text, 28, input_focused and COLOR_INPUT_T or COLOR_TEXT)
    
    -- Кнопка "Очистить"
    ui.rect(SCR_W-110, 20, 90, 50, COLOR_BTN)
    ui.text(SCR_W-90, 35, "X", 36, COLOR_TEXT)
end

-- ======================================
--  Упрощённый рендеринг страницы
-- ======================================
local function render_page()
    ui.rect(0, 100, SCR_W, SCR_H-180, COLOR_BG)
    
    local y = 110 - scroll_y
    local line_height = 28
    
    for line in page_content:gmatch("[^\r\n]+") do
        if y > 100 and y < SCR_H-100 then
            -- Очень простой HTML-парсер (только текст и <img>)
            if line:match("<img[^>]+src=\"([^\"]+)\"") then
                local img_src = line:match("<img[^>]+src=\"([^\"]+)\"")
                local img_path = "/sd/" .. img_src:match("[^/]+$")  -- только имя файла
                
                -- Пытаемся скачать изображение, если его нет
                if not sd.exists(img_path) then
                    local full_img_url = img_src
                    if not full_img_url:match("^https?://") then
                        -- относительный путь
                        local base = current_url:match("^(https?://[^/]+)")
                        if base then
                            full_img_url = base .. (img_src:sub(1,1)=="/" and "" or "/") .. img_src
                        end
                    end
                    
                    ui.text(20, y, "Downloading image...", 20, 0xFFFF88)
                    net.download(full_img_url, img_path, "sd")
                end
                
                if sd.exists(img_path) then
                    ui.drawJPEG_SD(20, y, img_path)
                    -- Предполагаем, что JPEG ~240px высотой
                    y = y + 260
                else
                    ui.text(20, y, "[Image not loaded: " .. img_path .. "]", 20, 0xFF8888)
                    y = y + line_height
                end
            else
                -- Обычный текст
                local text = line:gsub("<[^>]+>","") -- убираем теги
                text = text:gsub("&[^;]+;"," ")      -- очень грубо
                
                if text:match("^%s*$") then goto continue end
                
                ui.text(20, y, text, 24, COLOR_TEXT)
                y = y + line_height
            end
        end
        
        ::continue::
    end
end

-- ======================================
--  T9 логика
-- ======================================
local function handle_t9(key_row, key_col)
    local key = t9_layout[key_row][key_col]
    
    if key == "←" then
        -- backspace
        input_text = input_text:sub(1, #input_text-1)
        t9_current_key = nil
    elseif key == "OK" then
        -- enter
        current_url = input_text
        push_history(current_url)
        load_page(current_url)
        input_focused = false
        t9_current_key = nil
    elseif key_row >= 2 and key_row <= 9 then
        -- буквы
        if t9_current_key == key_row*10 + key_col then
            -- тот же ключ — следующий символ
            t9_char_index = t9_char_index + 1
            if t9_char_index > #t9_layout[key_row] then
                t9_char_index = 1
            end
        else
            -- новый ключ
            t9_char_index = 1
            t9_current_key = key_row*10 + key_col
        end
        
        -- добавляем/заменяем последний символ
        if #input_text > 0 and t9_char_index > 1 then
            input_text = input_text:sub(1, #input_text-1)
        end
        input_text = input_text .. t9_layout[key_row][t9_char_index]
        
        t9_timer = hw.millis()
    elseif key_row == 10 then
        -- 0 - пробел
        input_text = input_text .. " "
        t9_current_key = nil
    else
        -- цифры, символы
        input_text = input_text .. key
        t9_current_key = nil
    end
end

-- ======================================
--  Основные функции
-- ======================================
function setup()
    hw.setBright(180)
    ui.flush()
    
    -- Начальная страница
    push_history(current_url)
    load_page(current_url)
end

function draw()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, COLOR_BG)
    
    -- URL бар
    draw_url_bar()
    
    -- Кнопки
    for _, btn in ipairs(buttons) do
        ui.rect(btn.x, btn.y, btn.w, btn.h, COLOR_BTN)
        ui.rect(btn.x+4, btn.y+4, btn.w-8, btn.h-8, COLOR_BG)
        ui.text(btn.x + btn.w/2 - #btn.text*10, btn.y + btn.h/2 - 14, btn.text, 28, COLOR_TEXT)
    end
    
    -- T9 клавиатура (показываем когда поле ввода в фокусе)
    if input_focused then
        draw_t9_keyboard()
    end
    
    -- Контент страницы
    render_page()
    
    -- Заголовок текущей страницы
    ui.rect(0, 80, SCR_W, 40, 0x111133)
    ui.text(20, 90, current_url:sub(1,40) .. (#current_url>40 and "..." or ""), 24, 0xAAAAAA)
    
    ui.flush()
end

function loop()
    local touch = ui.getTouch()
    
    if touch.released then
        -- =====================================
        --  Клик по полю ввода
        -- =====================================
        if touch.x >= 15 and touch.x <= SCR_W-35 and
           touch.y >= 15 and touch.y <= 75 then
            input_focused = true
        end
        
        -- Клик по кнопке "X" (очистить)
        if input_focused and touch.x >= SCR_W-110 and touch.x <= SCR_W-20 and
           touch.y >= 20 and touch.y <= 70 then
            input_text = ""
        end
        
        -- Клик по T9 клавишам
        if input_focused then
            local kx, ky = 10, SCR_H - 340
            local key_w, key_h = 75, 75
            local spacing = 10
            
            for row = 1, #t9_layout do
                for col = 1, #t9_layout[row] do
                    local x = kx + (col-1)*(key_w + spacing)
                    local y = ky + (row-1)*(key_h + spacing)
                    
                    if touch.x >= x and touch.x <= x+key_w and
                       touch.y >= y and touch.y <= y+key_h then
                        handle_t9(row, col)
                        break
                    end
                end
            end
        end
        
        -- Кнопки навигации
        for _, btn in ipairs(buttons) do
            if touch.x >= btn.x and touch.x <= btn.x + btn.w and
               touch.y >= btn.y and touch.y <= btn.y + btn.h then
                
                if btn.action == "go" then
                    current_url = input_text
                    push_history(current_url)
                    load_page(current_url)
                    input_focused = false
                elseif btn.action == "back" then
                    go_back()
                elseif btn.action == "home" then
                    go_home()
                elseif btn.action == "refresh" then
                    load_page(current_url)
                end
            end
        end
    end
    
    -- Обработка таймаута T9
    if t9_current_key and hw.millis() - t9_timer > T9_TIMEOUT then
        t9_current_key = nil
        t9_char_index = 1
    end
    
    -- Простой скролл (смахивание вверх/вниз)
    if touch.touching and touch.y < SCR_H-100 and touch.y > 100 then
        if touch.pressed then
            last_y = touch.y
        else
            local dy = touch.y - (last_y or touch.y)
            scroll_y = scroll_y - dy * 1.5
            scroll_y = math.max(0, math.min(max_scroll, scroll_y))
            last_y = touch.y
        end
    end
end
