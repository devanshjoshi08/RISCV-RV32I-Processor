#include "mmio.h"

int main(void) {
    uart_puts("=== Fibonacci on RISC-V ===\r\n");

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

    uart_puts("Done.\r\n");
    return 0;
}
