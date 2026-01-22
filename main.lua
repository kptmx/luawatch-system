-- main.lua (или test.lua для экспериментов)

SCR_W, SCR_H = 410, 502

-- состояние
mode = "wifi"          -- "wifi" / "menu" / "image"
ssid, pass = "", ""
target = "ssid"        -- "ssid" или "pass"
msg = "Enter WiFi & Download test.png"

downloaded = false
image_x, image_y = 0, 0   -- для простого просмотра, можно двигать если нужно

-- T9 таблица (как в bootstrap)
local t9 = {
    [".,!1"]=".,!1", ["abc2"]="abc2", ["def3"]="def3",
    ["ghi4"]="ghi4", ["jkl5"]="jkl5", ["mno6"]="mno6",
    ["pqrs7"]="pqrs7", ["tuv8"]="tuv8", ["wxyz9"]="wxyz9",
    ["*"]="-+=", ["0"]=" ", ["#"]="#"
}
local keys = {".,!1","abc2","def3","ghi4","jkl5","mno6","pqrs7","tuv8","wxyz9","*","0","#","DEL","CLR","OK"}

last_key, last_time, char_idx = "", 0, 0

function handle_t9(k)
    local now = hw.millis()
    local chars = t9[k]
    if not chars then return end

    local val = (target == "ssid") and ssid or pass

    if k == last_key and (now - last_time) < 800 then
        -- повтор → меняем символ
        if #val > 0 then
            val = val:sub(1, -2)
        end
        char_idx = (char_idx % #chars) + 1
    else
        char_idx = 1
    end

    val = val .. chars:sub(char_idx, char_idx)

    if target == "ssid" then ssid = val else pass = val end
    last_key, last_time = k, now
end

function download_test_png()
    msg = "Downloading test.jpg..."
    local url = "https://raw.githubusercontent.com/kptmx/luawatch-system/main/test.jpg"

    local res = net.get(url)
    if res and res.ok and res.code == 200 then
        local ok = fs.save("/test.png", res.body)
        if ok then
            msg = "Downloaded & saved!"
            downloaded = true
        else
            msg = "Save failed!"
        end
    else
        msg = "Download failed (" .. (res and res.code or "no conn") .. ")"
    end
end

function draw_wifi_screen()
    ui.rect(0, 0, SCR_W, SCR_H, 0)  -- очистка чёрным

    ui.text(20, 20, "WiFi + PNG Demo", 3, 0x07E0)  -- зелёный

    local status = net.status()
    if status == 3 then
        ui.text(20, 60, "Connected: " .. net.getIP(), 2, 0x07E0)
    else
        ui.text(20, 60, msg, 2, 0xFFFF)
    end

    -- поля ввода (кликабельные)
    if ui.input(20, 100, 370, 45, "SSID: " .. ssid, target == "ssid") then
        target = "ssid"
    end

    if ui.input(20, 155, 370, 45, "PASS: " .. pass, target == "pass") then
        target = "pass"
    end

    -- кнопки
    if ui.button(20, 215, 180, 50, "CONNECT", 0x001F) then   -- синий
        net.connect(ssid, pass)
        msg = "Connecting..."
    end

    if ui.button(210, 215, 180, 50, "DOWNLOAD PNG", 0xF800) then  -- красный
        if status == 3 then
            download_test_png()
        else
            msg = "Connect to WiFi first!"
        end
    end

    -- T9 клавиатура
    for i, k in ipairs(keys) do
        local r = math.floor((i-1)/3)
        local c = (i-1)%3
        local bx, by = 20 + c*125, 280 + r*45
        if ui.button(bx, by, 115, 40, k, 0x4208) then
            if k == "DEL" then
                if target == "ssid" and #ssid > 0 then ssid = ssid:sub(1,-2) end
                if target == "pass" and #pass > 0 then pass = pass:sub(1,-2) end
            elseif k == "CLR" then
                if target == "ssid" then ssid = "" end
                if target == "pass" then pass = "" end
            elseif k == "OK" then
                target = ""
            else
                handle_t9(k)
            end
        end
    end
end

function draw_menu()
    ui.rect(0, 0, SCR_W, SCR_H, 0)
    ui.text(30, 40, "Download OK!", 4, 0x07E0)

    ui.text(30, 120, "File: /test.jpg", 2, 0xFFFF)

    if ui.button(50, 220, 300, 60, "SHOW IMAGE", 0x07E0) then
        mode = "image"
    end

    if ui.button(50, 320, 300, 60, "Back to WiFi", 0x001F) then
        mode = "wifi"
    end
end

function draw_image()
    ui.rect(0, 0, SCR_W, SCR_H, 0)

    -- рисуем картинку (центрируем примерно)
    local ok = ui.drawJPG( (SCR_W-320)/2, (SCR_H-240)/2, "/test.jpg" )

    if not ok then
        ui.text(40, 200, "Failed to load /test.jpg", 3, 0xF800)
    end

    -- кнопка назад
    if ui.button(20, SCR_H-80, 120, 50, "BACK", 0xF800) then
        mode = "menu"
    end
end

function draw()
    if mode == "wifi" then
        draw_wifi_screen()
    elseif mode == "menu" then
        draw_menu()
    elseif mode == "image" then
        draw_image()
    end
end
