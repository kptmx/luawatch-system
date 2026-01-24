-- Настройки репозитория
local user = "kptmx"
local repo = "luawatch-system"
local branch = "main"

local SW, SH = 410, 502
local mode = "LOCAL" 
local scroll = 0
local msg = "Ready"
local wifi_cfg_path = "/wifi.dat" -- Файл для хранения данных сети

-- Состояние WiFi
local ssid, pass = "", ""
local target = "ssid"
local last_key, last_time, char_idx = "", 0, 0

--- ### НОВОЕ: Логика автоподключения ---
function save_wifi()
    -- Сохраняем SSID и пароль через перевод строки
    fs.save(wifi_cfg_path, ssid .. "\n" .. pass)
end

function load_and_connect_wifi()
    if fs.exists(wifi_cfg_path) then
        local data = fs.load(wifi_cfg_path)
        if data then
            -- Разделяем строку по символу переноса
            local s, p = data:match("([^\n]*)\n([^\n]*)")
            if s and s ~= "" then
                ssid, pass = s, p
                net.connect(ssid, pass)
                msg = "Auto-connecting..."
            end
        end
    end
end
-----------------------------------------

local local_files = {}
local store_files = {}
local selected_idx = 0

-- Раскладка T9
local t9 = {
    [".,!1"] = ".,!1", ["abc2"] = "abc2", ["def3"] = "def3",
    ["ghi4"] = "ghi4", ["jkl5"] = "jkl5", ["mno6"] = "mno6",
    ["pqrs7"] = "pqrs7", ["tuv8"] = "tuv8", ["wxyz9"] = "wxyz9",
    ["*"] = "-+=", ["0"] = " ", ["#"] = "#"
}
local keys = {".,!1", "abc2", "def3", "ghi4", "jkl5", "mno6", "pqrs7", "tuv8", "wxyz9", "*", "0", "#", "DEL", "CLR", "OK"}

function handle_t9(k)
    local now = hw.millis()
    local chars = t9[k]
    if not chars then return end
    local val = (target == "ssid") and ssid or pass
    if k == last_key and (now - last_time) < 800 then
        val = val:sub(1, -2)
        char_idx = (char_idx % #chars) + 1
    else char_idx = 1 end
    val = val .. chars:sub(char_idx, char_idx)
    if target == "ssid" then ssid = val else pass = val end
    last_key, last_time = k, now
end

function scan_local()
    local all = fs.list("/")
    local_files = {}
    for _, name in ipairs(all) do
        if name:sub(-4) == ".lua" and name ~= "main.lua" then table.insert(local_files, name) end
    end
    mode = "LOCAL"
    selected_idx = 0
end

function refresh_store()
    if net.status() ~= 3 then
        mode = "WIFI"
        msg = "Connect to WiFi first!"
        return
    end
    msg = "Loading catalog..."
    local url = "https://raw.githubusercontent.com/"..user.."/"..repo.."/"..branch.."/scripts.json"
    local res = net.get(url)
    if res and res.ok and res.code == 200 then
        store_files = {}
        for item in res.body:gmatch("{(.-)}") do
            local name = item:match('"name"%s*:%s*"(.-)"')
            local file = item:match('"file"%s*:%s*"(.-)"')
            local desc = item:match('"desc"%s*:%s*"(.-)"')
            if name and file then table.insert(store_files, {name=name, file=file, desc=desc or ""}) end
        end
        msg = "Found " .. #store_files .. " scripts"
        mode = "STORE"
    else msg = "Catalog error: " .. (res.code or "off") end
end

-- Инициализация при старте
scan_local()
load_and_connect_wifi() -- Пробуем подключиться автоматически

function draw()
    ui.rect(0, 0, SW, SH, 0)
    
    -- Шапка
    ui.rect(0, 0, SW, 60, 0x2104)
    ui.text(20, 15, mode, 3, 0xFFFF)
    
    -- Вкладки
    if ui.button(10, 70, 125, 40, "LOCAL", mode == "LOCAL" and 0x001F or 0x4208) then scan_local() end
    if ui.button(140, 70, 125, 40, "STORE", mode == "STORE" and 0x001F or 0x4208) then refresh_store() end
    if ui.button(270, 70, 125, 40, "WIFI", mode == "WIFI" and 0x001F or 0x4208) then mode = "WIFI" end

    ui.text(20, 115, msg, 1, 0xCE79)

    if mode == "LOCAL" then
        scroll = ui.beginList(10, 140, 390, 260, scroll, #local_files * 55)
        for i, name in ipairs(local_files) do
            local col = (selected_idx == i) and 0x0510 or 0x2104
            if ui.button(0, (i-1)*55, 300, 45, name, col) then selected_idx = i end
        end
        ui.endList()
    elseif mode == "STORE" then
        scroll = ui.beginList(10, 140, 390, 260, scroll, #store_files * 80)
        for i, item in ipairs(store_files) do
            local y = (i-1)*80
            ui.rect(0, y, 380, 75, 0x1082)
            ui.text(10, y+10, item.name, 2, 0xFFFF)
            if ui.button(280, y+15, 90, 45, "GET", 0x07E0) then
                local r = net.get("https://raw.githubusercontent.com/"..user.."/"..repo.."/"..branch.."/"..item.file)
                if r.ok then fs.save("/"..item.file, r.body) msg = "Saved!" else msg = "Fail" end
            end
        end
        ui.endList()
    elseif mode == "WIFI" then
        if ui.input(20, 140, 370, 45, "SSID: "..ssid, target == "ssid") then target = "ssid" end
        if ui.input(20, 190, 370, 45, "PASS: "..pass, target == "pass") then target = "pass" end
        
        -- Кнопка CONNECT (теперь с сохранением)
        if ui.button(20, 245, 180, 45, "CONNECT", 0x07E0) then
            save_wifi() -- СОХРАНЯЕМ ПЕРЕД ПОДКЛЮЧЕНИЕМ
            net.connect(ssid, pass)
            msg = "Connecting & Saving..."
        end
        
        -- Клавиатура
        for i, k in ipairs(keys) do
            local r, c = math.floor((i-1)/3), (i-1)%3
            if ui.button(20 + c*125, 300 + r*35, 115, 32, k, 0x2104) then
                if k == "DEL" then if target == "ssid" then ssid = ssid:sub(1,-2) else pass = pass:sub(1,-2) end
                elseif k == "CLR" then if target == "ssid" then ssid = "" else pass = "" end
                elseif k == "OK" then target = "" 
                else handle_t9(k) end
            end
        end
        if net.status() == 3 then msg = "Online: " .. net.getIP() end
    end

    -- Нижняя панель
    ui.rect(0, 460, SW, 42, 0x2104)
    if mode == "LOCAL" and selected_idx > 0 then
        if ui.button(20, 465, 100, 32, "RUN", 0x07E0) then
            local f = load(fs.load("/"..local_files[selected_idx]))
            if f then f() end
        end
    end
    if ui.button(300, 465, 90, 32, "REBOOT", 0x4208) then hw.reboot() end
end
