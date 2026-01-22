-- Константы экрана
SCR_W, SCR_H = 410, 502

-- Состояние системы
brightness = 0.8
selected_tab = "Home"
scroll_y = 0

-- Цвета (RGB565)
COLOR_BG = 0x0000
COLOR_ACCENT = 0x07E0 -- Зеленый
COLOR_TEXT = 0xFFFF
COLOR_CARD = 0x2104

function draw()
    -- 1. Фон
    ui.rect(0, 0, SCR_W, SCR_H, COLOR_BG)

    -- 2. Верхний статус-бар
    ui.rect(0, 0, SCR_W, 30, 0x1082)
    local bat = hw.getBattPct()
    ui.text(SCR_W - 80, 5, bat .. "% BAT", 1, bat < 20 and 0xF800 or 0x07E0)
    
    local t = hw.getTime()
    local time_str = string.format("%02d:%02d", t.h, t.m)
    ui.text(10, 5, time_str, 1, COLOR_TEXT)

    -- 3. Навигация (Tabs)
    ui.rect(0, 30, SCR_W, 60, 0x0000)
    if ui.button(10, 35, 120, 50, "HOME", selected_tab == "Home" and COLOR_ACCENT or 0x4208) then
        selected_tab = "Home"
    end
    if ui.button(145, 35, 120, 50, "APPS", selected_tab == "Apps" and COLOR_ACCENT or 0x4208) then
        selected_tab = "Apps"
    end
    if ui.button(280, 35, 120, 50, "SYS", selected_tab == "Sys" and COLOR_ACCENT or 0x4208) then
        selected_tab = "Sys"
    end

    -- 4. Основной контент (Список)
    scroll_y = ui.beginList(10, 100, SCR_W - 20, SCR_H - 110, scroll_y, 800)
        
        if selected_tab == "Home" then
            -- Виджет Больших Часов
            ui.rect(10, 10, 370, 120, COLOR_CARD)
            ui.text(80, 35, time_str, 5, COLOR_ACCENT)
            ui.text(120, 95, "Thursday, Jan 22", 2, 0x8410)

            -- Слайдер яркости
            ui.text(10, 150, "Display Brightness", 2, COLOR_TEXT)
            brightness = ui.slider(10, 180, 370, 50, brightness, 0x4208, COLOR_ACCENT)
            -- Применяем яркость (если есть биндинг)
            -- hw.setBrightness(brightness * 255)

        elseif selected_tab == "Apps" then
            -- Сетка приложений (заглушки)
            local apps = {"Weather", "Music", "Calc", "Maps", "News", "Health"}
            for i, app in ipairs(apps) do
                local r, c = math.floor((i-1)/2), (i-1)%2
                if ui.button(10 + c*185, 10 + r*90, 175, 80, app, 0x3186) then
                    -- Логика запуска
                end
            end

        elseif selected_tab == "Sys" then
            ui.text(10, 10, "SYSTEM INFO", 2, COLOR_ACCENT)
            ui.rect(10, 40, 370, 2, 0x4208)
            
            ui.text(10, 60, "Firmware: GeminiOS v2.6", 2, 0xFFFF)
            ui.text(10, 90, "WiFi: Connected", 2, 0x07E0)
            ui.text(10, 120, "Storage: LittleFS OK", 2, 0xFFFF)

            if ui.button(10, 200, 370, 60, "CHECK UPDATES", 0xF800) then
                -- Код вызова Bootstrap режима
            end
        end

    ui.endList()
end
