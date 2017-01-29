OUTPUT_FORMAT(elf64-x86-64)
ENTRY(start)
SECTIONS
{
  . = 0x100000;
  .text : 
  {
    text_start = .;
    *(.text)
    text_end = .;
  }
  .data : 
  {
    data_start = .;
    *(.data)
    data_end = .;
  }
  .bss : 
  {
    bss_start = .;
    *(.bss)
    bss_end = .;
  }
  .heap : 
  {
    . = ALIGN(16);
    heap_start = .;
  }
}
