-- Константы оформления
local COLOR = {
    BG = 0,
    ACCENT = 0x07E0, 
    TEXT = 0xFFFF,   
    GRAY = 0x8410,
    RED = 0xF800,
    DARK = 0x2104
}

-- Состояния приложения: "watch", "menu", "wifi_config"
local state = "watch" 
local scrollY = 0
local last_weather_update = -600000 
local weather_temp = "No Data"

-- Данные WiFi
local wifi_ssid = fs.load("/ssid.txt") or ""
local wifi_pass = fs.load("/pass.txt") or ""
local target_field = "ssid" -- что сейчас вводим

-- Для клавиатуры T9
local last_key, last_time, char_idx = "", 0, 0
local t9 = {
    [".,!1"]=".,!1", ["abc2"]="abc2", ["def3"]="def3",
    ["ghi4"]="ghi4", ["jkl5"]="jkl5", ["mno6"]="mno6",
    ["pqrs7"]="pqrs7",["tuv8"]="tuv8", ["wxyz9"]="wxyz9",
    ["*"]="-+=", ["0"]=" ",   ["#"]="#"
}
local keys = {".,!1","abc2","def3","ghi4","jkl5","mno6","pqrs7","tuv8","wxyz9","*","0","#","DEL","CLR","OK"}

-- --- ЛОГИКА ---

function handle_t9(k)
    local now = hw.millis()
    local chars = t9[k]
    if not chars then return end
    
    local val = (target_field == "ssid") and wifi_ssid or wifi_pass
    if k == last_key and (now - last_time) < 800 then
        val = val:sub(1, -2)
        char_idx = (char_idx % #chars) + 1
    else
        char_idx = 1
    end
    val = val .. chars:sub(char_idx, char_idx)
    if target_field == "ssid" then wifi_ssid = val else wifi_pass = val end
    last_key, last_time = k, now
end

function update_weather()
    if net.status() == 3 then 
        local data = net.get("http://wttr.in/?format=%t+%C")
        if data then weather_temp = data; last_weather_update = hw.millis() end
    end
end

-- --- ЭКРАНЫ ---

-- ЭКРАН: Настройка WiFi (аналог Bootstrap)
function draw_wifi_config()
    ui.text(20, 20, "WIFI SETUP", 3, COLOR.ACCENT)
    
    if ui.input(20, 70, 370, 45, "SSID: "..wifi_ssid, target_field == "ssid") then target_field = "ssid" end
    if ui.input(20, 125, 370, 45, "PASS: "..wifi_pass, target_field == "pass") then target_field = "pass" end

    if ui.button(20, 185, 180, 45, "CONNECT", 0x0500) then 
        fs.save("/ssid.txt", wifi_ssid)
        fs.save("/pass.txt", wifi_pass)
        net.connect(wifi_ssid, wifi_pass)
        state = "menu"
    end
    if ui.button(210, 185, 180, 45, "CANCEL", COLOR.RED) then state = "menu" end

    -- Клавиатура
    for i, k in ipairs(keys) do
        local r, c = math.floor((i-1)/3), (i-1)%3
        if ui.button(20+c*125, 245+r*42, 115, 38, k, 0x2104) then
            if k == "DEL" then 
                if target_field == "ssid" then wifi_ssid=wifi_ssid:sub(1,-2) else wifi_pass=wifi_pass:sub(1,-2) end
            elseif k == "CLR" then 
                if target_field == "ssid" then wifi_ssid="" else wifi_pass="" end
            elseif k == "OK" then target_field = ""
            else handle_t9(k) end
        end
    end
end

-- ЭКРАН: Главное Меню
function draw_menu()
    ui.text(20, 20, "SETTINGS", 3, COLOR.ACCENT)
    scrollY = ui.beginList(0, 70, 410, 432, scrollY, 400)
    
    local status = net.status()
    ui.text(20, 10, status == 3 and "Status: Online" or "Status: Offline", 2, status == 3 and COLOR.ACCENT or COLOR.RED)
    
    if ui.button(20, 50, 370, 60, "WIFI CONFIG", COLOR.DARK) then state = "wifi_config" end
    if ui.button(20, 120, 370, 60, "UPDATE WEATHER", COLOR.DARK) then update_weather() end
    if ui.button(20, 190, 370, 60, "BACK", COLOR.GRAY) then state = "watch" end
    
    ui.endList()
end

-- ЭКРАН: Циферблат
function draw_watch()
    local t = hw.getTime()
    ui.text(60, 150, string.format("%02d:%02d", t.h, t.m), 10, COLOR.ACCENT)
    
    -- Мини-виджеты
    ui.text(130, 260, "BATT: " .. hw.getBatt() .. "%", 2, COLOR.GRAY)
    
    ui.rect(40, 320, 330, 80, COLOR.DARK)
    ui.text(60, 340, "WEATHER", 1, COLOR.GRAY)
    ui.text(60, 360, weather_temp, 3, COLOR.TEXT)
    
    if ui.button(155, 430, 100, 40, "MENU", COLOR.DARK) then state = "menu" end

    -- Авто-обновление погоды в фоне
    if net.status() == 3 and (hw.millis() - last_weather_update > 900000) then
        update_weather()
    end
end

-- ГЛАВНЫЙ ЦИКЛ
function draw()
    ui.rect(0, 0, 410, 502, COLOR.BG)
    
    if state == "watch" then
        draw_watch()
    elseif state == "menu" then
        draw_menu()
    elseif state == "wifi_config" then
        draw_wifi_config()
    end
end

-- Попытка авто-подключения при старте, если данные есть
if wifi_ssid ~= "" then net.connect(wifi_ssid, wifi_pass) end
