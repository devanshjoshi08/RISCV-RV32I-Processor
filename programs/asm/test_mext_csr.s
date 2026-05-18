# test_mext_csr.s
# tests M extension multiply/divide and CSR read/write.
# expected results:
#   x10 = 91    (7*13)
#   x11 = 13    (91/7)
#   x12 = 0     (91%7)
#   x13 = -30   ((-6)*5)
#   x14 = mcycle snapshot (nonzero)
#   x15 = 0xDEADBEEF (mscratch readback)

.text
.globl _start
_start:
    # multiply tests
    li   x1, 7
    li   x2, 13
    mul  x10, x1, x2       # x10 = 7*13 = 91

    # divide tests
    li   x3, 91
    div  x11, x3, x1       # x11 = 91/7 = 13
    rem  x12, x3, x1       # x12 = 91%7 = 0

    # signed multiply
    li   x4, -6
    li   x5, 5
    mul  x13, x4, x5       # x13 = -30

    # CSR tests: read mcycle
    csrr x14, mcycle        # x14 = current cycle count

    # CSR tests: write and read mscratch
    li   x6, 0xDEADBEEF
    csrw mscratch, x6       # write mscratch
    csrr x15, mscratch      # x15 should be 0xDEADBEEF

    # halt
    jal  x0, 0             # infinite loop
