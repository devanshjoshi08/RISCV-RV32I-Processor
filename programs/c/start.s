.section .text.init
.global _start

_start:
    la   sp, __stack_top
    call main
halt:
    j    halt
