// perf_report.c
// runs fibonacci, then reads hardware performance counters and
// prints IPC, cycle count, instruction count, and branch stats over UART.
// compile with: make perf_report

#include "mmio.h"

static inline unsigned int read_mcycle(void) {
    unsigned int val;
    asm volatile("csrr %0, mcycle" : "=r"(val));
    return val;
}

static inline unsigned int read_minstret(void) {
    unsigned int val;
    asm volatile("csrr %0, minstret" : "=r"(val));
    return val;
}

static inline unsigned int read_branches(void) {
    unsigned int val;
    asm volatile("csrr %0, 0xB04" : "=r"(val));
    return val;
}

static inline unsigned int read_mispredicts(void) {
    unsigned int val;
    asm volatile("csrr %0, 0xB03" : "=r"(val));
    return val;
}

void compute_fibonacci(void) {
    int a = 0, b = 1;
    for (int i = 0; i < 20; i++) {
        uart_puts("F(");
        uart_put_dec(i);
        uart_puts(") = ");
        uart_put_dec(a);
        uart_puts("\r\n");
        LED_REG = a & 0xFFFF;
        int next = a + b;
        a = b;
        b = next;
    }
}

void main(void) {
    // reset counters by reading baseline
    unsigned int c0 = read_mcycle();
    unsigned int i0 = read_minstret();
    unsigned int b0 = read_branches();
    unsigned int m0 = read_mispredicts();

    compute_fibonacci();

    unsigned int c1 = read_mcycle();
    unsigned int i1 = read_minstret();
    unsigned int b1 = read_branches();
    unsigned int m1 = read_mispredicts();

    unsigned int cycles = c1 - c0;
    unsigned int instrs = i1 - i0;
    unsigned int branches = b1 - b0;
    unsigned int mispred = m1 - m0;

    uart_puts("\r\n--- Performance Report ---\r\n");
    uart_puts("Cycles:         "); uart_put_dec(cycles); uart_puts("\r\n");
    uart_puts("Instructions:   "); uart_put_dec(instrs); uart_puts("\r\n");
    uart_puts("IPC:            "); uart_put_dec(instrs / cycles); uart_puts(".");
    // fractional part: (instrs % cycles) * 100 / cycles
    unsigned int frac = ((instrs % cycles) * 100) / cycles;
    if (frac < 10) uart_putc('0');
    uart_put_dec(frac);
    uart_puts("\r\n");
    uart_puts("Branches:       "); uart_put_dec(branches); uart_puts("\r\n");
    uart_puts("Mispredictions: "); uart_put_dec(mispred); uart_puts("\r\n");
    if (branches > 0) {
        uart_puts("Mispredict rate: ");
        unsigned int rate = (mispred * 100) / branches;
        uart_put_dec(rate);
        uart_puts("%\r\n");
    }
    uart_puts("--- End Report ---\r\n");

    // show IPC on LEDs (scaled: IPC * 1000)
    LED_REG = (instrs * 1000) / cycles;

    while (1); // halt
}
