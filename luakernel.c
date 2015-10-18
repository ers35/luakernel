#include <fcntl.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "lua-bundle.h"
#include "multiboot2.h"
#include "sqlite3.h"
#include "util.h"
#include "vbe.h"

static lua_State *L = NULL;
struct task
{
  lua_State *l;
  char *func_name;
} task[8] = {0};

void __attribute__((noinline))
trap()
{
  //~ asm volatile("");
  asm volatile("xchg bx, bx");
}

u8 __attribute__((aligned(16))) lua_mem[4096 * 1 * 1024] = {0};
u8 __attribute__((aligned(4096))) *lua_ptr = NULL;

u8 __attribute__((aligned(16))) mem[4096 * 1 * 1024] = {0};
u8 __attribute__((aligned(4096))) *mem_ptr = NULL;

u8 __attribute__((aligned(16))) sqlite3_mem[1024 * 8 * 1024] = {0};

static void*
l_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
  (void)ud;
  if (nsize == 0)
  {
    //free(ptr);
    return NULL;
  }
  else
  {
    // FIXME: this actually needs to be realloc
    u8 *new_ptr = lua_ptr;
    if (ptr)
    {
      memmove(new_ptr, ptr, osize);
    }
    // align to 16 for movaps
    lua_ptr += nsize + (16 - (nsize % 16));
    if (new_ptr >= lua_mem + sizeof(lua_mem))
    {
      trap();
      return NULL;
    }
    return new_ptr;
    //return realloc(ptr, nsize);
  }
}

struct __attribute__((packed, aligned(1)))
{
  u8 character;
  u8 attribute;
} (*screen)[80 * 25] = (void*)0xb8000;

long 
handle_syscall(long n, long a1, long a2, long a3, long a4, long a5, long a6)
{
  switch (n)
  {
    case SYS_brk:
    {
      void *end = (void*)a1;
      
      return 0;
      break;
    }
    
    case SYS_open:
    {
      const char *pathname = (const char*)a1;
      int flags = a2;
      int mode = a3;
      
      lua_getglobal(L, "open");
      lua_pushstring(L, pathname);
      lua_pushnumber(L, flags);
      lua_pushnumber(L, mode);
      lua_call(L, 3, 1);
      return luaL_ref(L, LUA_REGISTRYINDEX);
      //int fd = luaL_ref(L, LUA_REGISTRYINDEX);
      //return lua_tonumber(L, 1);
      break;
    }
    
    case SYS_close:
    {
      return 0;
      break;
    }
    
    case SYS_lseek:
    {
      int fd = a1;
      off_t offset = a2;
      int whence = a3;
      
      lua_getglobal(L, "lseek");
      lua_rawgeti(L, LUA_REGISTRYINDEX, fd);
      lua_pushnumber(L, offset);
      lua_pushnumber(L, whence);
      lua_call(L, 3, 1);
      int retn = lua_tonumber(L, -1);
      lua_pop(L, 1);
      return retn;
      break;
    }
    
    case SYS_read:
    {
      int fd = a1;
      char *buf = (char*)a2;
      size_t count = a3;
      
      lua_getglobal(L, "read");
      if (fd != 0)
      {
        lua_rawgeti(L, LUA_REGISTRYINDEX, fd);
      }
      else
      {
        // stdin
        lua_pushnumber(L, fd);
      }
      lua_pushnumber(L, count);
      lua_call(L, 2, 1);
      size_t len;
      const char *resbuf = lua_tolstring(L, -1, &len);
      memcpy(buf, resbuf, len);
      lua_pop(L, 1);
      return len;
      //~ break;
    }
    
    case SYS_write:
    {
      int fd = a1;
      const char *buf = (const char*)a2;
      size_t count = a3;
      
      lua_getglobal(L, "write");
      if (fd != 1)
      {
        lua_rawgeti(L, LUA_REGISTRYINDEX, fd);
      }
      else
      {
        lua_pushnumber(L, fd);
      }
      lua_pushlstring(L, buf, count);
      lua_call(L, 2, 1);
      int len = lua_tonumber(L, -1);
      lua_pop(L, 1);
      return len;
    }
    
    case SYS_writev:
    {
      // p (char*)iov[0].iov_base
      int fd = a1;
      struct iovec *iov = (struct iovec*)a2;
      int count = (int)a3;
      ssize_t num_bytes_written = 0;
      for (int i = 0; i < count; ++i)
      {
        num_bytes_written += write(fd, iov[i].iov_base, iov[i].iov_len);
      }
      return num_bytes_written;
      break;
    }
    
    case SYS_ioctl:
    {
      return 0;
    }
    
    case SYS_getpid:
    {
      return 0;
    }
    
    case SYS_fsync:
    {
      return 0;
    }
    
    case SYS_chown:
    {
      return 0;
    }
    
    case SYS_clock_gettime:
    {
      clockid_t clk_id = (clockid_t)a1;
      struct timespec *tp = (struct timespec*)a2;
      *tp = (struct timespec){0};
      return 0;
    }
    
    case SYS_gettimeofday:
    {
      struct timeval *tv = (struct timeval*)a1;
      *tv = (struct timeval){0};
      return 0;
    }
    
    default:
    {
      trap();
      return -1;
    }
  }
}

long 
__syscall(long n, long a1, long a2, long a3, long a4, long a5, long a6)
{
  handle_syscall(n, a1, a2, a3, a4, a5, a6);
}

extern u8 *volatile multiboot_boot_information;
static struct VBEModeInfoBlock *modeinfo = NULL;
static u8 *fbmem = NULL;

int
putpixel(lua_State *l)
{
  u32 x = lua_tonumber(l, 1);
  u32 y = lua_tonumber(l, 2);
  u32 r = lua_tonumber(l, 3);
  u32 g = lua_tonumber(l, 4);
  u32 b = lua_tonumber(l, 5);
  lua_pop(l, 5);
  const u32 bytes_per_pixel = (modeinfo->BitsPerPixel / 8);
  // http://forum.osdev.org/viewtopic.php?p=77998&sid=d4699cf03655c572906144641a98e4aa#p77998
  u8 *ptr = 
    &fbmem[(y * modeinfo->BytesPerScanLine) + (x * bytes_per_pixel)];
  const u8 *fbmem_end = 
    &fbmem[(modeinfo->YResolution * modeinfo->BytesPerScanLine) + (modeinfo->XResolution * bytes_per_pixel)];
  if (ptr < fbmem_end)
  {
    ptr[0] = b;
    ptr[1] = g;
    ptr[2] = r;
    ptr[3] = 0;
  }
  else
  {
    trap();
  }

  return 0;
}

int
clear_screen(lua_State *l)
{
  memset(fbmem, 0, modeinfo->YResolution * modeinfo->BytesPerScanLine);
  return 0;
}

void
get_multiboot_info(void)
{
  if (multiboot_boot_information == NULL)
  {
    trap();
  }
  u32 total_size = *(u32*)multiboot_boot_information;
  struct multiboot_tag *tag = (struct multiboot_tag*)&multiboot_boot_information[8];
  while (tag->type != MULTIBOOT_TAG_TYPE_END)
  {
    switch (tag->type)
    {
      case MULTIBOOT_TAG_TYPE_VBE:
      {
        struct multiboot_tag_vbe *vbetag = (struct multiboot_tag_vbe*)tag;
        modeinfo = (struct VBEModeInfoBlock*)&vbetag->vbe_mode_info;
        lua_pushnumber(L, modeinfo->XResolution);
        lua_setglobal(L, "DISPLAY_WIDTH");
        lua_pushnumber(L, modeinfo->YResolution);
        lua_setglobal(L, "DISPLAY_HEIGHT");
        break;
      }
      
      case MULTIBOOT_TAG_TYPE_FRAMEBUFFER:
      {
        struct multiboot_tag_framebuffer *fb = (struct multiboot_tag_framebuffer*)tag;
        if (modeinfo)
        {
          fbmem = (u8*)fb->common.framebuffer_addr;
          clear_screen(NULL);
        }
        break;
      }
    }

    // tags are padded to ensure 8 byte alignment
    if (tag->size % 8 == 0)
    {
      tag = (struct multiboot_tag*)((u8*)tag + tag->size);
    }
    else
    {
      tag = (struct multiboot_tag*)((u8*)tag + tag->size + (8 - (tag->size % 8)));
    }
  }
}

enum
{
  KEYBOARD_DATA_PORT = 0x60,
  KEYBOARD_STATUS_PORT = 0x64,
  PIC1_CMD = 0x20,
};

bool new_interrupt = false;

void
handle_interrupt(u32 n)
{
  switch (n)
  {
    // general protection fault
    case 13:
    {
      trap();
      break;
    }
    
    // keyboard
    case 33:
    {
      //~ trap();
      break;
    }
    
    default:
    {
      trap();
      break;
    }
  }
  
#if 0
  // race condition -- lua_hook may not have been called yet
  if (new_interrupt)
  {
    // nested!
    trap();
  }
#endif
  new_interrupt = true;
}

int
lua_outb(lua_State *l)
{
  const u32 addr = lua_tonumber(l, 1);
  const u8 value = lua_tonumber(l, 2);
  outb(addr, value);
  lua_pop(l, 2);
  return 0;
}

int
lua_inb(lua_State *l)
{
  const u32 addr = lua_tonumber(l, 1);
  lua_pop(l, 1);
  const u8 value = inb(addr);
  lua_pushnumber(l, value);
  return 1;
}

void
lua_hook(lua_State *l, lua_Debug *ar)
{
  if (new_interrupt)
  {
    lua_pushboolean(l, true);
    lua_setglobal(l, "keyboard_interrupt_flag");
    new_interrupt = false;
  }
  lua_yield(l, 0);
}

int
lua_taskadd(lua_State *l)
{
  for (u32 t = 0; t < arraylen(task); ++t)
  {
    if (!task[t].l)
    {
      size_t len;
      const char *func_name = lua_tolstring(l, -1, &len);
      task[t].l = lua_newthread(L);
      lua_sethook(task[t].l, lua_hook, LUA_MASKCOUNT, 1000);
      //~ int func = luaL_ref(l, LUA_REGISTRYINDEX);
      //~ printf("%i\n", func);
      //~ lua_rawgeti(task[t].l, LUA_REGISTRYINDEX, func);
      char func_name_[64] = {0};
      memcpy(func_name_, func_name, len);
      lua_pop(l, 1);
      lua_getglobal(task[t].l, func_name_);
      lua_pushnumber(l, t);
      break;
    }
  }
  return 1;
}

int
lua_loader(lua_State *l)
{
  size_t len;
  const char *modname = lua_tolstring(l, -1, &len);
  struct module *mod = NULL;
  for (int i = 0; i < arraylen(lua_bundle); ++i)
  {
    if (memcmp(modname, lua_bundle[i].name, len) == 0)
    {
      mod = &lua_bundle[i];
    }
  }
  if (!mod)
  {
    lua_pushnil(l);
    return 1;
  }
  if (luaL_loadbuffer(l, mod->buf, mod->len, mod->name) != LUA_OK)
  {
    puts("luaL_loadstring: error");
    trap();
  }
  int err = lua_pcall(l, 0, LUA_MULTRET, 0);
  if (err != LUA_OK)
  {
    puts("lua_pcall: error");
    trap();
  }
  if (!lua_istable(l, -1))
  {
    puts("not a table");
  }
  return 1;
}

int lua_resume_code = 0;
void
main(void)
{
  lua_ptr = lua_mem;
  mem_ptr = mem;
  L = lua_newstate(l_alloc, NULL);
  if (!L)
  {
    puts("lua_newstate: error");
    return;
  }
  luaL_openlibs(L);
  get_multiboot_info();
  lua_register(L, "clear_screen", clear_screen);
  lua_register(L, "putpixel", putpixel);
  lua_register(L, "outb", lua_outb);
  lua_register(L, "inb", lua_inb);
  lua_register(L, "taskadd", lua_taskadd);
  lua_register(L, "loader", lua_loader);
  sqlite3_config(SQLITE_CONFIG_HEAP, sqlite3_mem, sizeof(sqlite3_mem), 64);
  {
    int luaopen_lsqlite3(lua_State *L);
    luaL_requiref(L, "sqlite3", luaopen_lsqlite3, 0);
    lua_pop(L, 1);
  }
  if (luaL_loadbuffer(L, luakernel_lua, luakernel_lua_len, "luakernel") != LUA_OK)
  {
    //~ puts("luaL_loadstring: error");
    trap();
    return;
  }
  int err = lua_pcall(L, 0, LUA_MULTRET, 0);
  if (err != LUA_OK)
  {
    //~ puts("lua_pcall: error");
    trap();
    return;
  }
  while (1)
  {
    for (int t = 0; t < arraylen(task); ++t)
    {
      if (task[t].l)
      {
        switch (lua_resume_code = lua_resume(task[t].l, L, 0))
        //~ switch (lua_resume_code = lua_resume(task[t].l, NULL, 0))
        {
          case LUA_YIELD:
          {
            //~ trap();
            break;
          }
          
          case LUA_OK:
          {
            trap();
            task[t].l = NULL;
            break;
          }
          
          case LUA_ERRRUN:
          {
            trap();
            break;
          }
          
          default:
          {
            trap();
            break;
          }
        }
      }
    }
  }
  trap();
}
