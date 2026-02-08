-- minimal_browser.lua
-- Первая рабочая версия: ввод URL → загрузка → показ текста

local SW = 410
local SH = 502

-- Состояния
local url = "http://neverssl.com"
local content = "Нажмите на строку сверху, чтобы ввести адрес"
local input_active = false
local input_buffer = ""
local status_msg = "Готов"

local function redraw()
    ui.rect(0, 0, SW, SH, 0x000000)           -- фон чёрный

    -- Верхняя панель (URL + статус)
    ui.rect(0, 0, SW, 60, 0x111133)
    ui.text(12, 12, url, 2, 0xAAAAAA)
    ui.text(12, 38, status_msg, 1, 0x88FF88)

    -- Основная область
    ui.rect(0, 60, SW, SH-90, 0x000022)

    local y = 70
    for line in content:gmatch("[^\r\n]+") do
        if y < SH - 100 then
            ui.text(12, y, line:sub(1,45), 1, 0xDDDDDD)
            y = y + 18
        end
    end

    -- Нижняя панель с кнопками
    ui.rect(0, SH-80, SW, 80, 0x222244)

    ui.rect(20,  SH-70, 100, 50, input_active and 0x336633 or 0x444488)
    ui.text(35,  SH-55, "URL", 2, 0xFFFFFF)

    ui.rect(150, SH-70, 100, 50, 0x444488)
    ui.text(165, SH-55, "GO",  2, 0xFFFFFF)

    ui.rect(280, SH-70, 100, 50, 0x444488)
    ui.text(290, SH-55, "EXIT",2, 0xFF8888)

    ui.flush()
end

-- ────────────────────────────────────────────────
--   Главный цикл
-- ────────────────────────────────────────────────

local running = true

while running do

    local touch = ui.getTouch()

    if touch.released then

        local tx, ty = touch.x, touch.y

        -- Нажали на верхнюю панель → начинаем ввод адреса
        if ty < 60 then
            input_active = true
            input_buffer = url
            status_msg = "Введите адрес... (пока только T9 нет)"
        end

        -- Кнопка URL (левая)
        if ty > SH-70 and ty < SH-20 and tx > 20 and tx < 120 then
            input_active = true
            input_buffer = url
            status_msg = "Редактирование адреса"
        end

        -- Кнопка GO
        if ty > SH-70 and ty < SH-20 and tx > 150 and tx < 250 then
            if input_active then
                url = input_buffer
            end

            input_active = false
            status_msg = "Загрузка..."

            redraw()  -- показываем "Загрузка..." сразу

            local resp = net.get(url)

            if resp.ok and resp.body then
                content = resp.body
                status_msg = "Загружено (" .. #resp.body .. " байт)"
            else
                content = "Ошибка:\n" ..
                          "code = " .. (resp.code or "?") .. "\n" ..
                          "err  = " .. (resp.err  or "нет ответа")
                status_msg = "Ошибка загрузки"
            end
        end

        -- Кнопка EXIT
        if ty > SH-70 and ty < SH-20 and tx > 280 and tx < 380 then
            running = false
            status_msg = "Выход..."
        end

    end

    -- Очень простой способ ввода (пока без T9 — только для теста)
    -- В реальности здесь должна быть твоя T9-логика
    if input_active then
        -- Пока имитируем ввод (можно будет заменить на T9)
        -- Для теста: каждый кадр добавляем символ "x" если нажато где-то
        -- (это временно — потом уберём)
        if touch.touching then
            input_buffer = input_buffer .. "x"
            url = input_buffer
        end
    end

    redraw()

    -- Задержка ~30–50 fps, чтобы не грузить процессор
    -- Если есть hw.delay или аналог — используй его
    -- Пока просто пустой цикл (батарея будет садиться быстрее)
end

-- Когда вышли из цикла — можно что-то вывести в лаунчер
msg = "Браузер закрыт"
