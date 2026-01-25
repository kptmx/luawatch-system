-- ЦИФЕРБЛАТ С ЦЕНТРОМ УПРАВЛЕНИЯ
-- Открывается свайпом с верхнего края экрана

local SCR_W, SCR_H = 410, 502

-- Состояния
local state = {
    mode = "watch", -- "watch" или "control"
    swipeStartY = 0,
    panelY = -SCR_H, -- начальное положение панели
    lastUpdate = 0,
    
    -- Параметры для анимаций
    panelTargetY = -SCR_H,
    animationSpeed = 0.3,
    
    -- Настройки
    brightness = 80,
    volume = 50,
    wifiEnabled = true,
    bluetooth = false,
    
    -- Время
    hour = 12,
    minute = 0,
    second = 0,
    day = 1,
    month = "Jan"
}

-- Инициализация
function init()
    -- Загружаем текущее время из аппаратных часов
    local timeData = hw.getTime()
    if timeData and timeData.h and timeData.m then
        state.hour = timeData.h
        state.minute = timeData.m
    end
    
    -- Если есть сеть, можно получить точное время
    -- (здесь просто пример)
    state.lastUpdate = hw.millis()
end

-- Обновление времени
function updateTime()
    local now = hw.millis()
    if now - state.lastUpdate >= 1000 then
        state.second = state.second + 1
        state.lastUpdate = now
        
        if state.second >= 60 then
            state.second = 0
            state.minute = state.minute + 1
            
            if state.minute >= 60 then
                state.minute = 0
                state.hour = state.hour + 1
                
                if state.hour >= 24 then
                    state.hour = 0
                    state.day = state.day + 1
                end
            end
        end
    end
end

-- Рисуем циферблат
function drawWatch()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000) -- черный фон
    
    -- Центральные часы (большие цифры)
    local timeStr = string.format("%02d:%02d", state.hour, state.minute)
    ui.text(SCR_W/2 - 70, SCR_H/2 - 40, timeStr, 6, 0xFFFF)
    
    -- Секунды (поменьше)
    local secStr = string.format("%02d", state.second)
    ui.text(SCR_W/2 + 90, SCR_H/2 - 10, secStr, 3, 0x7BEF)
    
    -- Дата
    local dateStr = string.format("%d %s", state.day, state.month)
    ui.text(SCR_W/2 - 40, SCR_H/2 + 50, dateStr, 3, 0xFFFF)
    
    -- Батарея
    local batt = hw.getBatt() or 75
    local battStr = string.format("%d%%", batt)
    ui.text(20, 20, battStr, 2, 0xFFFF)
    
    -- Индикатор свайпа сверху
    ui.rect(SCR_W/2 - 30, 5, 60, 3, 0x7BEF)
    
    -- Подсказка внизу
    ui.text(SCR_W/2 - 60, SCR_H - 40, "Swipe down to open", 2, 0x528A)
end

-- Рисуем панель управления
function drawControlPanel()
    -- Полупрозрачный фон
    for y = 0, SCR_H, 4 do
        for x = 0, SCR_W, 4 do
            ui.rect(x, y, 2, 2, 0x1082) -- сетчатый фон
        end
    end
    
    -- Панель управления
    local panelH = SCR_H * 0.8
    ui.rect(0, state.panelY, SCR_W, panelH, 0x0000)
    
    -- Закругленные углы сверху
    ui.rect(0, state.panelY + 10, SCR_W, panelH - 10, 0x0000)
    
    -- "Ручка" для закрытия
    ui.rect(SCR_W/2 - 30, state.panelY + 5, 60, 4, 0x7BEF)
    
    -- Заголовок
    ui.text(SCR_W/2 - 50, state.panelY + 30, "Control Center", 3, 0xFFFF)
    
    -- Разделительная линия
    ui.rect(20, state.panelY + 70, SCR_W - 40, 2, 0x3186)
    
    local startY = state.panelY + 90
    
    -- 1. Яркость
    ui.text(30, startY, "Brightness", 2, 0xFFFF)
    local newBright = ui.slider(140, startY - 5, 200, 30, 
                               state.brightness/100, 0x4A69, 0xF800)
    state.brightness = math.floor(newBright * 100)
    
    -- 2. Громкость
    ui.text(30, startY + 50, "Volume", 2, 0xFFFF)
    local newVol = ui.slider(140, startY + 45, 200, 30, 
                            state.volume/100, 0x4A69, 0x07E0)
    state.volume = math.floor(newVol * 100)
    
    -- 3. Wi-Fi переключатель
    ui.text(30, startY + 100, "Wi-Fi", 2, 0xFFFF)
    local wifiText = state.wifiEnabled and "ON" or "OFF"
    local wifiColor = state.wifiEnabled and 0x07E0 or 0xF800
    
    if ui.button(140, startY + 95, 80, 30, wifiText, wifiColor) then
        state.wifiEnabled = not state.wifiEnabled
    end
    
    -- 4. Bluetooth
    ui.text(30, startY + 150, "Bluetooth", 2, 0xFFFF)
    local btText = state.bluetooth and "ON" or "OFF"
    local btColor = state.bluetooth and 0x001F or 0x7BEF
    
    if ui.button(140, startY + 145, 80, 30, btText, btColor) then
        state.bluetooth = not state.bluetooth
    end
    
    -- 5. Кнопки быстрого доступа
    local btnY = startY + 200
    if ui.button(30, btnY, 80, 40, "Flash", 0xFFE0) then
        -- Включить фонарик (заглушка)
    end
    
    if ui.button(130, btnY, 80, 40, "Music", 0x87FF) then
        -- Открыть музыку (заглушка)
    end
    
    if ui.button(230, btnY, 80, 40, "Wi-Fi", 0x051F) then
        -- Настройки Wi-Fi (заглушка)
    end
    
    if ui.button(30, btnY + 60, 120, 40, "Reboot", 0xF800) then
        hw.reboot()
    end
    
    if ui.button(170, btnY + 60, 140, 40, "Close Panel", 0x7BEF) then
        state.mode = "watch"
        state.panelTargetY = -SCR_H
    end
    
    -- Статусы
    local statusY = btnY + 120
    local netStatus = net.status()
    local netText = (netStatus == 3) and "Online" or "Offline"
    local netColor = (netStatus == 3) and 0x07E0 or 0xF800
    
    ui.text(30, statusY, "Network: " .. netText, 2, netColor)
    
    local freeMem = hw.getFreePsram() or 0
    ui.text(30, statusY + 25, string.format("Free PSRAM: %d KB", freeMem/1024), 1, 0xFFFF)
end

-- Обработка свайпов
function handleSwipes()
    local touch = ui.getTouch()
    
    if touch.touching then
        -- Если касание началось у верхнего края (первые 20 пикселей)
        if touch.y < 20 and state.mode == "watch" then
            state.swipeStartY = touch.y
        end
        
        -- Если тянем вниз от верхнего края
        if state.swipeStartY > 0 then
            local dragDistance = touch.y - state.swipeStartY
            
            if dragDistance > 50 then -- сработал свайп вниз
                state.mode = "control"
                state.panelTargetY = 0
                state.swipeStartY = 0
            end
        end
    else
        state.swipeStartY = 0
    end
    
    -- Анимация панели
    if math.abs(state.panelY - state.panelTargetY) > 1 then
        state.panelY = state.panelY + (state.panelTargetY - state.panelY) * state.animationSpeed
    else
        state.panelY = state.panelTargetY
    end
end

-- Главная функция отрисовки
function draw()
    updateTime()
    handleSwipes()
    
    -- Всегда рисуем циферблат на заднем плане
    drawWatch()
    
    -- Поверх рисуем панель управления (если она видима)
    if state.mode == "control" then
        drawControlPanel()
    end
end

-- Инициализируем при запуске
init()
