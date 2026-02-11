-- Константы экрана и чистки
local SCR_W, SCR_H = 410, 502
local LIST_X, LIST_Y = 5, 65
local LIST_W, LIST_H = 400, 375
local PAGE_H = LIST_H -- Высота одной "страницы" текста

-- Состояние приложения
local state = "browser" -- "browser" или "reader"
local full_text = ""
local pages = {}
local current_page_idx = 1
local scroll_y = PAGE_H -- Начинаем с центра (вторая страница)
local is_moving = false

-- Файловый браузер
local files = {}
local current_path = "/"
local storage = "fs" -- или "sd"

function load_file_list(path, type)
    storage = type
    current_path = path
    local res = (type == "sd") and sd.list(path) or fs.list(path)
    files = res or {}
end

-- Разбивка текста на страницы (упрощенно по строкам)
function paginate(text)
    pages = {}
    local lines_per_page = 15 -- Настрой под размер шрифта
    local current_line = 0
    local page_content = ""
    
    for line in text:gmatch("[^\r\n]+") do
        page_content = page_content .. line .. "\n"
        current_line = current_line + 1
        if current_line >= lines_per_page then
            table.insert(pages, page_content)
            page_content = ""
            current_line = 0
        end
    end
    if page_content ~= "" then table.insert(pages, page_content) end
end

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)
    
    if state == "browser" then
        ui.text(20, 20, "File Browser ("..storage..")", 2, 0x07E0)
        
        if ui.button(300, 15, 90, 35, storage == "fs" and "to SD" or "to FS", 0x3186) then
            load_file_list("/", storage == "fs" and "sd" or "fs")
        end

        local total_h = #files * 50
        local browser_scroll = ui.beginList(LIST_X, LIST_Y, LIST_W, LIST_H, browser_scroll or 0, total_h)
        for i, f in ipairs(files) do
            if ui.button(10, (i-1)*50, 360, 45, f, 0x2104) then
                local content = (storage == "sd") and sd.readBytes(current_path .. f) or fs.load(current_path .. f)
                if content then
                    full_text = content
                    paginate(full_text)
                    current_page_idx = 1
                    scroll_y = PAGE_H -- Центрируем
                    state = "reader"
                end
            end
        end
        ui.endList()

    elseif state == "reader" then
        ui.text(20, 20, "Reader: " .. current_page_idx .. "/" .. #pages, 2, 0x07FF)
        if ui.button(330, 15, 70, 35, "Back", 0x6000) then state = "browser" end

        -- Виртуальный скролл (три страницы высотой PAGE_H)
        -- Общая высота контента = PAGE_H * 3
        local new_scroll = ui.beginList(LIST_X, LIST_Y, LIST_W, LIST_H, scroll_y, PAGE_H * 3)
        
        -- Отрисовка трех сегментов
        for i = -1, 1 do
            local p_idx = current_page_idx + i
            local py = (i + 1) * PAGE_H
            if pages[p_idx] then
                ui.text(10, py + 10, pages[p_idx], 2, 0xFFFF)
            else
                ui.text(10, py + 10, "--- Конец файла ---", 2, 0x4208)
            end
        end
        
        -- Логика переключения страниц
        local touch = ui.getTouch()
        if not touch.touching then
            -- Если пользователь отпустил экран, проверяем, куда сместился скролл
            if new_scroll < PAGE_H * 0.5 and current_page_idx > 1 then
                current_page_idx = current_page_idx - 1
                new_scroll = PAGE_H -- Мгновенный возврат в центр
            elseif new_scroll > PAGE_H * 1.5 and current_page_idx < #pages then
                current_page_idx = current_page_idx + 1
                new_scroll = PAGE_H -- Мгновенный возврат в центр
            elseif math.abs(new_scroll - PAGE_H) > 10 then
                -- Доводчик к центру (плавность обеспечивается инерцией из C++)
                new_scroll = PAGE_H 
            end
        end

        scroll_y = new_scroll
        ui.endList()
    end
end

-- Инициализация при запуске
load_file_list("/", "fs")
