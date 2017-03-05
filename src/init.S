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

// http://www.brokenthorn.com/Resources/OSDevPic.html
// http://www.brokenthorn.com/Resources/OSDev16.html
// https://github.com/haiku/haiku/blob/5e726ed/src/system/kernel/arch/x86/pic.cpp#L219

#define PIC1_CMD_STATUS 0x20
#define PIC1_IMR_DATA 0x21
#define PIC2_CMD_STATUS 0xa0
#define PIC2_IMR_DATA 0xa1

  // ICW 1 
  // initialization bits:
  // 5-7: 0 unused
  // 4:   1 initialization
  // 3:   0 edge triggered
  // 2:   0 ignored by x86
  // 1:   0 cascading
  // 0:   1 IC4 expected
  mov al, 0b00010001
  out PIC1_CMD_STATUS, al
  out PIC2_CMD_STATUS, al
  
  // ICW 2
  // remap base IRQ addresses outside reserved range
  mov al, 0x20
  out PIC1_IMR_DATA, al
  mov al, 0x28
  out PIC2_IMR_DATA, al
  
  // ICW 3
  // enable cascading with PIC2 at IRQ 2
  mov al, 4
  out PIC1_IMR_DATA, al
  mov al, 2
  out PIC2_IMR_DATA, al
  
  // ICW 4
  // 5-7: 0 reserved
  // 4:   0 Special Fully Nested Mode
  // 3:   0 buffered mode off
  // 2:   0 buffered mode off
  // 1:   0 auto EOI off
  // 0:   1 8086 mode
  mov al, 0x1
  out PIC1_IMR_DATA, al
  out PIC2_IMR_DATA, al
  
#if 1
  // configure PIT for 100 Hz
  mov al, 0x36
  out 0x43, al
  mov al, 0xa9
  out 0x40, al
  mov al, 0x04
  out 0x40, al
#endif
  
#if 1
  // write IMR
  // IRQ 2 PIC2
  // IRQ 1 keyboard
  // IRQ 0 timer
  mov al, 0b11111000
  out PIC1_IMR_DATA, al
  
  // mouse is on PIC2
  // IRQ 12 mouse
  mov al, 0b11101111
  //mov al, 0b11111111
  out PIC2_IMR_DATA, al
#endif
  
#undef PIC1_CMD
#undef PIC1_DATA
#undef PIC2_CMD
#undef PIC2_DATA
  
  // enable FPU
  fninit
  push 0x037f
  fldcw [rsp]
  pop rax
  
  // enable interrupts
  sti
  
  call main
  hlt
  
// "8.9.3 Interrupt Stack Frame"
#include "interrupt.S"

// http://www.brokenthorn.com/Resources/OSDev15.html
// http://svnweb.freebsd.org/base/head/sys/amd64/amd64/exception.S?view=co
// http://cvsweb.openbsd.org/cgi-bin/cvsweb/~checkout~/src/sys/arch/amd64/amd64/vector.S?rev=1.43&content-type=text/plain
// https://github.com/ReturnInfinity/BareMetal-kernel/blob/master/src/x86-64/interrupt.asm

.global handle_interrupt_
handle_interrupt_:
  push rax
  push rbx
  push rbp
  push rcx
  push rdx
  push rsi
  // saved in the individual handlers
  //push rdi
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  push fs
  push gs
  
  // no need to save all the segment registers since this is 64-bit mode only

  // NOTE: RSP is +48 with error code
  // but only +40 without error code

  call handle_interrupt

  // FIXME: need to pop error code if there is a error.
  // iretq pops RIP, CS, RFLAGS, RSP, and SS

  pop gs
  pop fs
  pop r15
  pop r14
  pop r13
  pop r12
  pop r11
  pop r10
  pop r9
  pop r8
  pop rsi
  pop rdx
  pop rcx
  pop rbp
  pop rbx
  pop rax
  // set in the individual handlers
  pop rdi

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
