-- Simple Web Browser for LuaWatch v2.0
local SW, SH = 410, 502

-- Состояние
local url_input = "https://"
local page_elements = {} -- Массив: {type="text|link|img", content="...", url="...", y=0, h=0}
local history = {}
local scroll_pos = 0
local max_scroll = 0
local loading = false
local current_title = "Web Browser"
local status_msg = "Ready"
local mode = "browse"
local zoom = 1.0

-- Папка для временных картинок
local TMP_DIR = "/tmp_web"
fs.mkdir(TMP_DIR)

-- Вспомогательная функция: превращение относительной ссылки в абсолютную
local function resolve_url(base, relative)
    if relative:match("^https?://") then return relative end
    local protocol, host = base:match("(https?://)([^/]+)")
    if relative:sub(1,1) == "/" then
        return protocol .. host .. relative
    else
        return base:match(".*/") .. relative
    end
end

-- Парсер HTML с поддержкой ссылок и картинок
function parse_html_v2(content, base_url)
    local elements = {}
    local current_y = 0
    local line_h = 22 * zoom
    
    current_title = content:match("<title[^>]*>(.-)</title>") or "Untitled"
    
    -- Очистка от скриптов и стилей
    content = content:gsub("<script[^>]*>.-</script>", "")
    content = content:gsub("<style[^>]*>.-</style>", "")
    
    -- Простейший итератор по тегам (очень упрощенно)
    -- Ищем <a>, <img> или просто текст
    local last_pos = 1
    for pos, tag, attr, body in content:gmatch("()<(%w+)([^>]* suburb)>([^<]*)") do
        -- (Это упрощенная логика, в реальности лучше использовать стэк тегов)
    end

    -- Версия "Line-by-Line" для ESP32:
    local body = content:match("<body[^>]*>(.-)</body>") or content
    
    -- Разделяем контент на блоки
    for line in body:gmatch("[^\n]+") do
        -- Ищем картинку: <img src="url">
        local img_src = line:match("<img.-src=\"([^\"]+)\"")
        if img_src then
            local full_img_url = resolve_url(base_url, img_src)
            local local_path = TMP_DIR .. "/" .. (img_src:match("[^/]+%.jpg") or "img.jpg")
            table.insert(elements, {type="img", url=full_img_url, path=local_path, y=current_y, h=150, loaded=false})
            current_y = current_y + 160
        end

        -- Ищем ссылку: <a href="url">text</a>
        local link_url, link_text = line:match("<a.-href=\"([^\"]+)\"[^>]*>(.-)</a>")
        if link_url then
            table.insert(elements, {type="link", url=resolve_url(base_url, link_url), content=link_text, y=current_y, h=line_h})
            current_y = current_y + line_h
        else
            -- Просто текст
            local plain = line:gsub("<[^>]+>", ""):gsub("&nbsp;", " ")
            if #plain > 0 then
                table.insert(elements, {type="text", content=plain, y=current_y, h=line_h})
                current_y = current_y + line_h
            end
        end
    end
    
    max_scroll = current_y
    return elements
end

-- Загрузка страницы
function load_page(url)
    if net.status() ~= 3 then status_msg = "No WiFi"; return end
    
    loading = true
    status_msg = "Fetching..."
    
    local res = net.get(url)
    if res and res.ok then
        -- Очистка старых картинок перед новой страницей
        local files = fs.list(TMP_DIR)
        for _, f in ipairs(files) do fs.remove(TMP_DIR .. "/" .. f) end
        
        page_elements = parse_html_v2(res.body, url)
        scroll_pos = 0
        status_msg = "Done"
        if #history == 0 or history[#history] ~= url then table.insert(history, url) end
    else
        status_msg = "Error: " .. (res.code or "conn")
    end
    loading = false
end

-- Отображение контента
function display_content()
    local view_y = 100
    local view_h = 350
    
    for _, el in ipairs(page_elements) do
        local screen_y = el.y - scroll_pos + view_y
        
        -- Отрисовываем только то, что в зоне видимости
        if screen_y + el.h > view_y and screen_y < view_y + view_h then
            if el.type == "text" then
                ui.text(10, screen_y, el.content:sub(1, 40), 1, 0xFFFF)
            elseif el.type == "link" then
                ui.text(10, screen_y, "> " .. el.content:sub(1, 35), 1, 0x07FF) -- Голубой для ссылок
                ui.rect(10, screen_y + 18, 300, 1, 0x07FF) -- Подчеркивание
            elseif el.type == "img" then
                if not el.loaded then
                    -- Пытаемся скачать картинку в фоне (упрощенно)
                    ui.rect(10, screen_y, 100, 100, 0x3333)
                    ui.text(15, screen_y + 40, "Loading IMG...", 1, 0x8410)
                    if net.download(el.url, el.path) then
                        el.loaded = true
                    end
                else
                    ui.drawJPEG(10, screen_y, el.path)
                end
            end
        end
    end
end

-- Обработка кликов по ссылкам
function check_links(tx, ty)
    if ty < 100 or ty > 450 then return end
    
    local world_y = ty - 100 + scroll_pos
    for _, el in ipairs(page_elements) do
        if el.type == "link" then
            if world_y >= el.y and world_y <= el.y + el.h then
                url_input = el.url
                load_page(el.url)
                return true
            end
        end
    end
    return false
end

-- Основной цикл
local last_touch = {touching = false}

function loop()
    local touch = ui.getTouch()
    
    if touch.touching then
        if not last_touch.touching then
            -- Проверяем нажатие на ссылку в момент касания
            check_links(touch.x, touch.y)
        end
        
        -- Скроллинг
        if last_touch.touching then
            local delta = last_touch.y - touch.y
            scroll_pos = math.max(0, math.min(max_scroll - 300, scroll_pos + delta * 2))
        end
    end
    last_touch = touch
end

function draw()
    ui.rect(0, 0, SW, SH, 0x0000)
    
    -- Шапка
    ui.rect(0, 0, SW, 60, 0x2104)
    if ui.button(10, 10, 60, 40, "BACK", 0x4208) and #history > 1 then
        table.remove(history)
        url_input = history[#history]
        load_page(url_input)
    end
    
    if ui.input(80, 10, 250, 40, url_input, false) then end
    if ui.button(340, 10, 60, 40, "GO", 0x07E0) then load_page(url_input) end

    -- Контент
    display_content()

    -- Статус-бар
    ui.rect(0, 460, SW, 42, 0x1082)
    ui.text(10, 470, status_msg, 1, 0x07E0)
    ui.text(300, 470, "RAM:" .. math.floor(hw.getFreePsram()/1024) .. "K", 1, 0xFFFF)
end

-- Стартовая страница
if not _G._INIT then
    load_page("https://www.google.com")
    _G._INIT = true
end
