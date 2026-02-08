-- webbrowser.lua (исправленная версия для ESP32-S3 410x502)
-- Простой веб-браузер с T9 и JPEG

local SCR_W = 410
local SCR_H = 502

local current_url = "http://example.com"
local page_content = ""
local scroll_y = 0
local input_text = ""
local input_focused = false

-- Цвета (RGB565)
local COLOR_BG     = 0x0000
local COLOR_TEXT   = 0xFFFF
local COLOR_LINK   = 0xC618
local COLOR_BTN    = 0x4208
local COLOR_BTN_ACT= 0x636C
local COLOR_INPUT  = 0x2121
local COLOR_INPUT_T= 0x8FE0

-- T9 клавиатура (4 ряда для компактности)
local t9_layout = {
    {".","1","abc","def","ghi"},
    {"jkl","mno","pqrs","tuv","wxyz"},
    {"0"," ","←","OK"},
    {"http://",".com","Go","Back"}
}

local t9_current_key = nil
local t9_char_index = 1
local t9_timer = 0
local T9_TIMEOUT = 1000
local last_touch_y = 0

-- История (простая)
local history = {"http://example.com"}
local history_idx = 1

local function load_page(url)
    if not net.status() == 3 then -- 3 = подключен
        page_content = "WiFi disconnected!"
        return
    end
    
    ui.text(20, 20, "Loading: " .. url:sub(1,30), 20, 0xFFFF00)
    ui.flush()
    
    local resp = net.get(url)
    if resp.ok and resp.body then
        page_content = resp.body
    else
        page_content = "Error " .. (resp.code or 0) .. ": " .. (resp.err or "no response")
    end
end

local function draw_url_bar()
    ui.rect(5, 5, SCR_W-10, 45, COLOR_INPUT)
    ui.rect(10, 10, SCR_W-20, 35, COLOR_BG)
    
    local disp_text = input_text:sub(1,35)
    if #input_text > 35 then disp_text = disp_text .. "..." end
    
    if input_focused and (hw.millis() % 1000 < 500) then
        disp_text = disp_text .. "|"
    end
    
    ui.text(20, 22, disp_text, 20, input_focused and COLOR_INPUT_T or COLOR_TEXT)
end

local function draw_t9_keyboard()
    local ky = SCR_H - 220
    local key_w, key_h = 72, 50
    local spacing = 8
    
    for row=1, #t9_layout do
        local row_len = #t9_layout[row]
        local start_x = (SCR_W - row_len*(key_w + spacing) + spacing)/2
        
        for col=1, row_len do
            local x = start_x + (col-1)*(key_w + spacing)
            local y = ky + (row-1)*(key_h + 8)
            
            local key = t9_layout[row][col]
            local color = COLOR_BTN
            local text = key
            
            -- Подсветка текущей клавиши
            local key_id = row*10 + col
            if t9_current_key == key_id then
                color = COLOR_BTN_ACT
                if row >= 3 and #key == 1 and key:match("[%w]") then
                    text = key:upper()  -- показываем текущий символ
                end
            end
            
            ui.rect(x, y, key_w, key_h, color)
            ui.rect(x+2, y+2, key_w-4, key_h-4, COLOR_BG)
            ui.text(x + key_w/2 - #text*6, y + key_h/2 - 10, text, 22, COLOR_TEXT)
        end
    end
end

local function draw_buttons()
    local btn_y = SCR_H - 60
    local btn_w, btn_h = 90, 50
    
    local btns = {
        {text="Back", x=10},
        {text="Home", x=110},
        {text="Go", x=220},
        {text="↑↓", x=320}  -- скролл
    }
    
    for i, btn in ipairs(btns) do
        local color = COLOR_BTN
        ui.rect(btn.x, btn_y, btn_w, btn_h, color)
        ui.rect(btn.x+3, btn_y+3, btn_w-6, btn_h-6, COLOR_BG)
        ui.text(btn.x + btn_w/2 - #btn.text*8, btn_y + btn_h/2 - 12, btn.text, 20, COLOR_TEXT)
    end
end

local function render_content()
    ui.rect(0, 60, SCR_W, SCR_H-280, COLOR_BG)
    
    local y = 70 - scroll_y
    local line_h = 24
    
    -- Простой рендер (строки + img)
    for line in page_content:gmatch("[^\n\r]+") do
        if y > 60 and y < SCR_H-280 then
            -- <img src="...">
            local img_src = line:match('src=["\']([^"\']+)["\']')
            if img_src then
                local img_path = "/img_" .. (hw.millis() % 10000) .. ".jpg"  -- уникальное имя
                if not sd.exists(img_path) then
                    net.download(img_src, img_path, "sd")
                end
                if sd.exists(img_path) then
                    local ok = ui.drawJPEG_SD(20, y, img_path)
                    y = y + (ok and 200 or line_h)
                else
                    ui.text(20, y, "[IMG: " .. img_src:sub(-20) .. "]", 18, 0xFF4400)
                    y = y + line_h
                end
            else
                -- текст (убираем теги)
                local text = line:gsub("<[^>]*>", ""):gsub("&nbsp;", " ")
                text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
                if #text > 0 then
                    ui.text(15, y, text, 20, COLOR_TEXT)
                    y = y + line_h
                end
            end
        end
    end
end

local function handle_t9_touch(tx, ty)
    local ky = SCR_H - 220
    local key_w, key_h = 72, 50
    local spacing = 8
    
    for row=1, #t9_layout do
        local row_len = #t9_layout[row]
        local start_x = (SCR_W - row_len*(key_w + spacing) + spacing)/2
        
        for col=1, row_len do
            local x = start_x + (col-1)*(key_w + spacing)
            local y = ky + (row-1)*(key_h + 8)
            
            if tx >= x and tx <= x+key_w and ty >= y and ty <= y+key_h then
                local key = t9_layout[row][col]
                local key_id = row*10 + col
                
                if key == "←" then
                    input_text = input_text:sub(1, -2)
                elseif key == "OK" or key == "Go" then
                    if #input_text > 0 then
                        current_url = input_text
                        history[#history+1] = current_url
                        history_idx = #history
                        load_page(current_url)
                    end
                    input_focused = false
                elseif key == "Back" then
                    if history_idx > 1 then
                        history_idx = history_idx - 1
                        current_url = history[history_idx]
                        load_page(current_url)
                    end
                    input_focused = false
                elseif key == "Home" then
                    current_url = "http://example.com"
                    load_page(current_url)
                    input_focused = false
                elseif key == "http://" or key == ".com" then
                    input_text = input_text .. key
                elseif #key == 1 and key:match("[%w%.%?!/]") then
                    input_text = input_text .. key
                else
                    -- T9 буквы (2-4 символа на клавишу)
                    if t9_current_key == key_id then
                        t9_char_index = t9_char_index % #key + 1
                    else
                        t9_char_index = 1
                        t9_current_key = key_id
                    end
                    input_text = input_text:sub(1,-2) .. key:sub(t9_char_index, t9_char_index)
                    t9_timer = hw.millis()
                end
                return true
            end
        end
    end
    return false
end

function setup()
    hw.setBright(200)
    load_page(current_url)
end

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, COLOR_BG)
    
    draw_url_bar()
    draw_buttons()
    
    if input_focused then
        draw_t9_keyboard()
    end
    
    render_content()
    
    -- Статус
    local batt = hw.getBatt()
    ui.text(SCR_W-80, 10, batt .. "%", 18, 0x00FF00)
    
    ui.flush()
end

function loop()
    local touch = ui.getTouch()
    
    if touch.released then
        -- URL bar
        if touch.x > 10 and touch.x < SCR_W-10 and touch.y < 55 then
            input_focused = true
            input_text = current_url
        end
        
        -- Кнопки
        local btn_y = SCR_H - 60
        if touch.y > btn_y and touch.y < btn_y+50 then
            local btn_x = {10, 110, 220, 320}
            local btn_id = math.floor((touch.x - 10)/100) + 1
            if btn_id == 1 then  -- Back
                if history_idx > 1 then history_idx = history_idx - 1; load_page(history[history_idx]) end
            elseif btn_id == 2 then  -- Home
                load_page("http://example.com")
            elseif btn_id == 3 then  -- Go
                if input_focused and #input_text > 0 then
                    current_url = input_text; load_page(current_url)
                end
            end
        end
        
        -- T9
        if input_focused and touch.y > SCR_H-220 then
            handle_t9_touch(touch.x, touch.y)
        end
    end
    
    -- Скролл (drag)
    if touch.touching and not input_focused and touch.y > 60 and touch.y < SCR_H-280 then
        if touch.pressed then
            last_touch_y = touch.y
        else
            local dy = touch.y - last_touch_y
            scroll_y = math.max(0, scroll_y + dy)
            last_touch_y = touch.y
        end
    end
    
    -- T9 timeout
    if t9_current_key and hw.millis() - t9_timer > T9_TIMEOUT then
        t9_current_key = nil
    end
end
