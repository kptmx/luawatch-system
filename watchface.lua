// Добавьте этот код в main.lua или как отдельный модуль

-- Простая читалка текстовых файлов
TextReader = {
    -- Состояние
    currentFile = nil,
    totalLines = 0,
    currentPage = 0,
    totalPages = 0,
    linesPerPage = 30, -- подберите под размер шрифта
    
    -- Виртуальный скролл
    scrollY = 150, -- начальная позиция (центр)
    targetScroll = 150,
    velocity = 0,
    
    -- Кэш страниц
    cache = {},
    cacheSize = 3, -- храним 3 страницы (prev, current, next)
    
    -- UI элементы
    fileBrowserActive = false,
    files = {},
    browserScroll = 0,
    selectedFS = "sd", -- "sd" или "flash"
    
    -- Инициализация
    new = function(self, path, fsType)
        local o = {}
        setmetatable(o, self)
        self.__index = self
        
        o:loadFile(path, fsType)
        return o
    end,
    
    -- Загрузка файла
    loadFile = function(self, path, fsType)
        self.currentFile = path
        self.currentFS = fsType or "sd"
        self.currentPage = 0
        self.cache = {}
        self.scrollY = 150
        self.targetScroll = 150
        
        -- Получаем размер файла
        local size = 0
        if self.currentFS == "sd" then
            size = sd.size(path)
        else
            size = fs.size(path)
        end
        
        if size and size > 0 then
            -- Читаем первую страницу для подсчета строк
            local content = self:readPage(0)
            if content then
                -- Подсчитываем количество строк в файле
                local _, count = content:gsub("\n", "\n")
                self.totalLines = count
                self.totalPages = math.ceil(self.totalLines / self.linesPerPage)
            end
        end
    end,
    
    -- Чтение конкретной страницы
    readPage = function(self, pageNum)
        if pageNum < 0 or pageNum >= self.totalPages then
            return nil
        end
        
        -- Проверяем кэш
        if self.cache[tostring(pageNum)] then
            return self.cache[tostring(pageNum)]
        end
        
        -- Читаем из файла
        local content = ""
        local startLine = pageNum * self.linesPerPage + 1
        local endLine = math.min(startLine + self.linesPerPage - 1, self.totalLines)
        
        if self.currentFS == "sd" then
            local data = sd.readBytes(self.currentFile)
            if data then
                content = self:extractLines(data, startLine, endLine)
            end
        else
            local data = fs.readBytes(self.currentFile)
            if data then
                content = self:extractLines(data, startLine, endLine)
            end
        end
        
        -- Кэшируем
        if #self.cache >= self.cacheSize then
            -- Удаляем самую старую запись
            for k,_ in pairs(self.cache) do
                self.cache[k] = nil
                break
            end
        end
        self.cache[tostring(pageNum)] = content
        
        return content
    end,
    
    -- Извлечение строк из текста
    extractLines = function(self, text, startLine, endLine)
        local lines = {}
        local idx = 1
        local lineNum = 1
        
        for line in text:gmatch("([^\n]*)\n?") do
            if lineNum >= startLine and lineNum <= endLine then
                table.insert(lines, line)
            elseif lineNum > endLine then
                break
            end
            lineNum = lineNum + 1
        end
        
        return table.concat(lines, "\n")
    end,
    
    -- Обновление страницы при доводке
    updatePageCenter = function(self)
        -- Определяем страницу по позиции скролла
        local pageHeight = 375 -- высота области просмотра
        local virtualHeight = self.totalPages * pageHeight -- виртуальная высота в 3 раза больше реальной
        
        local virtualPos = self.scrollY
        local targetPage = math.floor((virtualPos - 75) / pageHeight) -- 75 = начальный оффсет
        
        if targetPage < 0 then targetPage = 0 end
        if targetPage >= self.totalPages then targetPage = self.totalPages - 1 end
        
        if targetPage ~= self.currentPage then
            self.currentPage = targetPage
            -- Предзагружаем соседние страницы
            self:readPage(self.currentPage - 1)
            self:readPage(self.currentPage)
            self:readPage(self.currentPage + 1)
        end
    end,
    
    -- Отрисовка страницы
    drawPage = function(self, pageNum, offsetY)
        if pageNum < 0 or pageNum >= self.totalPages then
            -- Пустая страница (за пределами файла)
            return
        end
        
        local content = self:readPage(pageNum)
        if content then
            local y = 65 + offsetY
            local lineNum = 1
            
            for line in content:gmatch("([^\n]+)") do
                if y + lineNum * 20 >= 65 and y + lineNum * 20 <= 440 then
                    ui.text(10, y + lineNum * 20, line, 2, 65535)
                end
                lineNum = lineNum + 1
            end
        end
    end,
    
    -- Отрисовка файлового браузера
    drawFileBrowser = function(self)
        ui.rect(0, 0, 410, 502, 0)
        ui.text(80, 20, "File Browser", 3, 2016)
        
        -- Переключатель SD/Flash
        if ui.button(20, 60, 100, 35, "SD", self.selectedFS == "sd" and 1040 or 8452) then
            self.selectedFS = "sd"
            self:refreshFileList()
        end
        if ui.button(130, 60, 100, 35, "FLASH", self.selectedFS == "flash" and 1040 or 8452) then
            self.selectedFS = "flash"
            self:refreshFileList()
        end
        
        -- Кнопка "Назад"
        if ui.button(300, 60, 90, 35, "BACK", 63488) then
            self.fileBrowserActive = false
        end
        
        -- Список файлов
        local scroll = ui.beginList(5, 105, 400, 350, self.browserScroll, 800)
        
        local y = 10
        for i, file in ipairs(self.files) do
            -- Определяем иконку
            local icon = file:match("%.txt$") and "📄 " or "📁 "
            
            if ui.button(10, y, 380, 35, icon .. file, 2113) then
                if file:match("%.txt$") then
                    -- Открываем файл
                    self:loadFile(file, self.selectedFS)
                    self.fileBrowserActive = false
                else
                    -- Заходим в папку (TODO)
                end
            end
            y = y + 40
        end
        
        ui.endList()
        self.browserScroll = scroll
    end,
    
    -- Обновление списка файлов
    refreshFileList = function(self)
        self.files = {}
        local list = {}
        
        if self.selectedFS == "sd" then
            list = sd.list("/")
        else
            list = fs.list("/")
        end
        
        if list and type(list) == "table" then
            -- Сортируем: папки, потом файлы
            local dirs, files = {}, {}
            for i, name in ipairs(list) do
                if name:match("%.txt$") then
                    table.insert(files, name)
                else
                    table.insert(dirs, name)
                end
            end
            table.sort(dirs)
            table.sort(files)
            
            -- Объединяем
            for _, d in ipairs(dirs) do table.insert(self.files, d) end
            for _, f in ipairs(files) do table.insert(self.files, f) end
        end
    end,
    
    -- Основной рендер
    render = function(self)
        if self.fileBrowserActive then
            self:drawFileBrowser()
            return
        end
        
        if not self.currentFile then
            -- Показываем браузер по умолчанию
            self.fileBrowserActive = true
            self:refreshFileList()
            self:drawFileBrowser()
            return
        end
        
        -- Очистка
        ui.rect(0, 0, 410, 502, 0)
        
        -- Заголовок
        ui.text(10, 20, self.currentFile, 2, 2016)
        ui.text(300, 20, self.currentPage + 1 .. "/" .. self.totalPages, 2, 65535)
        
        -- Кнопка "Список файлов"
        if ui.button(300, 450, 90, 35, "FILES", 1040) then
            self.fileBrowserActive = true
            self:refreshFileList()
        end
        
        -- Область текста с виртуальным скроллом
        local pageHeight = 375 -- высота области просмотра
        local virtualHeight = self.totalPages * pageHeight * 3 -- виртуальная высота в 3 раза больше
        
        -- Скролл с инерцией
        ui.setListInertia(true)
        self.scrollY = ui.beginList(5, 65, 400, pageHeight, self.scrollY, virtualHeight)
        
        -- Отображаем три страницы
        local viewportCenter = self.scrollY + pageHeight/2
        local centerPage = math.floor(viewportCenter / pageHeight)
        
        -- Рисуем страницы: предыдущая (-1), текущая (0), следующая (+1)
        self:drawPage(centerPage - 1, (centerPage - 1) * pageHeight - self.scrollY)
        self:drawPage(centerPage, centerPage * pageHeight - self.scrollY)
        self:drawPage(centerPage + 1, (centerPage + 1) * pageHeight - self.scrollY)
        
        ui.endList()
        
        -- Доводчик к ближайшей странице
        if not ui.getTouch().touching then
            -- Рассчитываем целевую позицию (центр страницы)
            local targetPage = math.floor((self.scrollY + pageHeight/2) / pageHeight)
            self.targetScroll = targetPage * pageHeight + pageHeight/2 - pageHeight/2
            
            -- Плавное движение к цели
            local diff = self.targetScroll - self.scrollY
            if math.abs(diff) > 0.5 then
                self.scrollY = self.scrollY + diff * 0.25
            else
                self.scrollY = self.targetScroll
                -- Обновляем кэш когда остановились
                self:updatePageCenter()
            end
        end
    end
}

-- Глобальный экземпляр читалки
reader = nil

-- Основная функция draw
function draw()
    if not reader then
        reader = TextReader:new()
    end
    
    reader:render()
end

-- Инициализация (можно вызвать вручную для открытия конкретного файла)
function openFile(path, useSD)
    reader = TextReader:new(path, useSD and "sd" or "flash")
end

-- Очистка кэша при необходимости
function clearCache()
    if reader then
        reader.cache = {}
    end
end
