-- Настройки репозитория
local user = "kptmx"
local repo = "luawatch-system"
local branch = "main"

local SW, SH = 410, 502
local mode = "LOCAL" -- LOCAL или STORE
local scroll = 0
local msg = "Ready"

local local_files = {}
local store_files = {} -- Сюда загрузим список из JSON
local selected_idx = 0

-- Сканирование локальных файлов
function scan_local()
    local all = fs.list("/")
    local_files = {}
    for _, name in ipairs(all) do
        if name:sub(-4) == ".lua" then table.insert(local_files, name) end
    end
    mode = "LOCAL"
    selected_idx = 0
end

-- Загрузка каталога из GitHub
function refresh_store()
    msg = "Loading catalog..."
    local url = "https://raw.githubusercontent.com/"..user.."/"..repo.."/"..branch.."/scripts.json"
    local res = net.get(url)
    
    if res and res.ok and res.code == 200 then
        -- Простейший парсинг JSON (ищем поля name, file, desc через регулярки)
        store_files = {}
        for item in res.body:gmatch("{(.-)}") do
            local name = item:match('"name"%s*:%s*"(.-)"')
            local file = item:match('"file"%s*:%s*"(.-)"')
            local desc = item:match('"desc"%s*:%s*"(.-)"')
            if name and file then
                table.insert(store_files, {name=name, file=file, desc=desc or ""})
            end
        end
        msg = "Found " .. #store_files .. " scripts"
        mode = "STORE"
    else
        msg = "Catalog error: " .. (res.code or "off")
    end
end

scan_local()

function draw()
    ui.rect(0, 0, SW, SH, 0)
    
    -- Header
    ui.rect(0, 0, SW, 60, 0x2104)
    ui.text(20, 15, mode == "LOCAL" and "MY SCRIPTS" or "CLOUD STORE", 3, 0xFFFF)
    
    -- Tabs
    if ui.button(20, 70, 180, 40, "LOCAL", mode == "LOCAL" and 0x001F or 0x4208) then scan_local() end
    if ui.button(210, 70, 180, 40, "STORE", mode == "STORE" and 0x001F or 0x4208) then refresh_store() end

    ui.text(20, 115, msg, 1, 0xCE79)

    -- Content Area
    if mode == "LOCAL" then
        scroll = ui.beginList(10, 140, 390, 260, scroll, #local_files * 55)
        for i, name in ipairs(local_files) do
            local col = (selected_idx == i) and 0x0510 or 0x2104
            if ui.button(0, (i-1)*55, 300, 45, name, col) then selected_idx = i end
        end
        ui.endList()
    else
        scroll = ui.beginList(10, 140, 390, 260, scroll, #store_files * 80)
        for i, item in ipairs(store_files) do
            local y = (i-1)*80
            ui.rect(0, y, 380, 75, 0x1082)
            ui.text(10, y+10, item.name, 2, 0xFFFF)
            ui.text(10, y+40, item.desc, 1, 0xBDD7)
            
            if ui.button(280, y+15, 90, 45, "GET", 0x07E0) then
                msg = "Downloading " .. item.file
                local r = net.get("https://raw.githubusercontent.com/"..user.."/"..repo.."/"..branch.."/"..item.file)
                if r.ok then 
                    fs.save("/"..item.file, r.body)
                    msg = "Installed: " .. item.name
                else msg = "Fail" end
            end
        end
        ui.endList()
    end

    -- Bottom Bar
    ui.rect(0, 410, SW, 92, 0x2104)
    if mode == "LOCAL" and selected_idx > 0 then
        if ui.button(20, 430, 120, 50, "RUN", 0x07E0) then
            local code = fs.load("/"..local_files[selected_idx])
            local f = load(code)
            if f then f() end
        end
        if ui.button(150, 430, 120, 50, "DELETE", 0xF800) then
            fs.remove("/"..local_files[selected_idx])
            scan_local()
        end
    end
    if ui.button(300, 430, 90, 50, "EXIT", 0x4208) then hw.reboot() end
end
