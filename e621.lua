-- e621 simple client for LuaWatch
-- Константы экрана
SCR_W = 410
SCR_H = 502

-- Состояние приложения
local app = {
    searchText = "cat",
    posts = {},
    scrollY = 0,
    maxScroll = 0,
    loading = false,
    page = 1,
    selectedTags = {},
    currentImage = nil
}

-- Настройки
local settings = {
    apiKey = "", -- оставьте пустым для публичного доступа
    username = "", -- оставьте пустым для публичного доступа
    rating = "safe", -- safe, questionable, explicit
    limit = 20 -- кол-во постов на страницу
}

-- Ключевые слова для быстрого поиска
local quickTags = {
    "cat", "dog", "fox", "wolf", "bird",
    "feral", "anthro", "male", "female",
    "solo", "duo", "group", "landscape",
    "digital_art", "traditional_art"
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
    explicit = 0xF800
}

-- Очистка изображений из кэша
function clearImageCache()
    for _, post in ipairs(app.posts) do
        if post.cacheKey then
            ui.unload(post.cacheKey)
        end
    end
end

-- Парсинг JSON (очень простой парсер для e621)
function parseJSON(str)
    local result = {}
    local i = 1
    local len = #str
    
    local function parseValue()
        while i <= len and str:sub(i, i):match("%s") do i = i + 1 end
        
        if str:sub(i, i) == '{' then
            return parseObject()
        elseif str:sub(i, i) == '[' then
            return parseArray()
        elseif str:sub(i, i) == '"' then
            return parseString()
        elseif str:sub(i, i):match("%d") then
            return parseNumber()
        elseif str:sub(i, i+3) == 'true' then
            i = i + 4
            return true
        elseif str:sub(i, i+4) == 'false' then
            i = i + 5
            return false
        elseif str:sub(i, i+3) == 'null' then
            i = i + 4
            return nil
        end
        return nil
    end
    
    local function parseObject()
        i = i + 1 -- пропускаем '{'
        local obj = {}
        
        while i <= len do
            while i <= len and str:sub(i, i):match("%s") do i = i + 1 end
            
            if str:sub(i, i) == '}' then
                i = i + 1
                return obj
            end
            
            -- Парсим ключ
            local key = parseString()
            
            while i <= len and str:sub(i, i):match("%s") do i = i + 1 end
            if str:sub(i, i) == ':' then i = i + 1 end
            
            -- Парсим значение
            obj[key] = parseValue()
            
            while i <= len and str:sub(i, i):match("%s") do i = i + 1 end
            if str:sub(i, i) == ',' then i = i + 1 end
        end
        return obj
    end
    
    local function parseArray()
        i = i + 1 -- пропускаем '['
        local arr = {}
        
        while i <= len do
            while i <= len and str:sub(i, i):match("%s") do i = i + 1 end
            
            if str:sub(i, i) == ']' then
                i = i + 1
                return arr
            end
            
            table.insert(arr, parseValue())
            
            while i <= len and str:sub(i, i):match("%s") do i = i + 1 end
            if str:sub(i, i) == ',' then i = i + 1 end
        end
        return arr
    end
    
    local function parseString()
        i = i + 1 -- пропускаем первую кавычку
        local start = i
        while i <= len and str:sub(i, i) ~= '"' do
            if str:sub(i, i) == '\\' then i = i + 1 end
            i = i + 1
        end
        local s = str:sub(start, i-1)
        i = i + 1 -- пропускаем последнюю кавычку
        return s
    end
    
    local function parseNumber()
        local start = i
        while i <= len and str:sub(i, i):match("[%d%.%-]") do
            i = i + 1
        end
        return tonumber(str:sub(start, i-1))
    end
    
    return parseValue()
end

-- Поиск постов на e621
function searchPosts(tags, page)
    app.loading = true
    app.page = page or 1
    
    local url = string.format(
        "https://e621.net/posts.json?tags=%s&limit=%d&page=%d",
        tags:gsub(" ", "+"),
        settings.limit,
        app.page
    )
    
    local headers = {
        "User-Agent: LuaWatch/1.0 (by yourUsername)",
        "Accept: application/json"
    }
    
    if settings.apiKey ~= "" and settings.username ~= "" then
        table.insert(headers, string.format(
            "Authorization: Basic %s",
            toBase64(settings.username .. ":" .. settings.apiKey)
        ))
    end
    
    -- Используем расширенную функцию net.get с заголовками
    local code, body = customHttpGet(url, headers)
    
    if code == 200 and body then
        local data = parseJSON(body)
        if data and data.posts then
            -- Очищаем старые изображения
            clearImageCache()
            
            app.posts = {}
            for _, post in ipairs(data.posts) do
                -- Проверяем рейтинг
                local showPost = false
                if settings.rating == "safe" and post.rating == "s" then showPost = true
                elseif settings.rating == "questionable" and (post.rating == "s" or post.rating == "q") then showPost = true
                elseif settings.rating == "explicit" then showPost = true
                end
                
                if showPost and post.file and post.file.url then
                    local ext = post.file.ext or ""
                    if ext:lower() == "jpg" or ext:lower() == "jpeg" or ext:lower() == "png" then
                        local postData = {
                            id = post.id,
                            url = post.file.url,
                            preview = post.preview and post.preview.url or nil,
                            sample = post.sample and post.sample.url or nil,
                            width = post.file.width,
                            height = post.file.height,
                            rating = post.rating,
                            tags = post.tags,
                            artist = post.tags.artist and post.tags.artist[1] or "unknown",
                            cacheKey = "/e621_" .. post.id .. ".jpg"
                        }
                        table.insert(app.posts, postData)
                    end
                end
            end
            app.loading = false
            app.scrollY = 0
            calculateMaxScroll()
            return true
        end
    end
    
    app.loading = false
    return false
end

-- Вспомогательная функция для Base64
function toBase64(str)
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local result = ''
    
    for i = 1, #str, 3 do
        local a, b, c = str:byte(i, i+2)
        local n = (a or 0) * 0x10000 + (b or 0) * 0x100 + (c or 0)
        
        for j = 1, 4 do
            local k = bit.rshift(n, 6 * (4 - j)) % 64
            result = result .. b64chars:sub(k+1, k+1)
        end
    end
    
    -- Добавляем padding
    local pad = 3 - ((#str - 1) % 3)
    if pad > 0 and pad < 3 then
        result = result:sub(1, -pad-1) .. string.rep('=', pad)
    end
    
    return result
end

-- Кастомный HTTP GET с заголовками
function customHttpGet(url, headers)
    -- В этой версии прошивки net.get не поддерживает заголовки напрямую
    -- Используем стандартный net.get, который обычно работает для e621
    local res = net.get(url)
    if res and res.ok then
        return res.code, res.body
    end
    return res and res.code or 0, nil
end

-- Расчет максимальной прокрутки
function calculateMaxScroll()
    local totalHeight = #app.posts * 120 -- каждый пост примерно 120px
    app.maxScroll = math.max(0, totalHeight - (SCR_H - 60)) -- 60px для верхней панели
end

-- Загрузка изображения
function loadImage(post)
    if not post or not post.url then return false end
    
    -- Сначала пробуем загрузить sample (меньший размер)
    local imageUrl = post.sample or post.url
    local filename = post.cacheKey
    
    -- Проверяем, есть ли уже в кэше
    if fs.exists(filename) then
        return true
    end
    
    -- Скачиваем изображение
    print("Downloading: " .. imageUrl)
    local success = net.download(imageUrl, filename, function(loaded, total)
        print(string.format("Progress: %d/%d", loaded, total))
    end)
    
    return success
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
    
    ui.rect(x, y, 20, 20, color)
    ui.text(x + 6, y + 2, text, 2, COLORS.bg)
end

-- Отрисовка интерфейса
function draw()
    -- Фон
    ui.rect(0, 0, SCR_W, SCR_H, COLORS.bg)
    
    -- Верхняя панель
    ui.rect(0, 0, SCR_W, 60, 0x2104)
    
    -- Поле поиска
    ui.rect(10, 10, 250, 40, 0x4208)
    ui.text(15, 20, app.searchText, 2, COLORS.text)
    
    -- Кнопка поиска
    if ui.button(270, 10, 60, 40, "GO", COLORS.button) then
        if app.searchText ~= "" then
            searchPosts(app.searchText, 1)
        end
    end
    
    -- Кнопка настроек
    if ui.button(340, 10, 60, 40, "SET", COLORS.button) then
        app.currentView = "settings"
    end
    
    if app.currentView == "settings" then
        drawSettings()
        return
    end
    
    if app.currentImage then
        drawImageView()
        return
    end
    
    -- Индикатор загрузки
    if app.loading then
        ui.text(SCR_W/2 - 40, SCR_H/2, "Loading...", 3, COLORS.text)
        return
    end
    
    -- Список постов
    if #app.posts == 0 then
        ui.text(SCR_W/2 - 80, SCR_H/2, "No posts found", 3, COLORS.text)
        
        -- Быстрые теги
        ui.text(10, 80, "Try:", 2, COLORS.text)
        local x, y = 10, 110
        for i, tag in ipairs(quickTags) do
            if ui.button(x, y, 60, 30, tag, COLORS.button) then
                app.searchText = tag
                searchPosts(tag, 1)
            end
            x = x + 65
            if x > SCR_W - 70 then
                x = 10
                y = y + 35
            end
        end
        return
    end
    
    -- Прокручиваемый список
    app.scrollY = ui.beginList(0, 60, SCR_W, SCR_H - 60, app.scrollY, #app.posts * 120)
    
    for i, post in ipairs(app.posts) do
        local yPos = (i-1) * 120
        
        -- Фон поста
        ui.rect(10, yPos + 5, SCR_W - 20, 110, 0x2104)
        
        -- Рейтинг
        drawRating(post.rating, 15, yPos + 10)
        
        -- Информация
        ui.text(40, yPos + 10, "ID: " .. post.id, 1, COLORS.text)
        ui.text(40, yPos + 25, "Artist: " .. post.artist, 1, COLORS.text)
        ui.text(40, yPos + 40, string.format("%dx%d", post.width, post.height), 1, COLORS.text)
        
        -- Кнопка просмотра
        if ui.button(SCR_W - 100, yPos + 10, 80, 40, "VIEW", COLORS.button) then
            if loadImage(post) then
                app.currentImage = post
            else
                print("Failed to load image")
            end
        end
        
        -- Кнопка скачивания
        if ui.button(SCR_W - 100, yPos + 60, 80, 40, "SAVE", COLORS.buttonActive) then
            -- Сохраняем в SD
            if sd.exists then
                local sdPath = "/e621_" .. post.id .. ".jpg"
                if fs.exists(post.cacheKey) then
                    local content = fs.readBytes(post.cacheKey)
                    if content and sd.append then
                        local file = sd.append(sdPath, content)
                        if file then
                            print("Saved to SD: " .. sdPath)
                        end
                    end
                end
            end
        end
        
        -- Разделитель
        ui.rect(10, yPos + 115, SCR_W - 20, 1, 0x528B)
    end
    
    ui.endList()
    
    -- Индикатор страницы
    ui.text(10, SCR_H - 25, string.format("Page: %d", app.page), 2, COLORS.text)
    
    -- Кнопки навигации
    if ui.button(SCR_W - 160, SCR_H - 40, 70, 30, "PREV", COLORS.button) and app.page > 1 then
        searchPosts(app.searchText, app.page - 1)
    end
    
    if ui.button(SCR_W - 80, SCR_H - 40, 70, 30, "NEXT", COLORS.button) then
        searchPosts(app.searchText, app.page + 1)
    end
end

-- Окно настроек
function drawSettings()
    ui.rect(0, 0, SCR_W, SCR_H, COLORS.bg)
    ui.text(SCR_W/2 - 40, 20, "SETTINGS", 3, COLORS.text)
    
    -- Рейтинг
    ui.text(20, 70, "Rating Filter:", 2, COLORS.text)
    local ratingY = 100
    local ratings = {"safe", "questionable", "explicit"}
    for _, r in ipairs(ratings) do
        local color = (settings.rating == r) and COLORS.buttonActive or COLORS.button
        if ui.button(20, ratingY, 120, 40, r:upper(), color) then
            settings.rating = r
            -- Сохраняем настройки
            fs.save("/e621_settings.json", jsonEncode(settings))
        end
        ratingY = ratingY + 50
    end
    
    -- Лимит постов
    ui.text(20, 250, "Posts per page:", 2, COLORS.text)
    ui.text(20, 280, tostring(settings.limit), 3, COLORS.text)
    
    if ui.button(100, 275, 40, 30, "-", COLORS.button) and settings.limit > 5 then
        settings.limit = settings.limit - 5
        fs.save("/e621_settings.json", jsonEncode(settings))
    end
    
    if ui.button(150, 275, 40, 30, "+", COLORS.button) and settings.limit < 100 then
        settings.limit = settings.limit + 5
        fs.save("/e621_settings.json", jsonEncode(settings))
    end
    
    -- API настройки (опционально)
    ui.text(20, 320, "API Key (optional):", 2, COLORS.text)
    ui.rect(20, 350, 200, 40, 0x4208)
    ui.text(25, 360, string.rep("*", #settings.apiKey), 2, COLORS.text)
    
    -- Кнопка назад
    if ui.button(SCR_W/2 - 60, SCR_H - 60, 120, 40, "BACK", COLORS.button) then
        app.currentView = nil
    end
end

-- Просмотр изображения
function drawImageView()
    if not app.currentImage then return end
    
    ui.rect(0, 0, SCR_W, SCR_H, COLORS.bg)
    
    -- Загружаем и отображаем изображение
    if fs.exists(app.currentImage.cacheKey) then
        if not ui.drawJPEG(10, 10, app.currentImage.cacheKey) then
            ui.text(SCR_W/2 - 60, SCR_H/2, "Failed to display", 2, COLORS.text)
        end
    else
        ui.text(SCR_W/2 - 60, SCR_H/2, "Image not loaded", 2, COLORS.text)
    end
    
    -- Информация об изображении
    ui.rect(0, SCR_H - 50, SCR_W, 50, 0x2104)
    ui.text(10, SCR_H - 40, "ID: " .. app.currentImage.id, 2, COLORS.text)
    drawRating(app.currentImage.rating, SCR_W - 100, SCR_H - 45)
    
    -- Кнопки
    if ui.button(SCR_W - 80, 10, 70, 40, "BACK", COLORS.button) then
        app.currentImage = nil
    end
    
    if ui.button(SCR_W - 80, 60, 70, 40, "SAVE", COLORS.buttonActive) then
        -- Сохраняем в SD карту
        if sd.exists then
            local sdPath = "/e621_" .. app.currentImage.id .. ".jpg"
            if fs.exists(app.currentImage.cacheKey) then
                local content = fs.readBytes(app.currentImage.cacheKey)
                if content and sd.append then
                    local file = sd.append(sdPath, content)
                    if file then
                        print("Saved to SD: " .. sdPath)
                    end
                end
            end
        end
    end
end

-- Простой JSON encoder для настроек
function jsonEncode(t)
    local result = "{"
    local first = true
    
    for k, v in pairs(t) do
        if not first then result = result .. "," end
        if type(v) == "string" then
            result = result .. string.format('"%s":"%s"', k, v)
        elseif type(v) == "number" then
            result = result .. string.format('"%s":%d', k, v)
        elseif type(v) == "boolean" then
            result = result .. string.format('"%s":%s', k, tostring(v))
        end
        first = false
    end
    
    return result .. "}"
end

-- Загрузка настроек
function loadSettings()
    if fs.exists("/e621_settings.json") then
        local content = fs.load("/e621_settings.json")
        if content then
            local ok, data = pcall(parseJSON, content)
            if ok and data then
                for k, v in pairs(data) do
                    settings[k] = v
                end
            end
        end
    end
end

-- Инициализация
function init()
    print("e621 Client Starting...")
    
    -- Загружаем настройки
    loadSettings()
    
    -- Проверяем сеть
    if net.status() ~= 3 then
        print("WiFi not connected")
        -- Можно добавить экран подключения к WiFi
    end
    
    -- Автоматический поиск при запуске
    searchPosts(app.searchText, 1)
end

-- Запуск приложения
init()
