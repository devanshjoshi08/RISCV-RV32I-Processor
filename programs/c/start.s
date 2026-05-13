# first thing that runs on the processor.
# sets up the stack so C functions work, then jumps to main.

.section .text.init
.global _start

_start:
    la   sp, __stack_top
    call main
halt:
    j    halt
