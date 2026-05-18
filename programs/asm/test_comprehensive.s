# test_comprehensive.s
# Comprehensive test for RV32IM processor with CSR and trap handling.
# See test_comprehensive.hex for the hand-encoded machine code.
#
# Register allocation:
#   x1-x9:   temporaries
#   x10-x31: test result registers
#
# Expected results:
#   x10 = 0x0000005B  (91, MUL 7*13)
#   x11 = 0xFFFFFFFE  (MULH: upper(-2 * 0x7FFFFFFF))
#   x12 = 0xFFFFFFFF  (MULHSU: upper(-2 signed * 3 unsigned))
#   x13 = 0x00000000  (MULHU: upper(3u * 5u) = 0)
#   x14 = 0x0000000D  (13, DIV 91/7)
#   x15 = 0x00000000  (REM 91%7 = 0)
#   x16 = 0xFFFFFFFF  (DIVU: 0xFFFFFFFF / 1)
#   x17 = 0x00000000  (REMU: 0xFFFFFFFF % 1 = 0)
#   x18 = 0xFFFFFFFF  (DIV by zero -> -1 per spec)
#   x19 = 0x00000007  (REM by zero -> dividend = 7)
#   x20 = 0x80000000  (DIV overflow: MIN_INT / -1 -> MIN_INT)
#   x21 = 0x00000000  (REM overflow: MIN_INT % -1 -> 0)
#   x22 = nonzero     (mcycle counter)
#   x23 = nonzero     (minstret counter)
#   x24 = 0xDEADBEEF  (mscratch readback after CSRRW)
#   x25 = 0xDEADBEEF  (CSRRS: old mscratch before setting bit 4)
#   x26 = 0xDEADBEFF  (CSRRC: old mscratch=0xDEADBEFF before clearing bit 2)
#   x27 = 0x0000001F  (CSRRSI: read mscratch=0x1F, zimm=0 so no change)
#   x28 = 0x0000001F  (CSRRCI: old mscratch before clearing bit 3)
#   x29 = 0x00000017  (final mscratch: 0x1F & ~0x08 = 0x17)
#   x30 = 0x000000AB  (trap handler reached flag)
#   x31 = 0x0000000B  (mcause = 11, ecall from M-mode)
#   x3  = 0x0000002A  (42, mul hazard test: 6*7)
#   x4  = 0x00000030  (48, add after mul: 42+6, forwarding test)

.text
.globl _start
_start:


# SECTION 1: M-extension multiply tests


    addi x1, x0, 7           # [0x00] x1 = 7
    addi x2, x0, 13          # [0x04] x2 = 13
    mul  x10, x1, x2         # [0x08] x10 = 7*13 = 91

    addi x3, x0, -2          # [0x0C] x3 = -2 (0xFFFFFFFE)
    lui  x4, 0x80000         # [0x10] x4 = 0x80000000
    addi x4, x4, -1          # [0x14] x4 = 0x7FFFFFFF
    mulh x11, x3, x4         # [0x18] x11 = upper(-2 * 0x7FFFFFFF) = 0xFFFFFFFE

    addi x5, x0, 3           # [0x1C] x5 = 3
    mulhsu x12, x3, x5       # [0x20] x12 = upper((-2 signed) * (3 unsigned)) = 0xFFFFFFFF

    addi x6, x0, 5           # [0x24] x6 = 5
    mulhu x13, x5, x6        # [0x28] x13 = upper(3u * 5u) = 0


# SECTION 2: M-extension divide tests


    addi x7, x0, 91          # [0x2C] x7 = 91
    div  x14, x7, x1         # [0x30] x14 = 91/7 = 13
    rem  x15, x7, x1         # [0x34] x15 = 91%7 = 0

    addi x8, x0, -1          # [0x38] x8 = 0xFFFFFFFF
    addi x9, x0, 1           # [0x3C] x9 = 1
    divu x16, x8, x9         # [0x40] x16 = 0xFFFFFFFF / 1 = 0xFFFFFFFF
    remu x17, x8, x9         # [0x44] x17 = 0xFFFFFFFF % 1 = 0

    div  x18, x1, x0         # [0x48] x18 = 7/0 = -1 (div by zero spec)
    rem  x19, x1, x0         # [0x4C] x19 = 7%0 = 7 (rem by zero spec)

    lui  x1, 0x80000         # [0x50] x1 = 0x80000000 (MIN_INT)
    addi x2, x0, -1          # [0x54] x2 = -1
    div  x20, x1, x2         # [0x58] x20 = MIN_INT/-1 = MIN_INT (overflow)
    rem  x21, x1, x2         # [0x5C] x21 = MIN_INT%-1 = 0 (overflow)


# SECTION 3: CSR operations


    csrrs x22, mcycle, x0    # [0x60] x22 = mcycle (should be nonzero)
    csrrs x23, minstret, x0  # [0x64] x23 = minstret (should be nonzero)

    lui   x1, 0xDEADC        # [0x68] x1 = 0xDEADC000
    addi  x1, x1, -273       # [0x6C] x1 = 0xDEADBEEF
    csrrw x0, mscratch, x1   # [0x70] mscratch = 0xDEADBEEF (discard old)
    csrrs x24, mscratch, x0  # [0x74] x24 = mscratch = 0xDEADBEEF

    addi  x2, x0, 16         # [0x78] x2 = 0x10
    csrrs x25, mscratch, x2  # [0x7C] x25 = old(0xDEADBEEF), mscratch |= 0x10 = 0xDEADBEFF

    addi  x3, x0, 4          # [0x80] x3 = 4
    csrrc x26, mscratch, x3  # [0x84] x26 = old(0xDEADBEFF), mscratch &= ~4 = 0xDEADBEFB

    csrrwi x0, mscratch, 31  # [0x88] mscratch = 31 = 0x1F (zimm=11111)
    csrrsi x27, mscratch, 0  # [0x8C] x27 = mscratch = 0x1F (zimm=0, no set)
    csrrci x28, mscratch, 8  # [0x90] x28 = old(0x1F), mscratch &= ~8 = 0x17
    csrrs  x29, mscratch, x0 # [0x94] x29 = mscratch = 0x17


# SECTION 4: Trap handling


    addi  x1, x0, 192        # [0x98] x1 = 0xC0 (trap handler address)
    csrrw x0, mtvec, x1      # [0x9C] mtvec = 0xC0
    ecall                     # [0xA0] trap! mepc=0xA0, mcause=11


# SECTION 5: Pipeline hazard test (reached after mret to 0xA4)


    addi x1, x0, 6           # [0xA4] x1 = 6
    addi x2, x0, 7           # [0xA8] x2 = 7
    mul  x3, x1, x2          # [0xAC] x3 = 42 (multi-cycle, stalls pipeline)
    add  x4, x3, x1          # [0xB0] x4 = 42+6 = 48 (forwarding from mul)


# HALT


    jal  x0, 0               # [0xB4] infinite loop (jump to self)
    nop                       # [0xB8] padding
    nop                       # [0xBC] padding


# TRAP HANDLER at address 0xC0 (word 48)

trap_handler:
    csrrs x31, mcause, x0    # [0xC0] x31 = mcause (should be 11)
    addi  x30, x0, 0xAB      # [0xC4] x30 = 0xAB (handler-reached flag)
    csrrs x1, mepc, x0       # [0xC8] x1 = mepc (address of ecall = 0xA0)
    addi  x1, x1, 4          # [0xCC] x1 = mepc + 4 (skip ecall)
    csrrw x0, mepc, x1       # [0xD0] mepc = 0xA4
    mret                      # [0xD4] return to 0xA4
