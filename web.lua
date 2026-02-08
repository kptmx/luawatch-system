-- Простой веб-браузер для LuaWatch
local Browser = {
    url = "",
    content = "",
    scrollY = 0,
    pageWidth = 390,
    pageHeight = 2000,
    loading = false,
    history = {},
    historyIndex = 0,
    cache = {},
    images = {},
    links = {},
    baseUrl = "",
    screenW = 410,
    screenH = 502,
    zoom = 1.0,
    lastTouchY = 0
}

-- Кодировка URL
function Browser.urlEncode(str)
    if str then
        str = string.gsub(str, "([^%w%-%.%_%~])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
    end
    return str
end

-- Декодировка URL
function Browser.urlDecode(str)
    str = string.gsub(str, '%%(%x%x)', function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return str
end

-- Извлечение базового URL
function Browser.getBaseUrl(url)
    if string.find(url, "://") then
        local protocol, rest = string.match(url, "^(.-)://(.+)$")
        local host = string.match(rest, "^([^/]+)")
        if host then
            return protocol .. "://" .. host
        end
    end
    return ""
end

-- Парсинг относительных ссылок
function Browser.resolveUrl(base, relative)
    if string.find(relative, "://") then
        return relative -- абсолютная ссылка
    end
    
    if string.sub(relative, 1, 2) == "//" then
        return "http:" .. relative
    end
    
    if string.sub(relative, 1, 1) == "/" then
        local protocol, host = string.match(base, "^(.-://[^/]+)")
        if protocol and host then
            return protocol .. host .. relative
        end
    end
    
    -- Относительная ссылка
    local basePath = string.match(base, "^(.-/)[^/]*$") or ""
    return basePath .. relative
end

-- Загрузка страницы
function Browser.loadPage(url, forceReload)
    if Browser.loading then return end
    
    url = Browser.urlEncode(url)
    if not string.find(url, "://") then
        url = "http://" .. url
    end
    
    Browser.url = url
    Browser.baseUrl = Browser.getBaseUrl(url)
    Browser.loading = true
    Browser.scrollY = 0
    Browser.links = {}
    Browser.images = {}
    
    -- Проверка кэша
    if not forceReload and Browser.cache[url] then
        Browser.content = Browser.cache[url]
        Browser.parseContent()
        Browser.loading = false
        return
    end
    
    -- Загрузка
    local result = net.get(url)
    
    if result and result.ok and result.body then
        Browser.content = result.body
        Browser.cache[url] = result.body
        Browser.parseContent()
        
        -- Добавление в историю
        if Browser.history[Browser.historyIndex] ~= url then
            table.insert(Browser.history, url)
            Browser.historyIndex = #Browser.history
        end
    else
        Browser.content = "<h1>Error loading page</h1>"
        if result and result.err then
            Browser.content = Browser.content .. "<p>" .. result.err .. "</p>"
        end
    end
    
    Browser.loading = false
end

-- Простой парсер HTML (только базовые теги)
function Browser.parseContent()
    -- Удаляем скрипты и стили
    local content = string.gsub(Browser.content, "<script[^>]*>.-</script>", "")
    content = string.gsub(content, "<style[^>]*>.-</style>", "")
    content = string.gsub(content, "<noscript[^>]*>.-</noscript>", "")
    
    -- Заменяем теги на простые аналоги
    content = string.gsub(content, "<br%s*/?>", "\n")
    content = string.gsub(content, "<p[^>]*>", "\n")
    content = string.gsub(content, "</p>", "\n\n")
    content = string.gsub(content, "<div[^>]*>", "\n")
    content = string.gsub(content, "</div>", "\n")
    content = string.gsub(content, "<h1[^>]*>", "\n\n=== ")
    content = string.gsub(content, "</h1>", " ===\n\n")
    content = string.gsub(content, "<h2[^>]*>", "\n\n== ")
    content = string.gsub(content, "</h2>", " ==\n\n")
    content = string.gsub(content, "<h3[^>]*>", "\n\n= ")
    content = string.gsub(content, "</h3>", " =\n\n")
    content = string.gsub(content, "<li[^>]*>", " • ")
    content = string.gsub(content, "</li>", "\n")
    content = string.gsub(content, "<ul[^>]*>", "\n")
    content = string.gsub(content, "</ul>", "\n")
    content = string.gsub(content, "<ol[^>]*>", "\n")
    content = string.gsub(content, "</ol>", "\n")
    
    -- Извлекаем ссылки
    local linkIndex = 1
    for link, text in string.gmatch(content, '<a[^>]*href="([^"]*)"[^>]*>([^<]*)</a>') do
        if link and text and link ~= "" then
            local fullUrl = Browser.resolveUrl(Browser.url, Browser.urlDecode(link))
            Browser.links[linkIndex] = {url = fullUrl, text = text}
            content = string.gsub(content, '<a[^>]*href="' .. link:gsub("([%%%[%]%^%$%*%+%-%?%.%(%)])", "%%%1") .. '"[^>]*>' .. text:gsub("([%%%[%]%^%$%*%+%-%?%.%(%)])", "%%%1") .. '</a>', 
                "[" .. linkIndex .. "]")
            linkIndex = linkIndex + 1
        end
    end
    
    -- Извлекаем изображения
    local imgIndex = 1
    for img in string.gmatch(content, '<img[^>]*src="([^"]*)"') do
        if img and img ~= "" then
            local fullUrl = Browser.resolveUrl(Browser.url, Browser.urlDecode(img))
            Browser.images[imgIndex] = {url = fullUrl, loaded = false, data = nil}
            content = string.gsub(content, '<img[^>]*src="' .. img:gsub("([%%%[%]%^%$%*%+%-%?%.%(%)])", "%%%1") .. '"[^>]*>', 
                "\n[Image " .. imgIndex .. "]\n")
            imgIndex = imgIndex + 1
        end
    end
    
    -- Удаляем остальные HTML теги
    content = string.gsub(content, "<[^>]+>", "")
    
    -- Заменяем HTML сущности
    content = string.gsub(content, "&lt;", "<")
    content = string.gsub(content, "&gt;", ">")
    content = string.gsub(content, "&amp;", "&")
    content = string.gsub(content, "&quot;", "\"")
    content = string.gsub(content, "&#(%d+);", function(n)
        return string.char(tonumber(n))
    end)
    
    Browser.content = content
end

-- Загрузка изображения
function Browser.loadImage(index)
    if not Browser.images[index] or Browser.images[index].loaded then
        return
    end
    
    local img = Browser.images[index]
    local url = img.url
    
    -- Скачиваем во временный файл
    local tempFile = "/temp_img.jpg"
    
    local function downloadCallback(loaded, total)
        -- Можно добавить индикатор загрузки
    end
    
    local success = net.download(url, tempFile, "flash", downloadCallback)
    
    if success then
        img.loaded = true
        img.data = tempFile
    end
end

-- Функция для безопасного переноса строк
function Browser.wrapText(text, maxChars)
    local lines = {}
    local words = {}
    
    -- Разбиваем на слова
    for word in string.gmatch(text, "%S+") do
        table.insert(words, word)
    end
    
    local currentLine = ""
    for i, word in ipairs(words) do
        if #currentLine + #word + 1 <= maxChars then
            if currentLine ~= "" then
                currentLine = currentLine .. " " .. word
            else
                currentLine = word
            end
        else
            if currentLine ~= "" then
                table.insert(lines, currentLine)
            end
            if #word > maxChars then
                -- Разбиваем очень длинное слово
                while #word > maxChars do
                    table.insert(lines, string.sub(word, 1, maxChars))
                    word = string.sub(word, maxChars + 1)
                end
                if #word > 0 then
                    currentLine = word
                else
                    currentLine = ""
                end
            else
                currentLine = word
            end
        end
    end
    
    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end
    
    return lines
end

-- Отрисовка страницы
function Browser.drawPage()
    local scrollY = Browser.scrollY
    local x, y = 10, 50 - scrollY
    local lineHeight = 20
    local maxChars = math.floor((Browser.screenW - 20) / 6) -- 6 пикселей на символ
    
    -- Фон
    ui.rect(0, 0, Browser.screenW, Browser.screenH, 0x0000)
    
    -- Панель URL
    ui.rect(0, 0, Browser.screenW, 40, 0x2104)
    
    -- Обрезаем URL если слишком длинный
    local displayUrl = Browser.url
    if #displayUrl > 50 then
        displayUrl = "..." .. string.sub(displayUrl, #displayUrl - 47)
    end
    ui.text(5, 12, displayUrl, 1, 0xFFFF)
    
    if Browser.loading then
        ui.text(Browser.screenW - 60, 12, "Loading...", 1, 0x07E0)
    else
        ui.text(Browser.screenW - 60, 12, "Ready", 1, 0xF800)
    end
    
    -- Кнопки навигации
    if ui.button(5, 45, 50, 30, "Back", 0x2104) then
        Browser.goBack()
    end
    
    if ui.button(60, 45, 50, 30, "Reload", 0x2104) then
        Browser.loadPage(Browser.url, true)
    end
    
    -- Поле ввода URL
    local inputX = 115
    if ui.input(inputX, 45, 200, 30, Browser.url, true) then
        -- Режим редактирования URL
        local newUrl = Browser.showKeyboard("Enter URL:", Browser.url)
        if newUrl and newUrl ~= "" then
            Browser.loadPage(newUrl)
        end
    end
    
    -- Кнопка Go
    if ui.button(320, 45, 85, 30, "Go", 0x001F) then
        Browser.loadPage(Browser.url)
    end
    
    -- Контент
    y = 85 - scrollY
    
    -- Разбиваем текст на строки с переносами
    local lines = {}
    for line in string.gmatch(Browser.content .. "\n", "(.-)\n") do
        local wrapped = Browser.wrapText(line, maxChars)
        for _, wrappedLine in ipairs(wrapped) do
            table.insert(lines, wrappedLine)
        end
        table.insert(lines, "") -- пустая строка между абзацами
    end
    
    -- Отрисовка текста
    for i, line in ipairs(lines) do
        if y >= -lineHeight and y < Browser.screenH then
            -- Проверяем ссылки [1], [2], etc
            local linkNum = string.match(line, "%[(%d+)%]")
            if linkNum then
                linkNum = tonumber(linkNum)
                if Browser.links[linkNum] then
                    -- Ограничиваем длину текста ссылки
                    local displayText = Browser.links[linkNum].text
                    if #displayText > maxChars then
                        displayText = string.sub(displayText, 1, maxChars - 3) .. "..."
                    end
                    
                    ui.text(x, y, displayText, 1, 0x07E0)
                    
                    -- Проверка клика
                    local tx, ty = ui.getTouch().x, ui.getTouch().y
                    if tx >= x and tx <= x + #displayText * 6 and
                       ty >= y and ty <= y + lineHeight and ui.getTouch().released then
                        Browser.loadPage(Browser.links[linkNum].url)
                        return -- Выходим из функции, чтобы избежать ошибок после перехода
                    end
                else
                    ui.text(x, y, line, 1, 0xFFFF)
                end
            -- Проверяем изображения
            elseif string.match(line, "^%[Image (%d+)%]$") then
                local imgNum = tonumber(string.match(line, "^%[Image (%d+)%]$"))
                if Browser.images[imgNum] then
                    if not Browser.images[imgNum].loaded then
                        ui.text(x, y, "[Loading image...]", 1, 0xF800)
                        Browser.loadImage(imgNum)
                    else
                        -- Пытаемся отобразить изображение
                        if ui.drawJPEG(x, y, Browser.images[imgNum].data) then
                            y = y + 100  -- Пропускаем место под изображение
                        else
                            ui.text(x, y, "[Image failed to load]", 1, 0xF800)
                        end
                    end
                else
                    ui.text(x, y, line, 1, 0xFFFF)
                end
            else
                ui.text(x, y, line, 1, 0xFFFF)
            end
        end
        y = y + lineHeight
        
        -- Прерываем если вышли за пределы экрана
        if y > Browser.screenH + scrollY + 100 then
            break
        end
    end
    
    -- Полоса прокрутки
    local contentHeight = #lines * lineHeight
    if contentHeight > Browser.screenH - 85 then
        local scrollHeight = math.max(10, (Browser.screenH - 85) * (Browser.screenH - 85) / contentHeight)
        local scrollPos = (Browser.screenH - 85 - scrollHeight) * scrollY / math.max(1, contentHeight - (Browser.screenH - 85))
        
        ui.rect(Browser.screenW - 5, 85, 5, Browser.screenH - 85, 0x4208)
        ui.rect(Browser.screenW - 5, 85 + scrollPos, 5, scrollHeight, 0x7BEF)
    end
    
    -- Прокрутка касанием
    local tx, ty = ui.getTouch().x, ui.getTouch().y
    local touching = ui.getTouch().touching
    
    if touching then
        if Browser.lastTouchY ~= 0 then
            local delta = ty - Browser.lastTouchY
            Browser.scrollY = Browser.scrollY - delta
        end
        Browser.lastTouchY = ty
    else
        Browser.lastTouchY = 0
    end
    
    -- Ограничение прокрутки
    local maxScroll = math.max(0, contentHeight - (Browser.screenH - 85))
    if Browser.scrollY < 0 then Browser.scrollY = 0 end
    if Browser.scrollY > maxScroll then Browser.scrollY = maxScroll end
    
    -- Кнопки внизу
    if ui.button(5, Browser.screenH - 35, 100, 30, "Home", 0x2104) then
        Browser.loadPage("http://www.google.com")
    end
    
    if ui.button(110, Browser.screenH - 35, 100, 30, "History", 0x2104) then
        Browser.showHistory()
    end
    
    if ui.button(215, Browser.screenH - 35, 100, 30, "Bookmarks", 0x2104) then
        Browser.showBookmarks()
    end
    
    if ui.button(320, Browser.screenH - 35, 85, 30, "Clear Cache", 0x001F) then
        Browser.cache = {}
        ui.unloadAll()
        fs.remove("/temp_img.jpg")
    end
end

-- Клавиатура для ввода
function Browser.showKeyboard(title, default)
    local input = default or ""
    local active = true
    
    -- Раскладка клавиатуры для URL
    local keys = {
        "q", "w", "e", "r", "t", "y", "u", "i", "o", "p",
        "a", "s", "d", "f", "g", "h", "j", "k", "l",
        "z", "x", "c", "v", "b", "n", "m",
        ".", "/", ":", "-", "_", "=",
        "BACK", "SPACE", "ENTER"
    }
    
    while active do
        -- Фон
        ui.rect(0, 0, Browser.screenW, Browser.screenH, 0x0000)
        ui.rect(0, 0, Browser.screenW, 40, 0x2104)
        ui.text(10, 12, title, 1, 0xFFFF)
        
        -- Показываем ввод (обрезаем если слишком длинный)
        local displayInput = input
        if #displayInput > 60 then
            displayInput = "..." .. string.sub(displayInput, #displayInput - 57)
        end
        ui.text(10, 50, displayInput, 2, 0xFFFF)
        
        -- Клавиши
        local keyW = 35
        local keyH = 35
        local startX = 10
        local startY = 100
        
        for i, key in ipairs(keys) do
            local row = math.floor((i-1) / 10)
            local col = (i-1) % 10
            
            -- Корректировка для разных рядов
            if row == 1 then col = col + 1 end  -- второй ряд смещен
            if row == 2 then col = col + 2 end  -- третий ряд смещен больше
            
            local x = startX + col * (keyW + 5)
            local y = startY + row * (keyH + 5)
            
            if key == "BACK" then
                x = 10
                y = startY + 4 * (keyH + 5)
                keyW = 80
                if ui.button(x, y, keyW, keyH, key, 0xF800) then
                    input = string.sub(input, 1, -2)
                end
            elseif key == "SPACE" then
                x = 95
                y = startY + 4 * (keyH + 5)
                keyW = 120
                if ui.button(x, y, keyW, keyH, key, 0x2104) then
                    input = input .. " "
                end
            elseif key == "ENTER" then
                x = 220
                y = startY + 4 * (keyH + 5)
                keyW = 80
                if ui.button(x, y, keyW, keyH, key, 0x07E0) then
                    active = false
                    return input
                end
            else
                if ui.button(x, y, keyW, keyH, key, 0x2104) then
                    input = input .. key
                end
            end
        end
        
        -- Кнопка Cancel
        if ui.button(305, startY + 4 * (keyH + 5), 95, keyH, "CANCEL", 0x001F) then
            active = false
            return nil
        end
        
        ui.flush()
    end
    
    return input
end

-- История посещений
function Browser.showHistory()
    local scrollY = 0
    local active = true
    
    while active do
        ui.rect(0, 0, Browser.screenW, Browser.screenH, 0x0000)
        ui.rect(0, 0, Browser.screenW, 40, 0x2104)
        ui.text(10, 12, "History", 2, 0xFFFF)
        
        scrollY = ui.beginList(0, 40, Browser.screenW, Browser.screenH - 40, scrollY, #Browser.history * 30)
        
        for i, url in ipairs(Browser.history) do
            local y = (i-1) * 30
            ui.rect(5, y, Browser.screenW - 10, 28, 0x2104)
            
            -- Обрезаем URL для отображения
            local displayUrl = url
            if #displayUrl > 50 then
                displayUrl = string.sub(displayUrl, 1, 47) .. "..."
            end
            ui.text(10, y + 5, displayUrl, 1, 0xFFFF)
            
            -- Клик по истории
            local tx, ty = ui.getTouch().x, ui.getTouch().y
            if tx >= 5 and tx <= Browser.screenW - 5 and
               ty >= 40 + y - scrollY and ty <= 40 + y + 28 - scrollY and
               ui.getTouch().released then
                Browser.loadPage(url)
                active = false
                return
            end
        end
        
        ui.endList()
        
        -- Кнопка закрытия
        if ui.button(10, Browser.screenH - 40, Browser.screenW - 20, 30, "Close", 0x001F) then
            active = false
        end
        
        ui.flush()
    end
end

-- Закладки
function Browser.showBookmarks()
    local bookmarks = {
        {name = "Google", url = "http://www.google.com"},
        {name = "Wikipedia", url = "http://www.wikipedia.org"},
        {name = "GitHub", url = "http://www.github.com"},
        {name = "Reddit", url = "http://www.reddit.com"},
        {name = "Hacker News", url = "http://news.ycombinator.com"},
        {name = "DuckDuckGo", url = "http://duckduckgo.com"},
        {name = "Archive.org", url = "http://archive.org"},
        {name = "Project Gutenberg", url = "http://www.gutenberg.org"}
    }
    
    local scrollY = 0
    local active = true
    
    while active do
        ui.rect(0, 0, Browser.screenW, Browser.screenH, 0x0000)
        ui.rect(0, 0, Browser.screenW, 40, 0x2104)
        ui.text(10, 12, "Bookmarks", 2, 0xFFFF)
        
        scrollY = ui.beginList(0, 40, Browser.screenW, Browser.screenH - 80, scrollY, #bookmarks * 40)
        
        for i, bm in ipairs(bookmarks) do
            local y = (i-1) * 40
            ui.rect(5, y, Browser.screenW - 10, 38, 0x2104)
            ui.text(10, y + 5, bm.name, 1, 0xFFFF)
            
            -- Обрезаем URL для отображения
            local displayUrl = bm.url
            if #displayUrl > 45 then
                displayUrl = string.sub(displayUrl, 1, 42) .. "..."
            end
            ui.text(10, y + 20, displayUrl, 1, 0x7BEF)
            
            -- Клик по закладке
            local tx, ty = ui.getTouch().x, ui.getTouch().y
            if tx >= 5 and tx <= Browser.screenW - 5 and
               ty >= 40 + y - scrollY and ty <= 40 + y + 38 - scrollY and
               ui.getTouch().released then
                Browser.loadPage(bm.url)
                active = false
                return
            end
        end
        
        ui.endList()
        
        -- Кнопки
        if ui.button(10, Browser.screenH - 75, Browser.screenW - 20, 30, "Add Current", 0x07E0) then
            -- Здесь можно добавить текущую страницу в закладки
            local name = Browser.url
            if #name > 20 then
                name = string.sub(name, 1, 17) .. "..."
            end
            table.insert(bookmarks, {name = name, url = Browser.url})
        end
        
        if ui.button(10, Browser.screenH - 40, Browser.screenW - 20, 30, "Close", 0x001F) then
            active = false
        end
        
        ui.flush()
    end
end

-- Навигация назад
function Browser.goBack()
    if Browser.historyIndex > 1 then
        Browser.historyIndex = Browser.historyIndex - 1
        Browser.loadPage(Browser.history[Browser.historyIndex], true)
    end
end

-- Навигация вперед
function Browser.goForward()
    if Browser.historyIndex < #Browser.history then
        Browser.historyIndex = Browser.historyIndex + 1
        Browser.loadPage(Browser.history[Browser.historyIndex], true)
    end
end

-- Главная функция браузера
function Browser.run()
    -- Начальная страница
    if Browser.url == "" then
        Browser.loadPage("www.google.com")
    end
    
    -- Главный цикл
    while true do
        Browser.drawPage()
        ui.flush()
    end
end

-- Запуск браузера при старте
Browser.run()
