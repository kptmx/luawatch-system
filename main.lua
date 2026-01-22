-- Константы оформления
local COLOR = {
    BG = 0,
    ACCENT = 0x07E0, -- Зеленый
    TEXT = 0xFFFF,   -- Белый
    GRAY = 0x8410,
    RED = 0xF800
}

-- Состояние приложения
local state = "watch" -- "watch" или "menu"
local scrollY = 0
local last_weather_update = -600000 -- 10 минут назад
local weather_temp = "--"
local weather_desc = "No Data"

-- Настройки (можно сохранять в FS)
local brightness = 200
local city = "London" -- Для API

-- Вспомогательная функция для получения времени
function get_time_str()
    local t = hw.getTime()
    return string.format("%02d:%02d", t.h, t.m)
end

-- Функция загрузки погоды (используем бесплатный API без ключа для примера)
-- В реальном проекте лучше использовать OpenWeatherMap с ключом
function update_weather()
    if net.status() == 3 then -- WL_CONNECTED
        local url = "http://wttr.in/" .. city .. "?format=%t+%C"
        local data = net.get(url)
        if data then
            weather_temp = data
            last_weather_update = hw.millis()
        end
    end
end

-- ЭКРАН 1: ЦИФЕРБЛАТ
function draw_watch()
    -- Большие часы в центре
    ui.text(60, 150, get_time_str(), 10, COLOR.ACCENT)
    
    -- Дата и Батарея
    local batt = hw.getBatt()
    ui.text(130, 260, "BATTERY: " .. batt .. "%", 2, batt < 20 and COLOR.RED or COLOR.GRAY)
    
    -- Виджет погоды
    ui.rect(40, 320, 330, 80, 0x2104)
    ui.text(60, 340, "WEATHER", 1, COLOR.GRAY)
    ui.text(60, 360, weather_temp, 3, COLOR.TEXT)
    
    -- Кнопка перехода в меню
    if ui.button(155, 430, 100, 40, "MENU", COLOR.GRAY) then
        state = "menu"
    end
    
    -- Фоновое обновление погоды каждые 10 минут
    if hw.millis() - last_weather_update > 600000 then
        update_weather()
    end
end

-- ЭКРАН 2: МЕНЮ НАСТРОЕК
function draw_menu()
    ui.text(20, 20, "SETTINGS", 3, COLOR.ACCENT)
    
    scrollY = ui.beginList(0, 70, 410, 432, scrollY, 600)
    
    -- Слайдер яркости
    ui.text(20, 10, "Brightness", 2, COLOR.TEXT)
    local new_bright = ui.slider(20, 40, 370, 40, brightness / 255, COLOR.GRAY, COLOR.ACCENT)
    if math.floor(new_bright * 255) ~= brightness then
        brightness = math.floor(new_bright * 255)
        hw.setBright(brightness)
    end
    
    -- Информация о WiFi
    ui.rect(20, 110, 370, 80, 0x1082)
    ui.text(35, 125, "WiFi Status:", 1, COLOR.GRAY)
    local status = net.status()
    if status == 3 then
        ui.text(35, 145, "ONLINE", 2, COLOR.ACCENT)
        ui.text(35, 165, net.getIP(), 1, COLOR.TEXT)
    else
        ui.text(35, 145, "OFFLINE", 2, COLOR.RED)
    end
    
    -- Кнопки действий
    if ui.button(20, 210, 370, 50, "FORCE WEATHER UPDATE", 0x3186) then
        update_weather()
    end
    
    if ui.button(20, 270, 370, 50, "REBOOT TO BOOTSTRAP", COLOR.RED) then
        -- Удаляем main.lua или просто зажимаем кнопку при старте
        -- Для простоты тут просто перезагрузка, если вы зажмете BOOT
        hw.reboot()
    end

    if ui.button(20, 330, 370, 50, "BACK TO WATCH", COLOR.GRAY) then
        state = "watch"
    end
    
    ui.endList()
end

-- Главная функция отрисовки (вызывается из C++)
function draw()
    ui.rect(0, 0, 410, 502, COLOR.BG) -- Очистка кадра
    
    if state == "watch" then
        draw_watch()
    elseif state == "menu" then
        draw_menu()
    end
end
