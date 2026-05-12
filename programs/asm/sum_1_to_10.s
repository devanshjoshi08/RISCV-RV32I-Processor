# sum 1 to 10, result should be 55
# x1 = sum, x5 = copy, mem[0] = stored

        addi x1, x0, 0       # sum = 0
        addi x2, x0, 1       # i = 1
        addi x3, x0, 11      # upper bound (exclusive)
loop:
        add  x1, x1, x2      # sum += i
        addi x2, x2, 1       # i++
        blt  x2, x3, loop
        sw   x1, 0(x0)       # store to mem[0]
        addi x5, x1, 0       # copy to x5
end:
        jal  x0, end
