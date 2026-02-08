-- Простой веб-браузер с ленивой загрузкой изображений
-- Коллбэк обновляет UI напрямую

local SCR_W, SCR_H = 410, 502
local LINE_H = 28
local LINK_H = 36
local IMAGE_H = 120
local MAX_CHARS_PER_LINE = 24

local current_url = "https://www.furtails.pw"
local history, history_pos = {}, 0
local scroll_y = 0
local content, content_height = {}, 0

-- Кэш изображений
local image_cache = {}
local currently_downloading = nil  -- URL текущей загрузки

-- Проверяем, поддерживается ли формат изображения
local function is_supported_image(url)
    if not url then return false end
    return url:match("%.jpg$") or url:match("%.jpeg$") or 
           url:match("%.JPG$") or url:match("%.JPEG$") or
           url:match("%.png$") or url:match("%.PNG$")
end

-- Коллбэк для обновления прогресса (вызывается из net.download)
local function download_progress_callback(loaded, total)
    if not currently_downloading then return true end
    
    local cache_entry = image_cache[currently_downloading]
    if not cache_entry then return true end
    
    -- Обновляем прогресс в кэше
    cache_entry.loaded = loaded
    cache_entry.total = total
    cache_entry.progress = total > 0 and math.floor((loaded / total) * 100) or 0
    
    -- Сразу рисуем обновленный прогресс!
    draw()
    ui.flush()  -- Принудительно обновляем экран
    
    return true  -- Продолжаем загрузку
end

-- Загрузка изображения
local function load_image_to_cache(img_url)
    if not img_url or currently_downloading then return false end
    
    -- Проверяем формат
    if not is_supported_image(img_url) then
        image_cache[img_url] = {
            loaded = false,
            failed = true,
            error = "Unsupported format"
        }
        return false
    end
    
    -- Проверяем, не загружено ли уже
    if image_cache[img_url] and image_cache[img_url].loaded then
        return true
    end
    
    -- Создаем имя файла
    local filename = "img_" .. os.time() .. "_" .. math.random(1000, 9999)
    if img_url:match("%.png$") or img_url:match("%.PNG$") then
        filename = filename .. ".png"
    else
        filename = filename .. ".jpg"
    end
    
    local cache_path = "/cache/" .. filename
    
    -- Инициализируем в кэше
    image_cache[img_url] = {
        loaded = false,
        loading = true,
        failed = false,
        path = cache_path,
        progress = 0,
        loaded = 0,
        total = 0
    }
    
    -- Устанавливаем текущую загрузку
    currently_downloading = img_url
    
    print("Starting download: " .. img_url)
    
    -- Запускаем загрузку С БЛОКИРОВКОЙ
    -- UI будет обновляться через коллбэк
    local success = net.download(img_url, cache_path, "flash", download_progress_callback)
    
    -- Загрузка завершена
    if success then
        image_cache[img_url].loaded = true
        image_cache[img_url].loading = false
        image_cache[img_url].progress = 100
        print("Download completed!")
    else
        image_cache[img_url].failed = true
        image_cache[img_url].loading = false
        image_cache[img_url].error = "Download failed"
        print("Download failed")
        
        if fs.exists(cache_path) then
            fs.remove(cache_path)
        end
    end
    
    currently_downloading = nil
    
    -- Обновляем экран с итоговым состоянием
    draw()
    ui.flush()
    
    return success
end

-- Функция для отрисовки прогресс-бара
local function draw_progress_bar(x, y, width, height, progress, color, bg_color)
    -- Фон
    ui.rect(x, y, width, height, bg_color or 0x4208)
    
    -- Заполненная часть
    local fill_width = math.max(2, math.floor(width * progress / 100))
    if fill_width > 0 then
        ui.rect(x, y, fill_width, height, color or 0x07E0)
    end
    
    -- Текст прогресса
    local percent_text = tostring(math.floor(progress)) .. "%"
    ui.text(x + width/2 - 10, y + height/2 - 4, percent_text, 1, 0xFFFF)
end

-- Основная функция отрисовки
function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0)

    -- URL
    local display_url = current_url
    if #display_url > 50 then
        display_url = display_url:sub(1, 47) .. "..."
    end
    ui.text(10, 12, display_url, 2, 0xFFFF)

    -- Кнопки управления
    if ui.button(10, 52, 100, 40, "Back", 0x4208) then 
        -- go_back() - реализуйте если нужно
    end
    if ui.button(120, 52, 130, 40, "Reload", 0x4208) then 
        -- Очистка кэша
        for url, cache in pairs(image_cache) do
            if cache.path and fs.exists(cache.path) then
                fs.remove(cache.path)
            end
        end
        image_cache = {}
        load_page(current_url)
    end
    if ui.button(260, 52, 130, 40, "Home", 0x4208) then 
        -- Очистка кэша
        for url, cache in pairs(image_cache) do
            if cache.path and fs.exists(cache.path) then
                fs.remove(cache.path)
            end
        end
        image_cache = {}
        load_page("https://www.furtails.pw")
    end

    -- Контент
    scroll_y = ui.beginList(0, 100, SCR_W, SCR_H - 100, scroll_y, content_height)

    local cy = 20
    for idx, item in ipairs(content) do
        if item.type == "text" then
            if item.text ~= "" then
                ui.text(20, cy, item.text, 2, 0xFFFF)
                cy = cy + LINE_H
            else
                cy = cy + LINE_H / 2
            end
        elseif item.type == "link" then
            local clicked = ui.button(10, cy, SCR_W - 20, LINK_H, "", 0x0101)
            ui.text(25, cy + 6, item.text, 2, 0x07FF)
            if clicked then
                for url, cache in pairs(image_cache) do
                    if cache.path and fs.exists(cache.path) then
                        fs.remove(cache.path)
                    end
                end
                image_cache = {}
                load_page(item.url)
            end
            cy = cy + LINK_H
        elseif item.type == "image" then
            local img_url = item.image_url
            local cache_entry = img_url and image_cache[img_url]
            local is_supported = is_supported_image(img_url)
            
            -- Цвет фона в зависимости от состояния
            local bg_color = 0x2104
            
            if is_supported then
                if cache_entry then
                    if cache_entry.loaded then
                        bg_color = 0x0520  -- Загружено
                    elseif cache_entry.loading then
                        bg_color = 0xFD20  -- Загружается
                    elseif cache_entry.failed then
                        bg_color = 0xF800  -- Ошибка
                    else
                        bg_color = 0x001F  -- Можно загрузить
                    end
                else
                    bg_color = 0x001F  -- Не загружалось
                end
            else
                bg_color = 0x4A69  -- Неподдерживаемый
            end
            
            -- Фон
            ui.rect(10, cy, SCR_W - 20, IMAGE_H, bg_color)
            
            -- Текст
            ui.text(20, cy + 10, item.text, 1, 0xFFFF)
            
            -- Отображение состояния
            if cache_entry then
                if cache_entry.loading then
                    -- Прогресс загрузки
                    local progress = cache_entry.progress or 0
                    local loaded_kb = math.floor((cache_entry.loaded or 0) / 1024)
                    local total_kb = math.floor((cache_entry.total or 0) / 1024)
                    
                    -- Прогресс-бар
                    ui.rect(20, cy + 40, SCR_W - 40, 30, 0x0000)
                    draw_progress_bar(30, cy + 45, SCR_W - 60, 20, progress)
                    
                    -- Размер файла
                    if total_kb > 0 then
                        ui.text(SCR_W/2 - 40, cy + 70, 
                               loaded_kb .. "/" .. total_kb .. " KB", 1, 0xFFFF)
                    end
                elseif cache_entry.loaded then
                    -- Показываем изображение
                    if cache_entry.path and fs.exists(cache_entry.path) then
                        local success = ui.drawJPEG(15, cy + 5, cache_entry.path)
                        if not success then
                            ui.text(20, cy + 60, "Display error", 1, 0xF800)
                        end
                    end
                elseif cache_entry.failed then
                    -- Ошибка
                    ui.text(20, cy + 60, "Load failed", 1, 0xF800)
                end
            elseif is_supported then
                -- Можно загрузить
                ui.text(20, cy + 60, "Click to load", 1, 0x07FF)
                ui.text(20, cy + 80, "JPG/PNG format", 1, 0x07E0)
            else
                -- Неподдерживаемый формат
                ui.text(20, cy + 60, "Format not supported", 1, 0xF800)
            end
            
            -- Кнопка для загрузки (прозрачная)
            local clicked = ui.button(10, cy, SCR_W - 20, IMAGE_H, "", 0x0101)
            if clicked and is_supported and img_url then
                if not cache_entry or (not cache_entry.loading and not cache_entry.loaded) then
                    -- Запускаем загрузку (блокирует UI, но показывает прогресс)
                    load_image_to_cache(img_url)
                end
            end
            
            cy = cy + IMAGE_H + 10
        end
    end

    ui.endList()
    
    -- Индикатор загрузки
    if currently_downloading then
        ui.rect(SCR_W - 60, SCR_H - 40, 50, 30, 0x0000)
        ui.text(SCR_W - 55, SCR_H - 35, "LOADING", 1, 0x07E0)
        
        local progress = image_cache[currently_downloading] and 
                        image_cache[currently_downloading].progress or 0
        ui.rect(SCR_W - 55, SCR_H - 20, 40, 8, 0x4208)
        if progress > 0 then
            local fill_width = math.floor(40 * progress / 100)
            ui.rect(SCR_W - 55, SCR_H - 20, fill_width, 8, 0x07E0)
        end
    end
end

-- Создаем папку для кэша
if not fs.exists("/cache") then
    fs.mkdir("/cache")
end

-- Загружаем стартовую страницу
load_page(current_url)
