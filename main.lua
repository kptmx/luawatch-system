-- Настройки репозитория
local user = "kptmx"
local repo = "luawatch"
local branch = "main"

local SW, SH = 410, 502
local mode = "LOCAL" 
local scroll = 0
local msg = "Ready"
local wifi_cfg_path = "/wifi.dat" -- Файл для хранения данных сети
local source_mode = "flash" -- "flash" или "sd"

-- Состояние WiFi
local ssid, pass = "", ""
local target = "ssid"
local last_key, last_time, char_idx = "", 0, 0

-- Файлы
local local_files = {}
local sd_files = {}
local store_files = {}
local selected_idx = 0

--- ### ДОБАВЛЕНО: Работа с SD картой ---
function check_sd()
    if not sd.exists("/") then
        return false, "SD card not mounted"
    end
    return true
end

function scan_sd()
    local ok, err = check_sd()
    if not ok then
        msg = "SD: " .. err
        sd_files = {}
        return
    end
    
    local all = sd.list("/")
    sd_files = {}
    for _, name in ipairs(all) do
        print(name)
        if name:sub(-4) == ".lua" then 
            table.insert(sd_files, name)
        end
    end
    msg = "SD: " .. #sd_files .. " scripts"
end

function scan_local()
    local all = fs.list("/")
    local_files = {}
    for _, name in ipairs(all) do
        if name:sub(-4) == ".lua" and name ~= "main.lua" then 
            table.insert(local_files, name) 
        end
    end
    msg = "Flash: " .. #local_files .. " scripts"
end

function scan_all()
    if mode == "LOCAL" then
        if source_mode == "flash" then
            scan_local()
        else
            scan_sd()
        end
    end
end

function load_script(filename)
    local script_content = ""
    
    if source_mode == "flash" then
        script_content = fs.load("/" .. filename)
    else
        -- Читаем с SD
        local res = sd.readBytes("/" .. filename)
        if type(res) == "table" then
            -- Это ошибка
            msg = "SD read error"
            return nil
        end
        script_content = res
    end
    
    if not script_content then
        msg = "Failed to load script"
        return nil
    end
    
    -- Проверяем, что файл не пустой
    if script_content == "" then
        msg = "Empty script"
        return nil
    end
    
    -- Загружаем и выполняем
    local chunk, load_err = load(script_content, filename, "t")
    if not chunk then
        msg = "Load error: " .. (load_err or "unknown")
        return nil
    end
    
    return chunk
end

function run_selected_script()
    if selected_idx == 0 then
        msg = "No script selected"
        return
    end
    
    local filename = ""
    if source_mode == "flash" then
        if selected_idx > #local_files then return end
        filename = local_files[selected_idx]
    else
        if selected_idx > #sd_files then return end
        filename = sd_files[selected_idx]
    end
    
    msg = "Running: " .. filename
    ui.flush() -- Обновляем экран перед запуском
    
    local chunk = load_script(filename)
    if chunk then
        -- Запускаем в защищенном режиме
        local success, run_err = pcall(chunk)
        if not success then
            msg = "Runtime error: " .. (run_err or "unknown")
        else
            msg = "Script finished"
        end
    end
end
-----------------------------------------

--- ### Логика автоподключения ---
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

-- ДОБАВЛЕНО: Загрузка скрипта с выбором места сохранения
function download_script(item)
    local r = net.get("https://raw.githubusercontent.com/"..user.."/"..repo.."/"..branch.."/"..item.file)
    if r.ok then
        -- Спрашиваем куда сохранить
        msg = "Save to: [F]lash or [S]D?"
        ui.flush()
        
        -- В реальности здесь нужно сделать выбор через интерфейс
        -- Для простоты сохраняем в оба места
        fs.save("/"..item.file, r.body)
        
        local sd_ok, sd_err = check_sd()
        if sd_ok then
            sd.append("/"..item.file, r.body)
            msg = "Saved to both!"
        else
            msg = "Saved to flash only"
        end
    else 
        msg = "Download failed" 
    end
end

-- Инициализация при старте
scan_local()
scan_sd() -- Сканируем SD карту при старте
load_and_connect_wifi() -- Пробуем подключиться автоматически

function draw()
    ui.rect(0, 0, SW, SH, 0)
    
    -- Шапка
    ui.rect(0, 0, SW, 60, 0x2104)
    ui.text(20, 15, mode, 3, 0xFFFF)
    
    if mode == "LOCAL" then
        -- ДОБАВЛЕНО: Переключатель источника
        if ui.button(150, 10, 100, 40, source_mode:upper(), 0x001F) then
            if source_mode == "flash" then
                source_mode = "sd"
                scan_sd()
            else
                source_mode = "flash"
                scan_local()
            end
            selected_idx = 0
            scroll = 0
        end
    end
    
    -- Вкладки
    if ui.button(10, 70, 120, 40, "LOCAL", mode == "LOCAL" and 0x001F or 0x4208) then 
        mode = "LOCAL"
        scan_all()
    end
    if ui.button(135, 70, 120, 40, "STORE", mode == "STORE" and 0x001F or 0x4208) then 
        mode = "STORE"
        refresh_store()
    end
    if ui.button(260, 70, 120, 40, "WIFI", mode == "WIFI" and 0x001F or 0x4208) then 
        mode = "WIFI" 
    end

    ui.text(20, 115, msg, 1, 0xCE79)

    if mode == "LOCAL" then
        local file_list = (source_mode == "flash") and local_files or sd_files
        
        if #file_list == 0 then
            ui.text(20, 140, "No scripts found", 2, 0xF800)
            ui.text(20, 170, "Source: " .. source_mode, 1, 0xFFFF)
        else
            scroll = ui.beginList(10, 140, 390, 260, scroll, #file_list * 55)
            for i, name in ipairs(file_list) do
                local col = (selected_idx == i) and 0x0510 or 0x2104
                if ui.button(0, (i-1)*55, 350, 45, name, col) then 
                    selected_idx = i 
                end
            end
            ui.endList()
        end
        
    elseif mode == "STORE" then
        scroll = ui.beginList(10, 140, 390, 260, scroll, #store_files * 80)
        for i, item in ipairs(store_files) do
            local y = (i-1)*80
            ui.rect(0, y, 380, 75, 0x1082)
            ui.text(10, y+10, item.name, 2, 0xFFFF)
            ui.text(10, y+40, item.desc, 1, 0xCE79)
            if ui.button(280, y+15, 90, 45, "GET", 0x07E0) then
                download_script(item)
                scan_all() -- Обновляем список после загрузки
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
        
        -- Статус WiFi
        local status = net.status()
        if status == 3 then 
            msg = "Online: " .. net.getIP()
            ui.text(20, 300, "RSSI: " .. net.getRSSI() .. " dBm", 1, 0x07E0)
        elseif status == 6 then
            msg = "Connecting..."
        else
            msg = "Disconnected"
        end
        
        -- Клавиатура
        for i, k in ipairs(keys) do
            local r, c = math.floor((i-1)/3), (i-1)%3
            if ui.button(20 + c*125, 340 + r*35, 115, 32, k, 0x2104) then
                if k == "DEL" then 
                    if target == "ssid" then ssid = ssid:sub(1,-2) else pass = pass:sub(1,-2) end
                elseif k == "CLR" then 
                    if target == "ssid" then ssid = "" else pass = "" end
                elseif k == "OK" then 
                    target = "" 
                else 
                    handle_t9(k) 
                end
            end
        end
    end

    -- Нижняя панель
    ui.rect(0, 460, SW, 42, 0x2104)
    
    if mode == "LOCAL" and selected_idx > 0 then
        local file_list = (source_mode == "flash") and local_files or sd_files
        
        if selected_idx <= #file_list then
            -- Кнопка RUN
            if ui.button(20, 465, 100, 32, "RUN", 0x07E0) then
                run_selected_script()
            end
            
            -- Кнопка INFO
            if ui.button(130, 465, 100, 32, "INFO", 0x6318) then
                local filename = file_list[selected_idx]
                local size = 0
                if source_mode == "flash" then
                    size = fs.size("/" .. filename) or 0
                else
                    size = sd.size("/" .. filename) or 0
                end
                msg = filename .. " (" .. size .. " bytes)"
            end
        end
    end
    
    -- Кнопка REFRESH для LOCAL
    if mode == "LOCAL" then
        if ui.button(240, 465, 100, 32, "REFRESH", 0x4208) then
            scan_all()
        end
    end
    
    -- Кнопка REBOOT
    if ui.button(300, 465, 90, 32, "REBOOT", 0xF800) then 
        hw.reboot() 
    end
end

-- ДОБАВЛЕНО: Обновление списка файлов периодически
local last_scan_time = 0
function loop()
    local now = hw.millis()
    if now - last_scan_time > 5000 then -- Каждые 5 секунд
        if mode == "LOCAL" then
            scan_all()
        end
        last_scan_time = now
    end
end

-- Автоматический запуск при загрузке
if not _G._BOOTED then
    _G._BOOTED = true
    -- Можно добавить автозапуск скрипта с SD если есть
    local sd_ok = check_sd()
    if sd_ok then
        -- Проверяем наличие autorun.lua на SD
        if sd.exists("/autorun.lua") then
            msg = "Found autorun.lua on SD"
            local chunk = load_script("autorun.lua")
            if chunk then
                local success, err = pcall(chunk)
                if not success then
                    msg = "Autorun error: " .. (err or "unknown")
                end
            end
        end
    end
end
