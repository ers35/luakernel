#!/bin/bash

# ./generate-interrupt-handler.sh > interrupt.S

for i in {0..255}
do
echo "
.global handle_interrupt_$i
.align 32
handle_interrupt_$i:
push rdi
mov rdi, $i
jmp handle_interrupt_"
done

