# Makefile for compiling C programs to hex for the RV32I processor.
#
# Prerequisites:
#   - Install RISC-V GCC toolchain:
#     Windows: download from https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack
#     Linux:   sudo apt install gcc-riscv64-unknown-elf
#
# Usage:
#   make bubble_sort      # compile bubble_sort.c to bubble_sort.hex
#   make fibonacci        # compile fibonacci.c to fibonacci.hex
#   make all              # compile both

PREFIX = riscv-none-elf
CC     = $(PREFIX)-gcc
OBJCOPY = $(PREFIX)-objcopy
OBJDUMP = $(PREFIX)-objdump

CFLAGS  = -march=rv32im_zicsr -mabi=ilp32 -Os -nostdlib -nostartfiles -ffreestanding
LDFLAGS = -T link.ld -Wl,--no-relax

PROGRAMS = bubble_sort fibonacci perf_report

all: $(addsuffix .hex, $(PROGRAMS))

%.elf: start.s %.c mmio.h link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.s $*.c

%.hex: %.elf
	$(OBJCOPY) -O verilog $< $@
	@echo "Generated $@"

%.dump: %.elf
	$(OBJDUMP) -d $< > $@
	@echo "Generated $@ (disassembly)"

clean:
	rm -f *.elf *.hex *.dump

.PHONY: all clean
