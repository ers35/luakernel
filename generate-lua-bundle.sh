#!/usr/bin/lua5.2

local raw = io.popen("find *.lua"):read("*all")
local filenames = {}
local modnames = {}
for filename in raw:gmatch("%a+%.lua") do
  table.insert(filenames, filename)
  table.insert(modnames, filename:sub(0, -5))
end
os.execute("rm -f lua-bundle.h")
for i, filename in ipairs(filenames) do
  os.execute(("xxd -i %s - >> lua-bundle.h"):format(filename))
end
local modname_str = ""
for i, modname in ipairs(modnames) do
  modname_str = 
    modname_str .. ("\t{\"%s\", %s_lua, sizeof(%s_lua)},\n"):format(modname, modname, modname)
end
local array = [[
struct module
{
  char *name;
  unsigned char *buf;
  unsigned int len;
} lua_bundle[] = 
{
%s
};
]]
local bundle = io.open("lua-bundle.h", "a+")
bundle:write(array:format(modname_str))
