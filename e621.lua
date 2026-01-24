-- Простой клиент для e621.net (NSFW-сайт с артом)
-- Добавлена отладка: statusMsg для ошибок/прогресса
-- Прогресс загрузки через callback
-- Загружает только один пост за раз (limit=1)
-- После успешной загрузки сразу показывает viewer

local SCR_W, SCR_H = 410, 502  -- Размеры экрана
local tags = "score:>50+cute"  -- Пример тегов по умолчанию (можно менять)
local post_path = nil          -- Путь к загруженному изображению
local statusMsg = "Enter tags and press Search"  -- Основной статус
local progress = 0             -- Прогресс загрузки (0-100)
local totalSize = 0            -- Общий размер для прогресса
local downloading = false      -- Флаг скачивания
local errorLog = ""            -- Отдельный лог ошибок (отображается внизу)

-- Простой парсер JSON: берём только первый file.url
function parse_e621_json(json_str)
    local url = nil
    for match in json_str:gmatch('"file":{"url":"(.-)"') do
        url = match
        break  -- Только первый
    end
    return url
end

-- Callback для прогресса загрузки
function download_progress(loaded, total)
    if total > 0 then
        progress = math.floor((loaded / total) * 100)
    else
        progress = 0
    end
    statusMsg = "Downloading... " .. progress .. "%"
    -- Можно добавить в errorLog, если нужно: errorLog = errorLog .. "Progress: " .. progress .. "%\n"
end

-- Функция поиска и скачивания одного поста
function search_and_download()
    if tags == "" then
        statusMsg = "Error: Enter tags!"
        errorLog = errorLog .. "Tags empty\n"
        return
    end
    statusMsg = "Searching API..."
    errorLog = "Search started\n"

    local api_url = "https://e621.net/posts.json?tags=" .. tags:gsub(" ", "+") .. "&limit=1"
    local res = net.get(api_url)

    if not res.ok or res.code ~= 200 then
        statusMsg = "Search failed"
        errorLog = errorLog .. "API error: " .. (res.err or "code " .. res.code) .. "\n"
        return
    end

    local url = parse_e621_json(res.body)
    if not url then
        statusMsg = "No image found"
        errorLog = errorLog .. "No file.url in JSON\n"
        return
    end

    local filename = "/e621/last_post.jpg"
    sd.mkdir("/e621")  -- Создаём папку, если нет

    statusMsg = "Downloading image..."
    downloading = true
    progress = 0
    totalSize = 0

    local success = net.download(url, filename, download_progress)

    if success then
        post_path = filename
        statusMsg = "Loaded! Showing image..."
        errorLog = errorLog .. "Download OK\n"
    else
        statusMsg = "Download failed"
        errorLog = errorLog .. "Download error\n"
    end

    downloading = false
end

-- Отрисовка прогресс-бара
function draw_progress_bar(x, y, w, h)
    ui.rect(x, y, w, h, 0x4208)  -- Фон
    if totalSize > 0 then
        local pw = math.floor((progress / 100) * w)
        ui.rect(x, y, pw, h, 0x07E0)  -- Зелёный прогресс
    end
    ui.text(x + 10, y + (h - 16)/2, progress .. "%", 2, 0xFFFF)
end

-- Просмотр изображения (единственного)
function draw_viewer()
    if post_path then
        ui.drawJPEG_SD(0, 0, post_path)  -- Полный размер, клиппинг экрана
    end
    ui.text(10, 10, "e621 Viewer", 2, 0xFFFF)
    ui.text(10, SCR_H - 40, statusMsg, 1, 0xFFFF)

    -- Прогресс-бар, если скачиваем
    if downloading then
        draw_progress_bar(20, SCR_H - 80, SCR_W - 40, 30)
    end

    -- Кнопка назад
    if ui.button(SCR_W - 100, SCR_H - 50, 90, 40, "Back", 0xF800) then
        post_path = nil
        statusMsg = "Ready for new search"
    end

    -- Отладка ошибок (маленький текст внизу)
    if errorLog ~= "" then
        ui.text(10, SCR_H - 20, errorLog:sub(-80), 1, 0xF800)  -- Последние 80 символов красным
    end
end

-- Основная функция draw()
function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)  -- Чёрный фон

    if post_path then
        -- Если изображение загружено — показываем viewer
        draw_viewer()
    else
        -- Иначе — поиск
        ui.text(10, 10, "e621 Client (1 post)", 2, 0xFFFF)

        -- Поле ввода тегов (для простоты — клик для фокуса, но без редактирования)
        ui.input(10, 40, SCR_W - 120, 30, "Tags: " .. tags, true)

        -- Кнопка поиска
        if ui.button(SCR_W - 100, 40, 90, 30, "Search", 0x07E0) and not downloading then
            search_and_download()
        end

        ui.text(10, 80, statusMsg, 1, 0xFFFF)

        -- Прогресс-бар
        if downloading then
            draw_progress_bar(20, 120, SCR_W - 40, 30)
        end

        -- Отладка
        if errorLog ~= "" then
            ui.text(10, 160, "Errors:", 1, 0xF800)
            ui.text(10, 180, errorLog:sub(-120), 1, 0xF800)  -- Последние 120 символов
        end
    end

    -- Периодическая очистка кэша (каждые 10 сек)
    if hw.millis() % 10000 < 100 then
        ui.unloadAll()
    end
end

-- Инициализация
if not sd.exists("/e621") then
    sd.mkdir("/e621")
end

-- Для теста: можно сразу искать, если tags не пустые
-- search_and_download()
