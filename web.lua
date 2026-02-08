local SCR_W = 410
local SCR_H = 502

local STYLES = {
    h1 = {size = 3, color = 0xF800},
    h2 = {size = 2, color = 0xFDA0},
    text = {size = 1, color = 0xFFFF},
    link = {size = 1, color = 0x001F}
}

local browser = {
    url = "http://google.com",
    elements = {},
    scroll = 0,
    history = {},
    show_kbd = false
}

-- Функция безопасного разбиения текста
local function wrap_text(text, limit)
    local lines = {}
    if not text or text == "" then return lines end
    text = text:gsub("%s+", " ") -- убираем лишние пробелы и переносы
    while #text > limit do
        table.insert(lines, text:sub(1, limit))
        text = text:sub(limit + 1)
    end
    if #text > 0 then table.insert(lines, text) end
    return lines
end

local function draw_loading(status)
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
    ui.text(120, 200, "LOADING...", 2, 0xFFFF)
    if status then ui.text(10, 250, tostring(status):sub(-45), 1, 0x7BEF) end
    ui.flush()
end

local function resolve(path)
    if not path or path:sub(1,4) == "http" then return path end
    local proto, host = browser.url:match("(https?://)([^/]+)")
    if not proto then proto = "http://" host = browser.url:match("([^/]+)") end
    if not host then return path end
    if path:sub(1,1) == "/" then return proto .. host .. path end
    return browser.url:match("(.*)/") .. "/" .. path
end

-- ПОЛНОСТЬЮ ПЕРЕРАБОТАННЫЙ ПАРСЕР
local function parse_html(html)
    browser.elements = {}
    if not html then return end
    
    -- Очистка
    html = html:gsub("<script.-</script>", "")
    html = html:gsub("<style.-</style>", "")
    html = html:gsub("<!%-%-.-%-%->", "")
    
    local pos = 1
    while pos <= #html do
        -- Ищем любую угловую скобку
        local start_tag, end_tag = html:find("<[^>]+>", pos)
        
        -- Весь текст ДО тега
        local text_chunk = html:sub(pos, (start_tag or 0) - 1)
        if #text_chunk > 0 then
            local lines = wrap_text(text_chunk, 45)
            for _, line in ipairs(lines) do
                if line:match("%S") then -- только если есть не пробельные символы
                    table.insert(browser.elements, {type="text", val=line})
                end
            end
        end

        if not start_tag then break end

        -- Извлекаем содержимое тега БЕЗ скобок
        local tag_content = html:sub(start_tag + 1, end_tag - 1)
        local tag_name = tag_content:match("^(%/?%w+)")
        if tag_name then
            tag_name = tag_name:lower()
            
            if tag_name:match("h[1-3]") then
                local h_end = html:find("</" .. tag_name .. ">", end_tag)
                if h_end then
                    table.insert(browser.elements, {type="header", level=tag_name:sub(2,2), val=html:sub(end_tag + 1, h_end - 1)})
                    end_tag = h_end + #tag_name + 3
                end
            elseif tag_name == "a" then
                local href = tag_content:match("href=\"([^\"]+)\"") or tag_content:match("href='([^']+)'")
                local a_end = html:find("</a>", end_tag)
                if a_end then
                    table.insert(browser.elements, {type="link", val=html:sub(end_tag+1, a_end-1), url=href})
                    end_tag = a_end + 4
                end
            elseif tag_name == "img" then
                local src = tag_content:match("src=\"([^\"]+)\"") or tag_content:match("src='([^']+)'")
                if src and src:lower():find(".jp") then
                    table.insert(browser.elements, {type="img", src=src})
                end
            end
        end
        pos = end_tag + 1
    end
end

function navigate(new_url, save_history)
    if not new_url or new_url == "" then return end
    if save_history then table.insert(browser.history, browser.url) end
    
    draw_loading(new_url)
    collectgarbage("collect")
    
    local res = net.get(new_url)
    if res and res.ok then
        browser.url = new_url
        parse_html(res.body)
        
        -- Картинки
        if fs.exists("/web/img.jpg") then fs.remove("/web/img.jpg") end
        for _, el in ipairs(browser.elements) do
            if el.type == "img" then
                net.download(resolve(el.src), "/web/img.jpg", "flash")
                break
            end
        end
    else
        local err_msg = res and (res.err or tostring(res.code)) or "No response"
        browser.elements = {{type="header", level="1", val="Error"}, {type="text", val=err_msg}}
    end
end

-- T9
local t9 = { keys = {["2"]="abc",["3"]="def",["4"]="ghi",["5"]="jkl",["6"]="mno",["7"]="pqrs",["8"]="tuv",["9"]="wxyz",["0"]=". /:"}, last="", idx=1, time=0 }
function handle_t9(k)
    local now = hw.millis()
    if t9.last == k and (now - t9.time) < 800 then
        browser.url = browser.url:sub(1,-2)
        t9.idx = t9.idx % #t9.keys[k] + 1
    else t9.idx = 1 end
    browser.url = browser.url .. t9.keys[k]:sub(t9.idx, t9.idx)
    t9.last, t9.time = k, now
end

function loop()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)
    
    -- UI: Шапка
    if ui.button(5, 5, 50, 40, "<", 0x3333) then
        if #browser.history > 0 then navigate(table.remove(browser.history), false) end
    end
    if ui.button(60, 5, 275, 40, browser.url:sub(-22), 0x18C3) then browser.show_kbd = not browser.show_kbd end
    if ui.button(340, 5, 65, 40, "GO", 0x07E0) then navigate(browser.url, true) end

    -- Список
    browser.scroll = ui.beginList(0, 50, SCR_W, 452, 38, browser.scroll)
    for i, el in ipairs(browser.elements) do
        if el.type == "header" then
            local s = STYLES["h"..el.level] or STYLES.h1
            ui.text(10, 0, tostring(el.val), s.size, s.color)
        elseif el.type == "text" then
            ui.text(10, 0, tostring(el.val), 1, 0xFFFF)
        elseif el.type == "link" then
            if ui.button(10, 0, 380, 32, "> "..tostring(el.val):sub(1,35), 0x001F) then
                navigate(resolve(el.url), true)
            end
        elseif el.type == "img" then
            if fs.exists("/web/img.jpg") then ui.drawJPEG(10, 0, "/web/img.jpg") 
            else ui.text(10, 0, "[IMAGE]", 1, 0x07E0) end
        end
    end
    ui.endList()

    -- Клавиатура
    if browser.show_kbd then
        ui.rect(0, 220, SCR_W, 282, 0x0000)
        local keys = {"1","2","3","4","5","6","7","8","9","CLR","0","DEL"}
        for i, k in ipairs(keys) do
            local x, y = 10 + ((i-1)%3)*135, 230 + math.floor((i-1)/3)*65
            if ui.button(x, y, 120, 55, k, 0x4444) then
                if k == "DEL" then browser.url = browser.url:sub(1,-2)
                elseif k == "CLR" then browser.url = ""
                elseif t9.keys[k] then handle_t9(k) end
            end
        end
    end
    ui.flush()
end

fs.mkdir("/web")
navigate(browser.url, false)
while true do loop() end
