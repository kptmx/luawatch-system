-- simple_file_manager.lua
-- для запуска: переименовать в /main.lua или загрузить через bootstrap

local SCR_W = 410
local SCR_H = 502

local current_path = "/"
local files = {}
local selected_idx = 1
local scroll_y = 0
local mode = "list"   -- "list", "create", "edit", "run_confirm", "delete_confirm"

local new_filename = ""
local new_content  = ""
local edit_content = ""
local message = ""

local function refresh_files()
    files = fs.list(current_path) or {}
    table.sort(files)
    selected_idx = 1
end

local function is_lua_file(name)
    return name:lower():match("%.lua$") ~= nil
end

local function try_run_file(fullpath)
    local code = fs.load(fullpath)
    if not code or code == "" then
        message = "Файл пустой или ошибка чтения"
        return
    end

    local chunk, err = load(code, fullpath, "t")
    if not chunk then
        message = "Ошибка компиляции: " .. (err or "?")
        return
    end

    local ok, run_err = pcall(chunk)
    if not ok then
        message = "Ошибка выполнения: " .. (run_err or "?")
    else
        message = "Запущен ✓ (результат в консоли)"
    end
end

-- ────────────────────────────────────────────────
-- Инициализация
-- ────────────────────────────────────────────────
refresh_files()

function draw()
    ui.rect(0, 0, SCR_W, SCR_H, 0x0000)

    -- Заголовок + путь
    ui.text(10, 10, "Файлы: " .. current_path, 2, 0x07FF)
    ui.text(10, 35, message, 2, 0xFFFF00)
    message = ""  -- сбрасываем после показа

    if mode == "list" then
        -- Список файлов
        local item_height = 34
        local visible_count = math.floor((SCR_H - 120) / item_height)

        scroll_y = ui.beginList(10, 70, SCR_W-20, SCR_H-130, scroll_y, #files * item_height + 20)

        for i, fname in ipairs(files) do
            local y = (i-1) * item_height + 10
            local color = (i == selected_idx) and 0x001F or 0xFFFF
            local icon = (fs.exists(current_path .. fname .. "/") and "[DIR]") or (is_lua_file(fname) and "[LUA]") or "[   ]"
            ui.text(20, y, icon .. " " .. fname, 2, color)
        end

        ui.endList()

        -- Кнопки внизу
        if ui.button(10, SCR_H-100, 120, 45, "↑ Вверх", 0x07E0) then
            if current_path ~= "/" then
                current_path = current_path:match("^(.*)/[^/]+/?$") or "/"
                if current_path == "" then current_path = "/" end
                refresh_files()
            end
        end

        if ui.button(140, SCR_H-100, 120, 45, "Создать .lua", 0x07FF) then
            mode = "create"
            new_filename = ""
            new_content = ""
        end

        if #files > 0 then
            local sel_name = files[selected_idx]
            local is_dir = fs.exists(current_path .. sel_name .. "/")

            if ui.button(270, SCR_H-100, 120, 45, "Открыть / Запустить", 0xFFE0) then
                if is_dir then
                    current_path = current_path .. sel_name .. "/"
                    refresh_files()
                elseif is_lua_file(sel_name) then
                    mode = "run_confirm"
                else
                    mode = "edit"
                    edit_content = fs.load(current_path .. sel_name) or ""
                end
            end

            if ui.button(10, SCR_H-50, 190, 40, "Удалить " .. sel_name, 0xF800) then
                mode = "delete_confirm"
            end
        end

    elseif mode == "create" then
        ui.text(20, 80, "Имя файла (без .lua):", 2, 0xFFFF)
        if ui.input(20, 110, 370, 45, new_filename, true) then
            -- input всегда focused в этом режиме
        end
        new_filename = ui.input(20, 110, 370, 45, new_filename, true) and new_filename or new_filename

        ui.text(20, 170, "Начальное содержимое:", 2, 0xFFFF)
        if ui.input(20, 200, 370, 120, new_content, true) then
            -- тут можно было бы сделать многострочный, но пока однострочный
        end
        new_content = ui.input(20, 200, 370, 120, new_content, true) and new_content or new_content

        if ui.button(20, 340, 180, 50, "Сохранить", 0x07E0) then
            if new_filename == "" then
                message = "Имя не может быть пустым"
            else
                local fname = new_filename:match("[^%.]+$") == new_filename and new_filename .. ".lua" or new_filename
                local full = current_path .. fname
                local ok = fs.save(full, new_content or "")
                if ok then
                    message = "Создан: " .. fname
                    mode = "list"
                    refresh_files()
                else
                    message = "Ошибка сохранения"
                end
            end
        end

        if ui.button(210, 340, 180, 50, "Отмена", 0xF800) then
            mode = "list"
        end

    elseif mode == "edit" then
        local fname = files[selected_idx]
        ui.text(20, 80, "Редактируем: " .. fname, 2, 0x07FF)

        ui.text(20, 120, "Содержимое (дописать):", 2, 0xFFFF)
        local added = ui.input(20, 150, 370, 100, "", true)
        if added and added ~= "" then
            fs.append(current_path .. fname, "\n" .. added)
            edit_content = fs.load(current_path .. fname) or ""
            message = "Добавлено ✓"
        end

        ui.text(20, 270, "Текущее содержимое:", 2, 0xBDF7)
        ui.text(30, 300, edit_content:sub(1, 200) .. ( #edit_content > 200 and "..." or ""), 1, 0xFFFF)

        if ui.button(20, SCR_H-60, 180, 45, "Назад", 0x07E0) then
            mode = "list"
        end

    elseif mode == "run_confirm" then
        local fname = files[selected_idx]
        ui.text(40, 120, "Запустить скрипт?", 3, 0xFFFF)
        ui.text(40, 170, fname, 2, 0x07FF)

        if ui.button(40, 240, 160, 60, "ДА, запустить", 0x07E0) then
            try_run_file(current_path .. fname)
            mode = "list"
        end

        if ui.button(210, 240, 160, 60, "Нет", 0xF800) then
            mode = "list"
        end

    elseif mode == "delete_confirm" then
        local fname = files[selected_idx]
        ui.text(40, 120, "Удалить файл?", 3, 0xFFFF)
        ui.text(40, 170, fname, 2, 0xF800)

        if ui.button(40, 240, 160, 60, "ДА, удалить", 0xF800) then
            local full = current_path .. fname
            fs.remove(full)
            message = "Удалён: " .. fname
            mode = "list"
            refresh_files()
        end

        if ui.button(210, 240, 160, 60, "Нет", 0x07E0) then
            mode = "list"
        end
    end

    -- Навигация по списку (в режиме list)
    if mode == "list" and #files > 0 then
        if ui.button(SCR_W-80, SCR_H-100, 60, 45, "↓", 0xFFFF) then
            selected_idx = math.min(#files, selected_idx + 1)
        end
        if ui.button(SCR_W-80, SCR_H-150, 60, 45, "↑", 0xFFFF) then
            selected_idx = math.max(1, selected_idx - 1)
        end
    end
end
