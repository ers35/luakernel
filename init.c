#include "util.h"

// map 0x00000000 to 0xffffffff (4GiB)
enum
{
  NUM_PML4 = 1,
  NUM_PDP  = 1,
  NUM_PD   = 4,
  NUM_PT   = 512,
};

struct PML4;
struct PDP;
struct PD;
struct PT;
struct __attribute__((aligned(4096))) PML4
{
  u64 ptr[NUM_PDP];
  struct __attribute__((aligned(4096))) PDP
  {
    u64 ptr[NUM_PD];
    struct __attribute__((aligned(4096))) PD
    {
      u64 ptr[NUM_PT];
      struct __attribute__((aligned(4096))) PT
      {
        u64 addr[512];
      } PT[NUM_PT];
    } PD[NUM_PD];
  } PDP[NUM_PDP];
} PML4[NUM_PML4] = {0};

void
setup_page_table(void)
{
  // identity map every page
  u32 addr = 0;
  for (u32 nPML4 = 0; nPML4 < arraylen(PML4); ++nPML4)
  {
    struct PML4 *PML4_ = &PML4[nPML4];
    for (u32 nPDP = 0; nPDP < arraylen(PML4_->PDP); ++nPDP)
    {
      PML4_->ptr[nPDP] = ((u32)&PML4_->PDP[nPDP] | 3);
      struct PDP *PDP_ = &PML4_->PDP[nPDP];
      for (u32 nPD = 0; nPD < arraylen(PDP_->PD); ++nPD)
      {
        PDP_->ptr[nPD] = ((u32)&PDP_->PD[nPD] | 3);
        struct PD *PD_ = &PDP_->PD[nPD];
        for (u32 nPT = 0; nPT < arraylen(PD_->PT); ++nPT)
        {
          PD_->ptr[nPT] = ((u32)&PD_->PT[nPT] | 3);
          struct PT *PT_ = &PD_->PT[nPT];
          for (u32 i = 0; i < arraylen(PT_->addr); ++i, ++addr)
          {
            PT_->addr[i] = (addr * 4096) | 3;
          }
        }
      }
    }
  }
  // Table 4-12. Use of CR3 with IA-32e Paging and CR4.PCIDE = 0
  asm volatile ("mov cr3, %0" ::"r"(PML4));
}

struct
{
  u16 baseLow;
  u16 selector;
  u8 reserved0;
  u8 flags;
  u16 baseMid;
  u32 baseHigh;
  u32 reserved1;
} __attribute__((packed)) IDT[256] = {0};

struct IDTR
{
  u16 limit;
  u64 base;
} __attribute__((packed)) IDTR = {0};

void
setIDT(u8 number, u64 base, u16 selector, u8 flags)
{
  // set base address
  IDT[number].baseLow = base & 0xFFFF;
  IDT[number].baseMid = (base >> 16) & 0xFFFF;
  IDT[number].baseHigh = (base >> 32) & 0xFFFFFFFF;

  // set selector
  IDT[number].selector = selector;
  IDT[number].flags = flags;

  IDT[number].reserved0 = 0;
  IDT[number].reserved1 = 0;
}

void
setup_IDT(void)
{
  IDTR.limit = sizeof(IDT) - 1;
  IDTR.base = (u32)IDT;
  for (u32 i = 0; i < arraylen(IDT); ++i)
  {
    void handle_interupt(void);
    setIDT(i, (u32)handle_interupt, 0x08, 0x8E);
  }
}
