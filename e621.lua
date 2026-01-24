-- Конфигурация
local SCR_W, SCR_H = 410, 502
local API_URL = "https://e621.net/posts.json?limit=10&tags=rating:s"
local img_path = "/e621_tmp.jpg"

-- Состояние
local posts = {}
local current_view = "list"
local selected_idx = 1
local is_loading = false
local scroll_y = 0
local status_msg = "Готов"

--- ### Самодельный парсер JSON
-- Ищет ID и URL образца (sample) в ответе API
function parseE621(json)
    local result = {}
    -- Находим массив "posts": [ ... ]
    local posts_content = string.match(json, '"posts":%s*%[(.*)%]%s*%}')
    if not posts_content then return result end

    -- Разбиваем на отдельные объекты постов (между { })
    for post_block in string.gmatch(posts_content, "{(.-)}") do
        local id = string.match(post_block, '"id":%s*(%d+)')
        -- Ищем URL в секции "sample" или "file". 
        -- Берем первый попавшийся подходящий URL в блоке поста.
        local url = string.match(post_block, '"url":%s*"(https://static1.e621.net/data/sample/.-%.jpg)"')
        
        if id and url then
            table.insert(result, {id = id, url = url})
        end
    end
    return result
end

function fetchPosts()
    is_loading = true
    status_msg = "Запрос к API..."
    local response = net.get(API_URL)
    
    if response.ok and response.body then
        posts = parseE621(response.body)
        status_msg = "Найдено: " .. #posts
    else
        status_msg = "Ошибка сети: " .. (response.err or response.code)
    end
    is_loading = false
end

function viewPost(idx)
    local post = posts[idx]
    if not post then return end
    
    is_loading = true
    status_msg = "Качаю картинку..."
    if net.download(post.url, img_path) then
        ui.unload(img_path) 
        current_view = "viewer"
    else
        status_msg = "Ошибка загрузки"
    end
    is_loading = false
end

-- Инициализация
fetchPosts()

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)

    if is_loading then
        ui.text(20, 240, status_msg, 2, 0x07E0)
        return
    end

    if current_view == "list" then
        drawList()
    else
        drawViewer()
    end
end

function drawList()
    ui.text(10, 10, "e621: Последнее (S)", 2, 0x52AA) -- Цвет e621
    
    -- Список
    local item_h = 70
    scroll_y = ui.beginList(0, 50, SCR_W, 380, scroll_y, #posts * item_h)
    
    for i, post in ipairs(posts) do
        local y = (i - 1) * item_h
        if ui.button(10, y + 5, 390, 60, "Post #" .. post.id, 0x4208) then
            selected_idx = i
            viewPost(i)
        end
    end
    ui.endList()

    -- Нижняя панель
    ui.rect(0, 440, SCR_W, 62, 0x18C3)
    ui.text(20, 455, status_msg, 2, 0xFFFF)
    if ui.button(300, 445, 100, 50, "Обн.", 0x07E0) then
        fetchPosts()
    end
end

function drawViewer()
    ui.drawJPEG_SD(0, 0, img_path)
    
    -- Кнопка назад поверх картинки
    if ui.button(10, 10, 80, 50, "<", 0x0000) then
        current_view = "list"
    end
end
