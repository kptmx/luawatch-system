local SCR_W, SCR_H = 410, 502
local CONTENT_H = SCR_H * 2 -- Общая высота (панель + циферблат)

-- Начинаем со скролла 502 (показываем нижнюю часть — циферблат)
local scroll_y = SCR_H 
local brightness = 0.5

function draw()
    -- Весь экран становится областью прокрутки
    -- scroll_y обновляется автоматически при свайпах
    scroll_y = ui.beginList(0, 0, SCR_W, SCR_H, scroll_y, CONTENT_H)

    ---------------------------------------------------------
    -- 1. ВЕРХНЯЯ ЧАСТЬ: ЦЕНТР УПРАВЛЕНИЯ (0...501)
    ---------------------------------------------------------
    ui.rect(0, 0, SCR_W, SCR_H, 0x18C3) -- Фон панели
    ui.text(100, 50, "SETTINGS", 3, 0xFFFF)
    
    ui.text(40, 150, "Brightness", 2, 0xFFFF)
    brightness = ui.slider(40, 200, 330, 50, brightness, 0x4208, 0xFFFF)
    
    if ui.button(100, 300, 210, 80, "REBOOT", 0xF800) then
        hw.reboot()
    end
    
    -- Подсказка внизу панели
    ui.text(140, 450, "Pull up to close", 1, 0x7BEF)

    ---------------------------------------------------------
    -- 2. НИЖНЯЯ ЧАСТЬ: ЦИФЕРБЛАТ (502...1003)
    ---------------------------------------------------------
    -- Рисуем фон для нижней части (сдвиг SCR_H)
    ui.rect(0, SCR_H, SCR_W, SCR_H, 0x0000)
    
    local time = hw.getTime()
    local timeStr = string.format("%02d:%02d", time.h, time.m)
    
    -- Текст рисуется по координатам относительно начала списка
    ui.text(75, SCR_H + 180, timeStr, 7, 0xFFFF)
    ui.text(150, SCR_H + 280, "Battery: " .. hw.getBatt() .. "%", 2, 0x07E0)
    
    -- Декоративная полоска-подсказка сверху циферблата
    ui.rect(170, SCR_H + 10, 70, 4, 0x7BEF)

    ui.endList()
end
