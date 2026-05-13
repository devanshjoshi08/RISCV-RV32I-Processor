MEMORY
{
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    RAM (rwx) : ORIGIN = 0x00001000, LENGTH = 3K
}

SECTIONS
{
    .text : { *(.text.init) *(.text*) } > ROM
    .rodata : { *(.rodata*) } > ROM
    .data : { *(.data*) } > RAM
    .bss : {
        __bss_start = .;
        *(.bss*) *(COMMON)
        __bss_end = .;
    } > RAM

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
