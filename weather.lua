-- Настройки
local lat = "55.75" -- Широта (например, Москва)
local lon = "37.62" -- Долгота
local url = "https://api.open-meteo.com/v1/forecast?latitude="..lat.."&longitude="..lon.."&current_weather=true&daily=temperature_2m_max,temperature_2m_min&timezone=auto"

local SW, SH = 410, 502
local weather = { temp = "--", code = 0, t_max = "--", t_min = "--" }
local msg = "Loading..."
local last_update = 0

-- Массив расшифровки кодов WMO (Weather Interpretation Codes)
local weather_types = {
    [0] = "Clear sky", [1] = "Mainly clear", [2] = "Partly cloudy", [3] = "Overcast",
    [45] = "Fog", [48] = "Depositing rime fog", [51] = "Drizzle", [61] = "Slight rain",
    [71] = "Slight snow", [95] = "Thunderstorm"
}

function update_weather()
    msg = "Updating..."
    local res = net.get(url)
    if res and res.ok and res.code == 200 then
        -- Парсим текущую температуру
        weather.temp = res.body:match('"temperature":%s*([%-?%d%.]+)')
        -- Парсим код погоды
        weather.code = tonumber(res.body:match('"weathercode":%s*(%d+)')) or 0
        -- Парсим макс/мин на сегодня
        weather.t_max = res.body:match('"temperature_2m_max":%s*%[([%-?%d%.]+)')
        weather.t_min = res.body:match('"temperature_2m_min":%s*%[([%-?%d%.]+)')
        
        msg = "Updated at " .. hw.getTime().h .. ":" .. hw.getTime().m
        last_update = hw.millis()
    else
        msg = "Error: " .. (res.code or "timeout")
    end
end

-- Первый запуск
update_weather()

function draw()
    ui.rect(0, 0, SW, SH, 0x0000) -- Фон
    
    -- Заголовок
    ui.text(20, 30, "WEATHER", 3, 0x051F) -- Синий
    ui.text(20, 70, msg, 1, 0x7BEF) -- Серый статус

    -- Центральный блок: Температура
    ui.text(60, 140, weather.temp .. "°C", 8, 0xFFFF)
    
    -- Описание погоды
    local desc = weather_types[weather.code] or "Cloudy"
    ui.text(60, 240, desc, 3, 0xCE79)

    -- Доп. информация
    ui.rect(20, 300, 370, 2, 0x2104) -- Линия-разделитель
    
    ui.text(40, 330, "Max: " .. (weather.t_max or "--") .. "°C", 2, 0xF800)
    ui.text(40, 370, "Min: " .. (weather.t_min or "--") .. "°C", 2, 0x001F)

    -- Кнопки внизу
    if ui.button(20, 430, 180, 50, "REFRESH", 0x4208) then
        update_weather()
    end
    
    if ui.button(210, 430, 180, 50, "BACK", 0x2104) then
        hw.reboot() -- Возврат в лаунчер через ребут или загрузку main.lua
    end

    -- Авто-обновление раз в 15 минут
    if (hw.millis() - last_update) > 900000 then
        update_weather()
    end
end
