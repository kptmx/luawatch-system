-- Константы
local SCR_W, SCR_H = 410, 502
local HEADER_H = 60         -- Высота заголовка
local ITEM_H = 200          -- Высота одного элемента списка
local IMG_PATH = "/test.jpg"
local COUNT = 10            -- Количество копий

-- Переменная для хранения текущей прокрутки
local scroll_y = 0

-- Рассчитываем полную высоту контента
local content_height = COUNT * ITEM_H

function draw()
    -- 1. Очистка фона (черный)
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)

    -- 2. Рисуем заголовок (статичный, не скроллится)
    ui.rect(0, 0, SCR_W, HEADER_H, 0x18E3) -- Темно-серый фон заголовка
    ui.text(20, 20, "SD Card Gallery", 3, 0xFFFF)
    
    -- 3. Начинаем список
    -- Параметры: x, y (начало области), w, h (размер области), текущий скролл, полная высота контента
    -- Функция возвращает новое значение скролла (обработанное инерцией и пальцем)
    scroll_y = ui.beginList(0, HEADER_H, SCR_W, SCR_H - HEADER_H, scroll_y, content_height)

    -- 4. Рисуем элементы
    for i = 0, COUNT - 1 do
        local y = i * ITEM_H -- Виртуальная Y координата элемента
        
        -- Фон карточки
        ui.rect(10, y + 5, SCR_W - 20, ITEM_H - 10, 0x2104) 
        
        -- Текст с номером
        ui.text(20, y + 20, "Image Clone #" .. (i + 1), 2, 0xFFFF)

        -- Изображение с SD карты
        -- Благодаря кэшу, оно загрузится 1 раз, а нарисуется 10 раз
        ui.drawJPEG_SD(20, y + 50, IMG_PATH)
        
        -- Кнопка для теста (например, выгрузить память)
        if ui.button(200, y + 60, 150, 40, "Unload", 0xF800) then
            ui.unload(IMG_PATH) -- Тест функции очистки памяти
        end
    end

    -- 5. Завершаем список (сбрасываем клиппинг)
    ui.endList()
    
    -- Отображаем FPS или отладку (поверх всего)
    ui.text(300, 20, "MEM: " .. math.floor(hw.getFreePsram()/1024) .. "k", 1, 0x07E0)
end
