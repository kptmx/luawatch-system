-- Минимальная версия для теста
function draw()
    ui.text(100, 100, "e621 Test", 3, 0xFFFF)
    
    if ui.button(100, 200, 100, 50, "TEST", 0x07E0) then
        print("Button pressed")
        local res = net.get("https://e621.net/posts.json?tags=cat&limit=1")
        if res then
            print("Response code: " .. (res.code or "?"))
            print("Response length: " .. #(res.body or ""))
            print("First 500 chars:")
            print(string.sub(res.body or "", 1, 500))
        end
    end
end

init = function()
    print("Test version loaded")
end

init()
