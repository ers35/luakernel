local sqlite3 = require("lsqlite3")

package.searchers[2] = function(modname)
  return loader, modname
end

timer_ticks = 0

local tasks = {}

function taskadd(func, name, maskcount)
  local co = coroutine.create(func)
  setmaskhook(co, maskcount or 1000)
  local task = {
    name = name or "task_" .. #tasks,
    -- For restarting the task if it crashes.
    func = func,
    wait_until = 0,
    co = co,
  }
  table.insert(tasks, task)
  return task
end

-- file system
local fs = {}

fs["/dev/null"] = 
{
  buf = "",
  fd = {},
  write = function(fd, buf)
    return #buf
  end,
  read = function(fd, count)
    return count
  end,
}

fs["/dev/urandom"] = 
{
  buf = "",
  fd = {},
  write = function(fd, buf)
    return #buf
  end,
  read = function(fd, count)
    return count
  end,
}

local O_CREAT = 64
local O_APPEND = 1024

function open(pathname, flags, mode)
  if fs[pathname] == nil and bit32.band(flags, O_CREAT) ~= O_CREAT then
    return -1
  end
  if fs[pathname] == nil and bit32.band(flags, O_CREAT) == O_CREAT then
    print("creat")
    -- create new file
    fs[pathname] = 
    {
      buf = "",
      fd = {},
    }
  end
  local fd = 
  {
    top = fs[pathname],
    -- string.sub considers the first character to be at position 1
    pos = 1
  }
  if fd == 1 then
    print("warning: fd == 1 -- conflicts with stdout")
  end
  if bit32.band(flags, O_APPEND) == O_CREAT then
    print("append")
    fd.pos = #fd.top.buf
  end
  table.insert(fs[pathname].fd, fd)
  return fd
end

local SEEK_SET = 0
local SEEK_CUR = 1
local SEEK_END = 2
function lseek(fd, offset, whence)
  if whence == SEEK_SET then
    fd.pos = offset + 1
  elseif whence == SEEK_CUR then
    fd.pos = fd.pos + offset
  elseif whence == SEEK_END then
    --~ fd.pos = #fd.top.buf
    return -1;
  else
    return -1
  end
  return fd.pos
end

local function sinsert(str, val, pos)
  local s1 = str:sub(0, pos)
  local s2 = str:sub(pos + 1)
  return s1 .. val .. s2
end

function read(fd, count)
  if fd.top.read then
    return fd.top.read(fd, count)
  end
  local buf = fd.top.buf:sub(fd.pos, fd.pos + count)
  print(buf)
  fd.pos = fd.pos + count
  return buf
end

local terminal_lines = {
  -- Start with one empty line.
  {}
}

local WRAP_X = (DISPLAY_WIDTH / 9)
local CLEAR_Y = (DISPLAY_HEIGHT / 15) - 1
local stdout = 1
function write(fd, buf)
  if fd == stdout then
    for c in buf:gmatch(".") do
      local line = terminal_lines[#terminal_lines]
      table.insert(line, c)
      if c == "\n" or #line >= WRAP_X then
        table.insert(terminal_lines, {})
      end
      if #terminal_lines >= CLEAR_Y then
        terminal_lines = {{}}
      end
    end
    return #buf
  end
  fd.top.buf = sinsert(fd.top.buf, buf, fd.pos)
  fd.pos = fd.pos + #buf
  return #buf
end

function hline(x1, y, x2, r, g, b)
  if x2 > x1 then
    for i = 0, x2 - x1, 1 do
      putpixel(x1 + i, y, r, g, b)
    end
  end
end

function vline(x, y1, y2, r, g, b)
  if y2 > y1 then
    for i = 0, y2 - y1, 1 do
      putpixel(x, y1 + i, r, g, b)
    end
  end
end

function rectangle(x, y, width, height, r, g, b)
  hline(x, y, x + width, r, g, b)
  hline(x, y + height, x + width, r, g, b)
  vline(x, y, y + height, r, g, b)
  vline(x + width, y, y + height, r, g, b)
end

local function wait(ticks)
  local me, main = coroutine.running()
  for _, task in ipairs(tasks) do
    if task.co == me then
      task.wait_until = timer_ticks + ticks
      break
    end
  end
  coroutine.yield()
end

local scancode2char =
{
  27, '1', '2', '3', '4', '5', '6', '7', {'8', '*'},	--[ 9 --]
  {'9', '('}, {'0', ')'}, {'-', '_'}, {'=', '+'}, '\b',	--[ Backspace --]
  '\t',			--[ Tab --]
  'q', 'w', 'e', 'r',	--[ 19 --]
  't', 'y', 'u', 'i', 'o', 'p', {'[', '{'}, {']', '}'}, '\n',	--[ Enter key --]
  0,			--[ 29   - Control --]
  'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', {';', ':'},	--[ 39 --]
  {'\'', '"'}, '`',   0,		--[ Left shift --]
  '\\', 'z', 'x', 'c', 'v', 'b', 'n',			--[ 49 --]
  'm', {',', '<'}, {'.', '>'}, '/',   0,				--[ Right shift --]
  '*',
  0,	--[ Alt --]
  ' ',	--[ Space bar --]
  0,	--[ Caps lock --]
  0,	--[ 59 - F1 key ... > --]
  0,   0,   0,   0,   0,   0,   0,   0,
  0,	--[ < ... F10 --]
  0,	--[ 69 - Num lock--]
  0,	--[ Scroll Lock --]
  0,	--[ Home key --]
  0,	--[ Up Arrow --]
  0,	--[ Page Up --]
  '-',
  0,	--[ Left Arrow --]
  0,
  0,	--[ Right Arrow --]
  '+',
  0,	--[ 79 - End key--]
  0,	--[ Down Arrow --]
  0,	--[ Page Down --]
  0,	--[ Insert Key --]
  0,	--[ Delete Key --]
  0,   0,   0,
  0,	--[ F11 Key --]
  0,	--[ F12 Key --]
  0,	--[ All other keys are undefined --]
}

local font = require("font")
function drawchar(x, y, character, r, g, b)
  local f = font[character]
  if f then
    local xl = 0
    local yl = 0
    for i = 1, #f do
      local c = f:sub(i, i)
      if c == '\n' then
        yl = yl + 1
        xl = 0
      elseif c == '.' then
        putpixel(x + xl, y + yl, r, g, b)
        xl = xl + 1
      elseif c == ' ' then
        putpixel(x + xl, y + yl, 0, 0, 0)
        xl = xl + 1
      end
    end
  end
end

function drawtext(x, y, text)
  text = tostring(text)
  local space = 0
  for i = 1, #text do
    local c = text:sub(i, i)
    if c == "\n" then
      space = 0
      y = y + 15
    end
    drawchar(x + space, y, c, 255, 255, 255)
    space = space + 8
  end
end

local tilda = false
local shift_on = 0
local ctrl_on = 0
function key_pressed(scancode_)
  if scancode_ == 0x2a or scancode_ == 0x36 then
    shift_on = 1
    return
  elseif scancode_ == 0xaa or scancode_ == 0xb6 then
    shift_on = 0
    return
  end
  if scancode_ == 0x1d then
    ctrl_on = 1
    return
  elseif scancode_ == 0x9d then
    ctrl_on = 0
    return
  end
  -- print(tostring(scancode_))
  local c = scancode2char[scancode_]
  if type(c) == "table" then
    c = c[shift_on + 1]
  end
  if type(c) == "string" then
    if c == '\b' then
      local line = terminal_lines[#terminal_lines]
      table.remove(line, #line)
    elseif c == '\n' then
      local line = terminal_lines[#terminal_lines]
      io.write("\n")
      local linestr = table.concat(line)
      local chunk, errmsg = load(linestr)
      if chunk == nil then
        print(errmsg)
      else
        local ok, err = pcall(function() chunk() end)
        if not ok then
          print(err)
        end
      end
    elseif ctrl_on == 1 and c == "l" then
      terminal_lines = {{}}
    elseif c == "`" then
      tilda = not tilda
    else
      local line = terminal_lines[#terminal_lines]
      if not line then
        line = {}
        terminal_lines[#terminal_lines + 1] = line
      end
      io.write(c)
      io.flush()
    end
  end
end

local function keyboard_task()
  while 1 do
    local scancodes = get_keyboard_interrupt()
    for _, scancode in ipairs(scancodes) do
      key_pressed(scancode)
    end
    wait(5)
  end
end

local function red_rect_task()
  local red = 20
  while 1 do
    for i = 1, 4 do
      rectangle(DISPLAY_WIDTH - 420, 100, 100, 100, red, 0, 0)
      wait(5)
    end
    red = red + 1
    if red >= 255 then
      red = 20
    end
  end
end

local function green_rect_task()
  local green = 20
  while 1 do
    for i = 1, 6 do
      rectangle(DISPLAY_WIDTH - 410, 110, 100, 100, 0, green, 0)
      wait(5)
    end
    green = green + 3
    if green >= 255 then
      green = 20
    end
  end
end

local function blue_rect_task()
  local blue = 20
  while 1 do
    for i = 1, 8 do
      rectangle(DISPLAY_WIDTH - 400, 120, 100, 100, 0, 0, blue)
      wait(5)
    end
    blue = blue + 5
    if blue >= 255 then
      blue = 20
    end
  end
end

local function draw_tilda()
  -- Draw border.
  rectangle(4, 4, DISPLAY_WIDTH - 8, DISPLAY_HEIGHT - 8, 255, 0, 255)
end

local function draw_terminal()
  local pad_x = 10
  local pad_y = 15
  local cursor_x = 0
  local cursor_y = 1
  for y, line in ipairs(terminal_lines) do
    local str = table.concat(line)
    drawtext(pad_x, y * pad_y, str)
    cursor_x = #str
    cursor_y = y
  end
  -- Draw the terminal cursor.
  rectangle((cursor_x * 8) + pad_x, (cursor_y * pad_y) - 2, 1, 14, 255, 255, 255)
end

local function display_task()
  while 1 do
    -- Draw a border around the screen.
    rectangle(0, 0, DISPLAY_WIDTH - 1, DISPLAY_HEIGHT - 1, 255, 255, 255)
    if tilda then
      draw_tilda()
    end
    draw_terminal()
    swap_buffers()
    wait(10)
  end
end

function fib(n)
  return n < 2 and n or fib(n - 1) + fib(n - 2)
end

taskadd(keyboard_task, "keyboard")
taskadd(display_task, "display")
taskadd(red_rect_task, "red_rect")
taskadd(green_rect_task, "green_rect")
taskadd(blue_rect_task, "blue_rect")

local function database_open()
  db = sqlite3.open_memory()
  db:exec([[
  CREATE TABLE test (id INTEGER PRIMARY KEY, data TEXT);
  INSERT INTO test (data) VALUES ('hello world');
  INSERT INTO test (data) VALUES ('hello lua');
  INSERT INTO test (data) VALUES ('hello sqlite3');
  ]])
  -- print(db:errmsg())
end
database_open()

function db_test()
  print(db)
  for row in db:nrows("SELECT * FROM test") do
    print(row.id, row.data)
  end
end

--[[
The scheduler task is never preempted because lua_sethook() has not been called on it.
--]]
while 1 do
  timer_ticks = get_timer_ticks()
  local any_tasks_ready = false
  for _, task in ipairs(tasks) do
    local costatus = coroutine.status(task.co)
    if costatus == "suspended" or costatus == "normal" then
      if task.wait_until <= timer_ticks then
        any_tasks_ready = true
        local ok, errmsg = coroutine.resume(task.co)
        if not ok then
          -- print(task.name .. ": " .. errmsg)
          print(errmsg)
          -- Restart the task.
          -- taskadd(task.func, task.name)
        end
      end
    end
  end
  if not any_tasks_ready then
    -- Idle until the next interrupt.
    hlt()
  end
end
