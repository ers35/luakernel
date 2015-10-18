package.searchers[2] = function(modname)
  return loader, modname
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
    msg("creat")
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
    msg("warning: fd == 1 -- conflicts with stdout")
  end
  if bit32.band(flags, O_APPEND) == O_CREAT then
    msg("append")
    fd.pos = #fd.top.buf
  end
  table.insert(fs[pathname].fd, fd)
  return fd
end

function close(fd)
  
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

local stdout = 1
function write(fd, buf)
  if fd == stdout then
    msg(buf)
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

local function wait(n)
  for i = 0, n, 1 do
  end
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

local font = require"font"
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
  -- clear line
  for i = y, y + 14 do
    hline(x, i, DISPLAY_WIDTH - 6, 0, 0, 0)
  end
  text = tostring(text)
  local space = 0
  for i = 1, #text do
    local c = text:sub(i, i)
    drawchar(x + space, y, c, 255, 255, 255)
    space = space + 8
  end
end

-- display border
rectangle(5, 5, DISPLAY_WIDTH - 10, DISPLAY_HEIGHT - 10, 255, 255, 255)

-- cursor position
local cpos = {x = 26, y = 10}

function msg(text)
  drawtext(10, cpos.y, text)
  cpos.y = cpos.y + 15
  if cpos.y >= 13 * 30 then
    cpos.y = 10
  end
end

drawtext(10, 10, "> ")

local shift_on = 0
local TIB = {}
function key_pressed(scancode)
  if scancode == 0x2a or scancode == 0x36 then
    shift_on = 1
    return
  elseif scancode == 0xaa or scancode == 0xb6 then
    shift_on = 0
    return
  end
  local c = scancode2char[scancode]
  if type(c) == "table" then
    c = c[shift_on + 1]
  end
  if type(c) == "string" then
    if c == '\b' then
      if cpos.x > 26 then
        cpos.x = cpos.x - 8
      end
      drawchar(cpos.x, cpos.y, TIB[#TIB], 0, 0, 0)
      TIB[#TIB] = nil
    elseif c == '\n' then
      cpos.x = 10
      cpos.y = cpos.y + 15
      local TIBstr = table.concat(TIB)
      local chunk, errmsg = load(TIBstr)
      if chunk == nil then
        msg(errmsg)
      else
        local ok, err = pcall(function() chunk() end)
        if not ok then
          msg(err)
        end
      end
      TIB = {}
      drawtext(10, cpos.y, "> ")
      cpos.x = 26
    else
      drawchar(cpos.x, cpos.y, c, 255, 255, 255)
      cpos.x = cpos.x + 8
      table.insert(TIB, c)
    end
  end
  if cpos.y >= 40 * 10 then
    cpos.y = 10
  end
end

local PIC1_CMD = 0x20
local KEYBOARD_DATA_PORT = 0x60
keyboard_interrupt_flag = false
function keyboard_task()
  while 1 do
    if keyboard_interrupt_flag then
      local scancode = inb(KEYBOARD_DATA_PORT)
      key_pressed(scancode)
      keyboard_interrupt_flag = false
      -- interrupt EOI (ACK)
      outb(PIC1_CMD, 0x20)
    end
  end
end

function red_rect_task()
  local red = 20
  while 1 do
    rectangle(400, 100, 100, 100, red, 0, 0)
    red = red + 1
    if red >= 255 then
      red = 20
    end
    wait(1000000)
  end
end

function green_rect_task()
  local green = 20
  while 1 do
    rectangle(410, 110, 100, 100, 0, green, 0)
    green = green + 3
    if green >= 255 then
      green = 20
    end
    wait(1000000)
  end
end

function blue_rect_task()
  local blue = 20
  while 1 do
    rectangle(420, 120, 100, 100, 0, 0, blue)
    blue = blue + 5
    if blue >= 255 then
      blue = 20
    end
    wait(1000000)
  end
end

function fib(n)
  return n < 2 and n or fib(n - 1) + fib(n - 2)
end

taskadd("red_rect_task")
taskadd("green_rect_task")
taskadd("blue_rect_task")
taskadd("keyboard_task")
