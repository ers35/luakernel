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

extern const uintptr_t heap_start;
u8 *heap_end = 0;

static lua_State *L = NULL;

#if 1
// QEMU
void __attribute__((noinline))
trap()
{
  //~ asm volatile("");
  //~ asm volatile("int 3");
  asm volatile("xchg bx, bx");
}
#else
// bochs
#define trap() asm volatile("xchg bx, bx")
#endif

// p &lua_ptr[0]
//~ u8 __attribute__((aligned(16))) lua_mem[4096 * 5 * 1024] = {0};
u8 __attribute__((aligned(4096))) *lua_ptr = NULL;

// need a real realloc now

struct block;
static struct block
{
  size_t len_used_contiguous;
  size_t len_free_contiguous;
  struct block *prev;
  struct block *next;
  u8 buf[];
} *first = NULL;

static struct block*
alloc_block(size_t size)
{
  size_t fsize = sizeof(struct block) + size;
  // align
  fsize += (16 - (fsize % 16));
  for (struct block *foo = first; foo; foo = foo->next)
  {
    if (foo->len_free_contiguous >= fsize)
    {
      foo->next = (struct block*)((u8*)foo + fsize);
      foo->next->len_free_contiguous = foo->len_free_contiguous - fsize;
      foo->next->len_used_contiguous = 0;
      foo->next->prev = foo;
      foo->len_used_contiguous = fsize;
      foo->len_free_contiguous = 0;
      return foo;
    }
  }
  return NULL;
}

static void
free_block(struct block *block)
{
  if (block == NULL)
  {
    return;
  }
  if (block->prev)
  {
    block->prev->len_free_contiguous += block->len_free_contiguous;
    block->prev->next = block->next;
  }
  else
  {
    block->len_free_contiguous = block->len_used_contiguous;
    block->len_used_contiguous = 0;
  }
}

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
    //~ if (new_ptr >= lua_mem + sizeof(lua_mem))
    if (new_ptr >= heap_end)
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
static u8 *display_buffer = NULL;
static u32 display_buffer_len = 0;

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
    &display_buffer[(y * modeinfo->BytesPerScanLine) + (x * bytes_per_pixel)];
  const u8 *display_buffer_end = 
    &display_buffer[(modeinfo->YResolution * modeinfo->BytesPerScanLine)];
  if (ptr < display_buffer_end)
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
  memset(display_buffer, 0, display_buffer_len);
  return 0;
}

int
swap_buffers(lua_State *l)
{
  memcpy(fbmem, display_buffer, display_buffer_len);
  // clear old buffer
  memset(display_buffer, 0, display_buffer_len);
  return 0;
}

u16 DISPLAY_WIDTH = 0;
u16 DISPLAY_HEIGHT = 0;

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
        DISPLAY_WIDTH = modeinfo->XResolution;
        DISPLAY_HEIGHT = modeinfo->YResolution;
        break;
      }
      
      case MULTIBOOT_TAG_TYPE_FRAMEBUFFER:
      {
        struct multiboot_tag_framebuffer *fb = (struct multiboot_tag_framebuffer*)tag;
        if (modeinfo)
        {
          fbmem = (u8*)fb->common.framebuffer_addr;
          //~ clear_screen(NULL);
        }
        break;
      }
#if 0
      case MULTIBOOT_TAG_TYPE_BASIC_MEMINFO:
      {
        struct multiboot_tag_basic_meminfo *meminfo = (struct multiboot_tag_basic_meminfo*)tag;
        break;
      }
#endif

      case MULTIBOOT_TAG_TYPE_MMAP:
      {
        struct multiboot_tag_mmap *mmap = (struct multiboot_tag_mmap*)tag;
        for
        (
          struct multiboot_mmap_entry *entry = mmap->entries;
          (u8*)entry < (u8*)mmap + tag->size;
          entry = (struct multiboot_mmap_entry*)((u8*)entry + mmap->entry_size)
        )
        {
          if (entry->type == MULTIBOOT_MEMORY_AVAILABLE)
          {
            // available memory:
            // 0x0 to 0x9f000
            // 0x100000 to 0x3FFF0000
            // 0xdcaa00
            if (entry->addr == 0x100000)
            {
              //~ heap_end = (u64)&heap_start + (entry->len - ((u64)&heap_start - entry->addr));
              heap_end = (u8*)entry->addr + entry->len;
              //~ trap();
            }
          }
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

bool keyboard_interrupt = false;
bool mouse_interrupt = false;
u64 timer_ticks = 0;

u32 keyboard_scancode_queue[8] = {0};
u32 keyboard_scancode_queue_len = 0;

u32 latest_interrupt = 0;
void
handle_interrupt(u32 n)
{
  latest_interrupt = n;
  switch (n)
  {
    // general protection fault
    case 13:
    {
      trap();
      break;
    }
    
    // page fault
    case 14:
    {
      trap();
      break;
    }
    
    // timer
    case 32:
    {
      //~ trap(); while (1);
      // 100 Hz
      timer_ticks += 1;
      outb(0x20, 0x20);
      break;
    }
    
    // keyboard
    case 33:
    {
      //~ keyboard_interrupt = true;
      u32 scancode = inb(0x60);
      if (keyboard_scancode_queue_len < arraylen(keyboard_scancode_queue))
      {
        keyboard_scancode_queue[keyboard_scancode_queue_len] = scancode;
        keyboard_scancode_queue_len += 1;
      }
      outb(0x20, 0x20);
      break;
    }
    
    // mouse
    case 44:
    {
      //~ trap(); while (1);
      mouse_interrupt = true;
#if 1
      u32 n = inb(0x60);
      outb(0xa0, 0x20);
      outb(0x20, 0x20);
#endif
      break;
    }
    
    default:
    {
      trap(); while (1);
      break;
    }
  }
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

// http://lua-users.org/lists/lua-l/2003-12/msg00301.html
// http://lua-users.org/lists/lua-l/2002-12/msg00171.html
// http://lua-users.org/lists/lua-l/2011-06/msg00426.html
// http://lua-users.org/lists/lua-l/2010-03/msg00679.html

void
lua_hook(lua_State *l, lua_Debug *ar)
{
  lua_yield(l, 0);
}

int
lua_setmaskhook(lua_State *l)
{
  lua_State *t = lua_tothread(l, 1);
  int maskcount = lua_tointeger(l, 2);
  lua_pop(l, 2);
  if (t)
  {
    lua_sethook(t, lua_hook, LUA_MASKCOUNT, maskcount);
  }
  return 0;
}

int
lua_get_timer_ticks(lua_State *l)
{
  lua_pushinteger(l, timer_ticks);
  return 1;
}

int
lua_get_keyboard_interrupt(lua_State *l)
{
  // disable interrupts
  asm volatile ("cli");
  
  // process interrupt data
  lua_createtable(l, keyboard_scancode_queue_len, 0);
  for (int i = 0; i < keyboard_scancode_queue_len; ++i)
  {
    lua_pushinteger(l, keyboard_scancode_queue[i]);
    lua_rawseti(l, -2, i + 1);
  }
  keyboard_scancode_queue_len = 0;
  
  //~ lua_pushboolean(l, keyboard_interrupt);
  //~ keyboard_interrupt = false;
  // enable interrupts
  asm volatile ("sti");
  return 1;
}

int
lua_get_mouse_interrupt(lua_State *l)
{
  lua_pushboolean(l, mouse_interrupt);
  mouse_interrupt = false;
  return 1;
}

int
lua_hlt(lua_State *l)
{
  asm volatile("hlt");
  return 0;
}

const char *errstr = NULL;

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
    errstr = lua_tostring(l, 1);
    //~ puts("luaL_loadstring: error");
    trap();
  }
  int err = lua_pcall(l, 0, LUA_MULTRET, 0);
  if (err != LUA_OK)
  {
    errstr = lua_tostring(l, 1);
    //~ puts("lua_pcall: error");
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
  get_multiboot_info();

  //~ lua_ptr = lua_mem;
  lua_ptr = (u8*)&heap_start;
  //~ mem_ptr = mem;
  //~ first = (struct block*)&heap_start;
  //~ first->prev = NULL;
  //~ first->next = NULL;
  //~ first->len_free_contiguous = sizeof(heap_end);
  //~ first->len_used_contiguous = 0;
  
  L = lua_newstate(l_alloc, NULL);
  if (!L)
  {
    puts("lua_newstate: error");
    return;
  }
  luaL_openlibs(L);
  
  display_buffer_len 
    = (modeinfo->YResolution * modeinfo->BytesPerScanLine);
  display_buffer = lua_newuserdata(L, display_buffer_len);
  clear_screen(L);
  lua_setglobal(L, "display_buffer___");
  
  u8 *sqlite3_mem = lua_newuserdata(L, 1024 * 8 * 1024);
  lua_setglobal(L, "sqlite3_mem___");
  
  lua_pushnumber(L, DISPLAY_WIDTH);
  lua_setglobal(L, "DISPLAY_WIDTH");
  lua_pushnumber(L, DISPLAY_HEIGHT);
  lua_setglobal(L, "DISPLAY_HEIGHT");  
  lua_register(L, "clear_screen", clear_screen);
  lua_register(L, "putpixel", putpixel);
  lua_register(L, "swap_buffers", swap_buffers);
  lua_register(L, "outb", lua_outb);
  lua_register(L, "inb", lua_inb);
  lua_register(L, "setmaskhook", lua_setmaskhook);
  lua_register(L, "loader", lua_loader);
  lua_register(L, "get_timer_ticks", lua_get_timer_ticks);
  lua_register(L, "get_keyboard_interrupt", lua_get_keyboard_interrupt);
  lua_register(L, "get_mouse_interrupt", lua_get_mouse_interrupt);
  lua_register(L, "hlt", lua_hlt);
#if 0
  sqlite3_config(SQLITE_CONFIG_HEAP, sqlite3_mem, sizeof(sqlite3_mem), 64);
  {
    int luaopen_lsqlite3(lua_State *L);
    luaL_requiref(L, "sqlite3", luaopen_lsqlite3, 0);
    lua_pop(L, 1);
  }
#endif
  if (luaL_loadbuffer(L, luakernel_lua, luakernel_lua_len, "luakernel") != LUA_OK)
  {
    //~ puts("luaL_loadstring: error");
    errstr = lua_tostring(L, 1);
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
  trap();
}
