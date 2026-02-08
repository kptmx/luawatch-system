-- Конфигурация и стили
local STYLES = {
    h1 = {size = 3, color = 0xF800}, -- Красный крупный
    h2 = {size = 2, color = 0xFDA0}, -- Оранжевый
    h3 = {size = 2, color = 0xFFE0}, -- Желтый
    text = {size = 1, color = 0xFFFF},
    link = {size = 1, color = 0x001F}, -- Синий
    img = {size = 1, color = 0x07E0}   -- Зеленый
}

local browser = {
    url = "http://example.com",
    elements = {},
    scroll = 0,
    history = {},
    loading = false,
    show_kbd = false
}

-- Функция отображения индикатора загрузки
local function draw_loading(status)
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
    ui.text(SCR_W/2 - 50, SCR_H/2 - 20, "LOADING...", 2, 0xFFFF)
    ui.text(SCR_W/2 - 80, SCR_H/2 + 20, status or "", 1, 0x7BEF)
    ui.flush()
end

-- Резолв ссылок
local function resolve(path)
    if not path then return "" end
    if path:sub(1,4) == "http" then return path end
    local proto, host = browser.url:match("(https?://)([^/]+)")
    if path:sub(1,1) == "/" then return proto .. host .. path end
    return browser.url:match("(.*)/") .. "/" .. path
end

-- Мощный парсер (идем по тегам через поиск)
local function parse_html(html)
    browser.elements = {}
    local pos = 1
    
    -- Предварительная очистка тяжелого мусора
    html = html:gsub("<script.-</script>", ""):gsub("<style.-</style>", ""):gsub("<!%-%-.-%-%->", "")

    while pos <= #html do
        -- Ищем начало любого тега
        local start_tag, end_tag, tag_body = html:find("<(%/?%w+.-)>", pos)
        
        -- Добавляем текст ПЕРЕД тегом
        if not start_tag then
            local plain = html:sub(pos):gsub("%s+", " ")
            if #plain > 1 then table.insert(browser.elements, {type="text", val=plain}) end
            break
        end
        
        local text_before = html:sub(pos, start_tag - 1):gsub("%s+", " ")
        if #text_before > 1 then
            table.insert(browser.elements, {type="text", val=text_before})
        end

        -- Разбор тега
        local tag_name = tag_body:match("^(%w+)"):lower()
        
        if tag_name:match("h[1-6]") then
            local h_lvl = tag_name:sub(2,2)
            local h_end = html:find("</" .. tag_name .. ">", end_tag)
            if h_end then
                local content = html:sub(end_tag + 1, h_end - 1)
                table.insert(browser.elements, {type="header", level=h_lvl, val=content})
                end_tag = h_end + #tag_name + 3
            end
        elseif tag_name == "a" then
            local href = tag_body:match("href=\"([^\"]+)\"")
            local a_end = html:find("</a>", end_tag)
            if a_end then
                local content = html:sub(end_tag + 1, a_end - 1)
                table.insert(browser.elements, {type="link", val=content, url=href})
                end_tag = a_end + 4
            end
        elseif tag_name == "img" then
            local src = tag_body:match("src=\"([^\"]+)\"")
            if src and (src:find(".jp") or src:find(".JP")) then
                table.insert(browser.elements, {type="img", src=src})
            end
        end

        pos = end_tag + 1
    end
end

function navigate(new_url)
    draw_loading(new_url) -- Рисуем сразу, так как net.get заблокирует поток
    
    local res = net.get(new_url)
    if res.ok then
        browser.url = new_url
        parse_html(res.body)
        -- Очистка старой картинки
        if fs.exists("/web/page.jpg") then fs.remove("/web/page.jpg") end
        
        -- Попытка скачать первую картинку
        for _, el in ipairs(browser.elements) do
            if el.type == "img" then
                draw_loading("Downloading image...")
                net.download(resolve(el.src), "/web/page.jpg", "flash")
                break
            end
        end
    else
        browser.elements = {{type="header", level="1", val="Error 404"}, {type="text", val=res.err or "Check connection"}}
    end
end

-- T9 Клавиатура
local t9 = {
    keys = {["2"]="abc",["3"]="def",["4"]="ghi",["5"]="jkl",["6"]="mno",["7"]="pqrs",["8"]="tuv",["9"]="wxyz",["0"]=". /:"},
    last = "", idx = 1, time = 0
}

function handle_t9(k)
    local now = hw.millis()
    if t9.last == k and (now - t9.time) < 800 then
        browser.url = browser.url:sub(1,-2)
        t9.idx = t9.idx % #t9.keys[k] + 1
    else t9.idx = 1 end
    browser.url = browser.url .. t9.keys[k]:sub(t9.idx, t9.idx)
    t9.last, t9.time = k, now
end

-- Главный цикл
function loop()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)

    -- URL Bar
    if ui.button(5, 5, 330, 40, browser.url, 0x18C3) then browser.show_kbd = not browser.show_kbd end
    if ui.button(340, 5, 65, 40, "GO", 0x07E0) then navigate(browser.url) end

    -- Content Area
    browser.scroll = ui.beginList(0, 50, SCR_W, 452, 40, browser.scroll)
    
    for i, el in ipairs(browser.elements) do
        if el.type == "header" then
            local s = STYLES["h" .. el.level] or STYLES.h1
            ui.text(10, 0, el.val, s.size, s.color)
        elseif el.type == "text" then
            ui.text(10, 0, el.val:sub(1, 100), 1, STYLES.text.color)
        elseif el.type == "link" then
            if ui.button(10, 0, 380, 35, "🔗 " .. el.val:sub(1, 40), STYLES.link.color) then
                table.insert(browser.history, browser.url)
                navigate(resolve(el.url))
            end
        elseif el.type == "img" then
            if fs.exists("/web/page.jpg") then
                ui.drawJPEG(10, 0, "/web/page.jpg")
            else
                ui.text(10, 0, "[IMG: "..el.src:sub(-10).."]", 1, STYLES.img.color)
            end
        end
    end
    ui.endList()

    -- Клавиатура
    if browser.show_kbd then
        ui.rect(0, 220, SCR_W, 282, 0x0000)
        local keys = {"1","2","3","4","5","6","7","8","9","CLR","0","DEL"}
        for i, k in ipairs(keys) do
            local x, y = 10 + ((i-1)%3)*135, 230 + math.floor((i-1)/3)*65
            if ui.button(x, y, 120, 55, k, 0x3333) then
                if k == "DEL" then browser.url = browser.url:sub(1,-2)
                elseif k == "CLR" then browser.url = ""
                elseif t9.keys[k] then handle_t9(k) end
            end
        end
    end

    ui.flush()
end

-- Запуск
fs.mkdir("/web")
navigate(browser.url)
while true do loop() end
