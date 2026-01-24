-- e621 simple client for LuaWatch - Fixed parser version
-- Константы экрана (закругленный 410x502)
SCR_W = 410
SCR_H = 502
SAFE_MARGIN = 20  -- Отступ от углов для закругленного экрана

-- Отладочный вывод
local debugLog = {}
local MAX_LOG_LINES = 10

function addLog(msg)
    table.insert(debugLog, 1, tostring(msg))
    if #debugLog > MAX_LOG_LINES then
        table.remove(debugLog, MAX_LOG_LINES + 1)
    end
    print(msg)
end

-- Состояние приложения
local app = {
    searchText = "cat_solo",
    currentPost = nil,
    loading = false,
    page = 1,
    debugVisible = true,
    lastError = nil,
    downloadProgress = 0,
    downloadTotal = 0
}

-- Настройки
local settings = {
    rating = "safe",
    showDebug = true
}

-- Цвета
local COLORS = {
    bg = 0x0000,
    text = 0xFFFF,
    button = 0x528B,
    buttonActive = 0x7BEF,
    warning = 0xF800,
    safe = 0x07E0,
    questionable = 0xFD20,
    explicit = 0xF800,
    debug = 0xAD55,
    progress = 0x07FF
}

function drawProgress()
    if app.downloadTotal == 0 then return end
    
    local width = SCR_W - 2*SAFE_MARGIN - 20
    local progressWidth = app.downloadTotal > 0 and math.floor((app.downloadProgress / app.downloadTotal) * width) or 0
    
    ui.rect(SAFE_MARGIN + 10, SCR_H - 180, width, 15, 0x4208)
    ui.rect(SAFE_MARGIN + 10, SCR_H - 180, progressWidth, 15, COLORS.progress)
    
    if app.downloadTotal > 0 then
        local percent = math.floor((app.downloadProgress / app.downloadTotal) * 100)
        local text = string.format("%d%% (%d/%d KB)", 
            percent, 
            math.floor(app.downloadProgress / 1024),
            math.floor(app.downloadTotal / 1024)
        )
        ui.text(SCR_W/2 - 40, SCR_H - 178, text, 1, COLORS.text)
    else
        ui.text(SCR_W/2 - 30, SCR_H - 178, "Downloading...", 1, COLORS.text)
    end
end

-- Очистка изображений из кэша
function clearImageCache()
    if app.currentPost and app.currentPost.cacheKey then
        ui.unload(app.currentPost.cacheKey)
        addLog("Cache cleared")
    end
end

-- ОЧЕНЬ ПРОСТОЙ парсер для извлечения данных из e621 JSON
function parseSimpleE621(jsonStr)
    addLog("Parsing simple...")
    
    -- Ищем основные поля простым поиском
    local post = {}
    
    -- ID
    local idMatch = jsonStr:match('"id"%s*:%s*(%d+)')
    post.id = idMatch and tonumber(idMatch) or 0
    addLog("Found ID: " .. post.id)
    
    if post.id == 0 then
        -- Попробуем другой паттерн
        idMatch = jsonStr:match('"id" ?: ?(%d+)')
        post.id = idMatch and tonumber(idMatch) or 0
        addLog("Alt ID: " .. post.id)
    end
    
    -- Рейтинг
    local ratingMatch = jsonStr:match('"rating"%s*:%s*"([sqe])"')
    if not ratingMatch then
        ratingMatch = jsonStr:match('"rating" ?: ?"([sqe])"')
    end
    post.rating = ratingMatch or "q"
    addLog("Rating: " .. post.rating)
    
    -- Размеры
    local widthMatch = jsonStr:match('"width"%s*:%s*(%d+)')
    local heightMatch = jsonStr:match('"height"%s*:%s*(%d+)')
    post.width = widthMatch and tonumber(widthMatch) or 0
    post.height = heightMatch and tonumber(heightMatch) or 0
    addLog("Size: " .. post.width .. "x" .. post.height)
    
    -- Расширение файла
    local extMatch = jsonStr:match('"ext"%s*:%s*"([^"]+)"')
    post.ext = extMatch or ""
    addLog("Ext: " .. post.ext)
    
    -- URL файла (полный размер)
    local urlMatch = jsonStr:match('"url"%s*:%s*"([^"]+)"')
    post.file_url = urlMatch or ""
    if post.file_url == "" then
        -- Пробуем найти в секции file
        local fileSection = jsonStr:match('"file"%s*:%s*{([^}]+)}')
        if fileSection then
            urlMatch = fileSection:match('"url"%s*:%s*"([^"]+)"')
            post.file_url = urlMatch or ""
        end
    end
    addLog("File URL found: " .. (#post.file_url > 0 and "yes" or "no"))
    
    -- Preview URL (маленький размер)
    local previewMatch = jsonStr:match('"preview"%s*:%s*{([^}]+)}')
    if previewMatch then
        local previewUrl = previewMatch:match('"url"%s*:%s*"([^"]+)"')
        post.preview_url = previewUrl or ""
    else
        post.preview_url = ""
    end
    
    -- Sample URL (средний размер)
    local sampleMatch = jsonStr:match('"sample"%s*:%s*{([^}]+)}')
    if sampleMatch then
        local sampleUrl = sampleMatch:match('"url"%s*:%s*"([^"]+)"')
        post.sample_url = sampleUrl or ""
    else
        post.sample_url = ""
    end
    
    -- Артист
    local tagsMatch = jsonStr:match('"tags"%s*:%s*{([^}]+)}')
    if tagsMatch then
        local artistMatch = tagsMatch:match('"artist"%s*:%s*%[([^%]]+)%]')
        if artistMatch then
            -- Берем первого артиста из массива
            local firstArtist = artistMatch:match('"([^"]+)"')
            post.artist = firstArtist or "unknown"
        else
            post.artist = "unknown"
        end
    else
        post.artist = "unknown"
    end
    addLog("Artist: " .. post.artist)
    
    return post
end

-- Получение одного поста с e621
function fetchPost(tags)
    app.loading = true
    app.lastError = nil
    clearImageCache()
    
    local url = string.format(
        "https://e621.net/posts.json?tags=%s&limit=1&page=%d",
        tags:gsub(" ", "+"),
        app.page
    )
    
    addLog("Fetching: " .. url)
    
    local res = net.get(url)
    
    if res and res.code == 200 and res.body then
        addLog("Response: " .. #res.body .. " bytes")
        
        -- Покажем начало ответа для отладки
        if #res.body > 500 then
            addLog("First 500 chars:")
            addLog(res.body:sub(1, 500))
        end
        
        local postData = parseSimpleE621(res.body)
        
        if postData and postData.id > 0 then
            -- Проверяем рейтинг
            local showPost = false
            if settings.rating == "safe" and postData.rating == "s" then 
                showPost = true
            elseif settings.rating == "questionable" and (postData.rating == "s" or postData.rating == "q") then 
                showPost = true
            elseif settings.rating == "explicit" then 
                showPost = true
            end
            showPost = true
            
            if not showPost then
                app.lastError = "Rating filtered: " .. postData.rating
                app.loading = false
                return false
            end
            
            -- Проверяем формат
            local ext = postData.ext:lower()
            local supported = ext == ".jpg" or ext == ".jpeg" or ext == ".png" or
                             ext == "jpg" or ext == "jpeg" or ext == "png" or
                             ext == ""  -- Иногда может быть пустым
            
            
            -- Проверяем URL
            local imageUrl = postData.sample_url or postData.preview_url or postData.file_url
            if not imageUrl or imageUrl == "" then
                app.lastError = "No image URL found"
                app.loading = false
                return false
            end
            
            app.currentPost = {
                id = postData.id,
                url = postData.file_url,
                preview = postData.preview_url,
                sample = postData.sample_url,
                width = postData.width,
                height = postData.height,
                rating = postData.rating,
                artist = postData.artist,
                cacheKey = "/e621_" .. postData.id .. ".jpg"
            }
            
            addLog("Post loaded: ID=" .. postData.id)
            addLog("Image URL: " .. (imageUrl:sub(1, 50) .. "..."))
            app.loading = false
            return true
        else
            app.lastError = "No posts found (ID=0)"
            addLog("Parse result: ID=0")
        end
    else
        local errMsg = res and res.err or "Unknown error"
        local code = res and res.code or "?"
        app.lastError = "HTTP " .. code .. ": " .. errMsg
        addLog("HTTP error: " .. app.lastError)
    end
    
    app.loading = false
    return false
end

-- Загрузка изображения
function loadCurrentImage()
    if not app.currentPost then 
        addLog("No post to load")
        return false 
    end
    
    -- Выбираем URL для загрузки
    local imageUrl = app.currentPost.sample or app.currentPost.preview or app.currentPost.url
    
    if not imageUrl or imageUrl == "" then
        app.lastError = "No image URL available"
        addLog("No image URL")
        return false
    end
    
    addLog("Loading: " .. imageUrl:sub(1, 50) .. "...")
    
    -- Проверяем кэш
    if sd.exists(app.currentPost.cacheKey) then
        addLog("Image in cache")
        return true
    end
    
    addLog("Downloading...")
    
    -- Сбрасываем прогресс
    app.downloadProgress = 0
    app.downloadTotal = 0
    
    local success = net.download(
        imageUrl, 
        app.currentPost.cacheKey,
        function(loaded, total)
            app.downloadProgress = loaded
            app.downloadTotal = total
            addLog("DL: " .. loaded .. "/" .. total)
            drawProgress()
            ui.flush()
        end
    )    
    if success then
        addLog("Download OK")
        return true
    else
        app.lastError = "Download failed"
        addLog("Download failed")
        return false
    end
end

-- Отображение рейтинга
function drawRating(rating, x, y)
    local color = COLORS.text
    local text = "?"
    
    if rating == "s" then
        color = COLORS.safe
        text = "S"
    elseif rating == "q" then
        color = COLORS.questionable
        text = "Q"
    elseif rating == "e" then
        color = COLORS.explicit
        text = "E"
    end
    
    ui.rect(x, y, 25, 25, color)
    ui.text(x + 8, y + 5, text, 2, COLORS.bg)
end

-- Безопасные координаты (учитываем закругленные углы)
function safeX(x)
    return math.max(SAFE_MARGIN, math.min(SCR_W - SAFE_MARGIN, x))
end

function safeY(y)
    return math.max(SAFE_MARGIN, math.min(SCR_H - SAFE_MARGIN, y))
end

-- Отрисовка отладочной информации
function drawDebugInfo()
    if not settings.showDebug then return end
    
    -- Фон для лога
    ui.rect(SAFE_MARGIN, SCR_H - 150, SCR_W - 2*SAFE_MARGIN, 130, 0x2104)
    ui.rect(SAFE_MARGIN, SCR_H - 150, SCR_W - 2*SAFE_MARGIN, 15, COLORS.debug)
    ui.text(SAFE_MARGIN + 5, SCR_H - 147, "DEBUG", 1, COLORS.bg)
    
    -- Лог
    local y = SCR_H - 130
    for i, msg in ipairs(debugLog) do
        if y < SCR_H - SAFE_MARGIN - 10 then
            local displayMsg = msg
            if #displayMsg > 40 then
                displayMsg = displayMsg:sub(1, 37) .. "..."
            end
            ui.text(SAFE_MARGIN + 5, y, displayMsg, 1, COLORS.text)
            y = y + 12
        end
    end
end

-- Основной интерфейс
function draw()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, COLORS.bg)
    
    -- Верхняя панель (безопасные координаты)
    ui.rect(SAFE_MARGIN, SAFE_MARGIN, SCR_W - 2*SAFE_MARGIN, 50, 0x2104)
    
    -- Поле поиска
    ui.rect(SAFE_MARGIN + 10, SAFE_MARGIN + 10, 200, 30, 0x4208)
    ui.text(SAFE_MARGIN + 15, SAFE_MARGIN + 15, app.searchText, 2, COLORS.text)
    
    -- Кнопка поиска
    if ui.button(SAFE_MARGIN + 220, SAFE_MARGIN + 10, 60, 30, "GO", COLORS.button) then
        if app.searchText ~= "" and #app.searchText > 0 then
            app.page = 1
            fetchPost(app.searchText)
        end
    end
    
    -- Кнопка дебага
    if ui.button(SAFE_MARGIN + 290, SAFE_MARGIN + 10, 60, 30, "DBG", COLORS.buttonActive) then
        settings.showDebug = not settings.showDebug
    end
    
    -- Индикатор загрузки
    if app.loading then
        ui.text(SCR_W/2 - 30, SCR_H/2 - 20, "LOADING...", 2, COLORS.text)
        drawDebugInfo()
        return
    end
    
    -- Ошибка
    if app.lastError then
        ui.text(SCR_W/2 - 30, SCR_H/2 - 40, "ERROR", 2, COLORS.warning)
        ui.text(SCR_W/2 - 100, SCR_H/2, app.lastError, 1, COLORS.text)
        
        if ui.button(SCR_W/2 - 60, SCR_H/2 + 40, 120, 40, "RETRY", COLORS.button) then
            app.lastError = nil
            fetchPost(app.searchText)
        end
        drawDebugInfo()
        return
    end
    
    -- Нет поста - показываем быстрые теги
    if not app.currentPost then
        drawQuickTags()
        drawDebugInfo()
        return
    end
    
    -- Отображение поста
    drawPost()
    
    -- Панель управления
    drawControls()
    
    -- Отладочная информация
    drawDebugInfo()
end

-- Быстрые теги
function drawQuickTags()
    local quickTags = {"cat", "dog", "fox", "wolf", "bird", "solo", "rating:s"}
    
    ui.rect(SAFE_MARGIN, 100, SCR_W - 2*SAFE_MARGIN, 200, 0x2104)
    ui.text(SCR_W/2 - 40, 110, "QUICK TAGS", 2, COLORS.text)
    
    local x, y = SAFE_MARGIN + 10, 140
    local btnW = 70
    local btnH = 35
    local spacing = 5
    
    for i, tag in ipairs(quickTags) do
        if ui.button(x, y, btnW, btnH, tag, COLORS.button) then
            app.searchText = tag
            app.page = 1
            fetchPost(tag)
        end
        
        x = x + btnW + spacing
        if x + btnW > SCR_W - SAFE_MARGIN then
            x = SAFE_MARGIN + 10
            y = y + btnH + spacing
        end
    end
    
    -- Инструкция
    ui.text(SCR_W/2 - 100, y + 50, "Enter tags or click quick tags", 1, COLORS.text)
    ui.text(SCR_W/2 - 80, y + 70, "Then press GO", 1, COLORS.text)
end

-- Отображение поста
function drawPost()
    local post = app.currentPost
    if not post then return end
    
    -- Область для информации
    local areaX = SAFE_MARGIN
    local areaY = SAFE_MARGIN + 60
    local areaW = SCR_W - 2*SAFE_MARGIN
    local areaH = SCR_H - SAFE_MARGIN - 160
    
    -- Фон
    ui.rect(areaX, areaY, areaW, areaH, 0x2104)
    
    -- Информация о посте
    ui.text(areaX + 10, areaY + 10, "ID: " .. post.id, 2, COLORS.text)
    ui.text(areaX + 10, areaY + 35, "Artist: " .. post.artist, 2, COLORS.text)
    ui.text(areaX + 10, areaY + 60, "Size: " .. post.width .. "x" .. post.height, 1, COLORS.text)
    
    -- Рейтинг
    drawRating(post.rating, areaX + areaW - 40, areaY + 10)
    
    -- Загружаем и отображаем изображение если есть
    if sd.exists(post.cacheKey) then
        addLog("Drawing image...")
        local success = ui.drawJPEG_SD(areaX + 10, areaY + 90, post.cacheKey)
        if not success then
            ui.text(areaX + 10, areaY + 90, "Image loaded", 1, COLORS.text)
            ui.text(areaX + 10, areaY + 110, "but display failed", 1, COLORS.text)
        end
    else
        ui.text(areaX + 10, areaY + 90, "Image not downloaded", 1, COLORS.text)
        ui.text(areaX + 10, areaY + 110, "Press LOAD to download", 1, COLORS.text)
    end
end

-- Панель управления
function drawControls()
    local y = SCR_H - SAFE_MARGIN - 40
    local btnW = 70
    local spacing = 5
    
    -- Кнопка загрузки
    if ui.button(SAFE_MARGIN, y, btnW, 60, "LOAD", COLORS.button) then
        loadCurrentImage()
    end
    
    -- Кнопка предыдущего
    local prevX = SAFE_MARGIN + btnW + spacing
    if ui.button(prevX, y, 50, 40, "<", COLORS.button) and app.page > 1 then
        app.page = app.page - 1
        fetchPost(app.searchText)
    end
    
    -- Номер страницы
    ui.rect(prevX + 55, y, 40, 40, 0x2104)
    ui.text(prevX + 60, y + 10, tostring(app.page), 2, COLORS.text)
    
    -- Кнопка следующего
    if ui.button(prevX + 100, y, 50, 40, ">", COLORS.button) then
        app.page = app.page + 1
        fetchPost(app.searchText)
    end
    
    -- Кнопка очистки
    if ui.button(SCR_W - SAFE_MARGIN - 60, y, 60, 40, "X", COLORS.warning) then
        clearImageCache()
        app.currentPost = nil
    end
end

-- Тестовая функция для отладки сети
function testNetwork()
    addLog("=== Network Test ===")
    addLog("Testing e621 API...")
    
    local testUrl = "https://e621.net/posts.json?tags=cat&limit=1"
    local res = net.get(testUrl)
    
    if res then
        addLog("Response code: " .. (res.code or "?"))
        addLog("Response length: " .. #(res.body or "0"))
        
        if res.body and #res.body > 100 then
            addLog("First 100 chars:")
            addLog(res.body:sub(1, 100))
            
            -- Пробуем распарсить
            local post = parseSimpleE621(res.body)
            if post and post.id > 0 then
                addLog("Parse success! ID=" .. post.id)
            else
                addLog("Parse failed")
            end
        end
    else
        addLog("No response")
    end
end

-- Инициализация
function init()
    addLog("=== e621 Client ===")
    addLog("Screen: " .. SCR_W .. "x" .. SCR_H)
    
    local freeMem = math.floor(hw.getFreePsram() / 1024)
    addLog("Free PSRAM: " .. freeMem .. "KB")
    
    -- Проверяем сеть
    if net.status() ~= 3 then
        app.lastError = "WiFi not connected"
        addLog("WiFi: Not connected")
    else
        addLog("WiFi: Connected")
        addLog("IP: " .. (net.getIP() or "unknown"))
        
        -- Тестируем сеть при запуске
        testNetwork()
    end
    
    addLog("Ready - use GO or quick tags")
end

-- Запуск приложения
init()

-- Простая функция для ручного теста из консоли
function manualTest()
    print("=== Manual Test ===")
    print("1. Testing fetch...")
    fetchPost("cat")
    
    print("2. Waiting 3 seconds...")
    local start = hw.millis()
    while hw.millis() - start < 3000 do end
    
    if app.currentPost then
        print("Post loaded: ID=" .. app.currentPost.id)
        print("Loading image...")
        loadCurrentImage()
    else
        print("No post loaded")
    end
end
