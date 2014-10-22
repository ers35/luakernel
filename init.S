.intel_syntax noprefix
.code32

#define ASM_FILE 1
#include "multiboot2.h"

#define trap xchg bx, bx

.bss

// align for movaps
.align 16
stack_end: .space 4096 * 1 * 1024
stack:

.data

.align 8
// Global Descriptor Table
GDT:
  GDTNull:
  .quad 0      	
  GDTCode:     	
  .short 0xFFFF
  .short 0
  .byte 0
  .byte 0x9a
  .byte 0xaf
  .byte 0
  GDTData:
  .short 0xFFFF
  .short 0
  .byte 0
  .byte 0x92
  .byte 0x8f
  .byte 0
GDT_end:
  GDTPointer:
  .short GDT_end - GDT - 1
  .quad GDT

.align 4
.global multiboot_boot_information
multiboot_boot_information: .long 0

.text
.global start
.align 4
multiboot_header:
  .long MULTIBOOT2_HEADER_MAGIC
  .long MULTIBOOT_ARCHITECTURE_I386
  # length
  .long multiboot_header_end - multiboot_header
  # checksum
  .long -(MULTIBOOT2_HEADER_MAGIC + MULTIBOOT_ARCHITECTURE_I386 + (multiboot_header_end - multiboot_header))
.align 8
multiboot_framebuffer:
  .short MULTIBOOT_HEADER_TAG_FRAMEBUFFER
  .short MULTIBOOT_HEADER_TAG_OPTIONAL
  .long multiboot_framebuffer_end - multiboot_framebuffer
  .long 0#1920
  .long 0#1080
  .long 32
.align 4
multiboot_framebuffer_end:
  .short MULTIBOOT_HEADER_TAG_END
  .short MULTIBOOT_TAG_TYPE_END
  .long 0
multiboot_header_end:
.align 4
start:
enter_long_mode:
  // disable interrupts
  cli
  
  // ebx contains multiboot2 data structure from GRUB
  mov multiboot_boot_information, ebx
  
  // enable SSE
  mov ecx, cr0
  // clear CR0.EM bit
  btr ecx, 2
  // set CR0.MP bit
  bts ecx, 1
  mov cr0, ecx
  mov ecx, cr4
  // set CR4.OSFXSR bit
  bts ecx, 9
  // set CR4.OSXMMEXCPT bit
  bts ecx, 10
  mov cr4, ecx

  # Enable PAE
  mov eax, cr4
  or eax, 1 << 5
  mov cr4, eax

  # Enable long mode and syscalls
  // EFER
  mov ecx, 0xc0000080
  rdmsr
  //long mode and syscalls
  //or eax, 0x101
  // long mode only
  or eax, 0x100
  wrmsr

  // push grows the stack down
  lea esp, stack
  call setup_page_table

  # Enable paging
  mov eax, cr0
  or eax, 0x80000000
  mov cr0, eax

  # Load the long mode GDT.
  lgdt [GDTPointer]
  call setup_IDT
  lidt [IDTR]

  // jump to the 64-bit code segment located at 0x08, as indicated in the GDT
  jmp 0x08:Realm64
	
.code64
Realm64:
  // "4.5.3 Segment Registers in 64-Bit Mode"
  // "In 64-bit mode, the contents of the ES, DS, and SS segment registers are ignored."
  mov ax, 0
  mov ds, ax
  mov es, ax
  mov fs, ax
  mov gs, ax
  mov ss, ax

#define PIC1_CMD 0x20
#define PIC1_DATA 0x21
#define PIC2_CMD 0xa0
#define PIC2_DATA 0xa1

  // init PICs
  mov al, 0x11
  out PIC1_CMD, al
  out PIC2_CMD, al
  
  // remap offset address
  mov al, 0x20
  out PIC1_DATA, al
  mov al, 0x28
  out PIC2_DATA, al
  
  // cascade
  mov al, 0
  out PIC1_DATA, al
  out PIC2_DATA, al
  
  // env info
  mov al, 0x1
  out PIC1_DATA, al
  out PIC2_DATA, al
  
  // disable all interrupts via IMR
  mov al, 0xff
  out PIC1_DATA, al
  out PIC2_DATA, al
  
  // enable only the keyboard interrupt
  mov al, 0xfd
  out PIC1_DATA, al
  
#undef PIC1_CMD
#undef PIC1_DATA
#undef PIC2_CMD
#undef PIC2_DATA
  
  // enable interrupts
  sti
  
  call main
  hlt
  
// "8.9.3 Interrupt Stack Frame"
.global handle_interupt_
handle_interupt_:
  push rax
  push rcx
  push rdx
  push r8
  push r9
  push r10
  push r11
  push fs
  push gs
  
  // no need to save all the segment registers since this is 64-bit mode only
  // C ensures rbx, rbp, rsi, and rdi, r12, r13, r14, and r15 are preserved.

  // NOTE: RSP is +48 with error code
  // but only +40 without error code

  call handle_interrupt

  // FIXME: need to pop error code if there is a error.
  // iretq pops RIP, CS, RFLAGS, RSP, and SS

  pop gs
  pop fs
  pop r11
  pop r10
  pop r9
  pop r8
  pop rdx
  pop rcx
  pop rax

  iretq

.global outb
outb:
  mov rdx, rdi
  mov rax, rsi
  outb dx, al
  ret

.global inb
inb:
  mov rdx, rdi
  inb al, dx
  //mov rdi, rax
  ret
