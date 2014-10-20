#ifndef UTIL_H_
#define UTIL_H_

#include <stdint.h>

typedef int8_t s8;
typedef uint8_t u8;
typedef int16_t s16;
typedef uint16_t u16;
typedef int32_t s32;
typedef uint32_t u32;
typedef int64_t s64;
typedef uint64_t u64;

#define arraylen(array) (sizeof(array) / sizeof(array[0]))

void
outb(u32 addr, u32 value);

u32
inb(u32 addr);

#endif

