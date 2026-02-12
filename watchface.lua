function draw()
    ui.rect(1, 1, 400, 400, 0x0000)
    touch = ui.getTouch()
    rect(touch.x, touch.y, 50, 50, 0xFFFF)
end
    
