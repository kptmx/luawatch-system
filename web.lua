-- Simple Web Browser for ESP32-S3 with Touch and JPEG support
-- Dependencies: ui, net, fs (or sd), hw
-- Save as /browser.lua

local SCR_W, SCR_H = 410, 502
local FONT_H = 16  -- Approximate height for size 2 text
local LINE_H = 18  -- Line spacing

-- State
local url = "https://www.google.com"  -- Default test page with links and images
local raw_html = ""
local display_lines = {}
local links = {}          -- {url="...", title="..."}
local images = {}         -- {src="...", x, y, w, h, loaded=bool, path=...}
local scroll_y = 0
local max_scroll = 0
local loading = false
local status = "Ready"
local selected_link = nil  -- Index in links
local touch_start_y = nil
local is_scrolling = false
local velocity = 0

-- Simple HTML parser (extract text, links, images)
function parse_html(html)
  lines = {}
  links = {}
  images = {}
  -- Very naive parsing: split by < and >, handle tags
  local in_tag = false
  local token = ""
  local buf = ""
  local y = 10

  for c in html:gmatch(".") do
    if c == "<" then
      in_tag = true
      if #buf > 0 then
        -- Wrap text into lines
        local words = {}
        for w in buf:gmatch("%S+") do table.insert(words, w) end
        local line = ""
        for _, w in ipairs(words) do
          if #line == 0 then
            line = w
          elseif #line + #w + 1 < 50 then  -- crude line length limit
            line = line .. " " .. w
          else
            table.insert(lines, {type="text", text=line, y=y})
            y = y + LINE_H
            line = w
          end
        end
        if #line > 0 then
          table.insert(lines, {type="text", text=line, y=y})
          y = y + LINE_H
        end
        buf = ""
      end
      token = ""
    elseif c == ">" then
      in_tag = false
      token = token:lower()
      -- Handle <a href="...">
      local href = token:match('a%s+href=["\']([^"\']+)["\']')
      if href then
        local title = token:match('>(.-)</a>') or href
        table.insert(links, {url=href, title=title, y=y})
        table.insert(lines, {type="link", index=#links, y=y})
        y = y + LINE_H
      end
      -- Handle <img src="...">
      local src = token:match('img%s+src=["\']([^"\']+)["\']')
      if src then
        table.insert(images, {src=src, x=10, y=y, w=200, h=150, loaded=false, path=nil})
        y = y + 160
      end
      token = ""
    else
      if in_tag then
        token = token .. c
      else
        buf = buf .. c
      end
    end
  end
  -- Flush any trailing text
  if #buf > 0 then
    table.insert(lines, {type="text", text=buf, y=y})
    y = y + LINE_H
  end
  max_scroll = math.max(0, y - SCR_H + 40)
  scroll_y = 0
end

-- Load a URL
function load_page(u)
  url = u
  loading = true
  status = "Loading " .. url
  -- Unload previous images
  for _, img in ipairs(images) do
    if img.path then ui.unload(img.path) end
  end
  images = {}
  -- Fetch HTML
  local res = net.get(url)
  if not res or not res.ok then
    status = "Failed to load: " .. (res and res.code or "no response")
    loading = false
    return
  end
  raw_html = res.body
  parse_html(raw_html)
  -- Load images
  for i, img in ipairs(images) do
    local img_url = img.src
    if not img_url:find("://") then
      local base = url:match("^(.*/)") or ""
      img_url = base .. img_url
    end
    -- Download to flash
    local filename = "/img_" .. i .. ".jpg"
    local ok = net.download(img_url, filename, "flash")
    if ok then
      img.loaded = true
      img.path = filename
    else
      img.loaded = false
    end
  end
  status = "Done: " .. url
  loading = false
end

-- Draw page
function draw()
  ui.rect(0, 0, SCR_W, SCR_H, 0)
  -- URL bar
  ui.rect(0, 0, SCR_W, 30, 0x2104)
  ui.text(5, 8, url, 1, 0xFFFF)
  if ui.button(SCR_W-55, 3, 50, 24, "GO", 0x0420) then
    -- You can add an input dialog for URL, for now just reload default
    load_page(url)
  end
  -- Status bar
  ui.text(5, 32, status, 1, 0x07E0)
  -- Scrollable area
  ui.beginList(0, 50, SCR_W, SCR_H-50, scroll_y, max_scroll+SCR_H)
  -- Render lines
  for _, line in ipairs(display_lines) do
    if line.type == "text" then
      ui.text(10, line.y, line.text, 2, 0xFFFF)
    elseif line.type == "link" then
      local link = links[line.index]
      ui.text(10, line.y, link.title, 2, 0x001F)
    end
  end
  -- Render images
  for _, img in ipairs(images) do
    if img.loaded and img.path then
      ui.drawJPEG(img.x, img.y, img.path)
    else
      ui.rect(img.x, img.y, img.w, img.h, 0x8888)
      ui.text(img.x+5, img.y+70, "Image", 2, 0xFFFF)
    end
  end
  ui.endList()
  -- Simple link click: detect touch on link area (naive)
  local touch = ui.getTouch()
  if touch.touching and not is_scrolling then
    for i, link in ipairs(links) do
      local ly = link.y - scroll_y + 50
      if touch.x >= 10 and touch.x <= SCR_W-10 and touch.y >= ly and touch.y <= ly+LINE_H then
        selected_link = i
      end
    end
  end
  if selected_link and not touch.touching then
    local link = links[selected_link]
    local next_url = link.url
    if not next_url:find("://") then
      local base = url:match("^(.*/)") or ""
      next_url = base .. next_url
    end
    load_page(next_url)
    selected_link = nil
  end
  -- Scrolling: drag or momentum
  if touch.pressed then
    touch_start_y = touch.y
    is_scrolling = false
    velocity = 0
  elseif touch.touching then
    if touch_start_y and math.abs(touch.y - touch_start_y) > 10 then
      is_scrolling = true
    end
    if is_scrolling then
      local dy = touch_start_y - touch.y
      scroll_y = scroll_y + dy
      touch_start_y = touch.y
      velocity = dy
    end
  elseif not touch.touching then
    if is_scrolling then
      -- Apply momentum
      scroll_y = scroll_y + velocity
      velocity = velocity * 0.9
      if math.abs(velocity) < 1 then velocity = 0 end
    end
    is_scrolling = false
    touch_start_y = nil
  end
  -- Clamp scroll
  if scroll_y < 0 then scroll_y = 0 velocity = 0 end
  if scroll_y > max_scroll then scroll_y = max_scroll velocity = 0 end
  ui.flush()
end

-- Initial load
load_page(url)
