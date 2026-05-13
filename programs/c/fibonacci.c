// runs on the rv32i processor on the basys 3.
// prints F(0) through F(19) over UART (115200 baud, shows up in serial terminal)
// and puts the lower 16 bits of each value on the board's LEDs.

#include "mmio.h"

int main(void) {
    uart_puts("Fibonacci\r\n");

    int a = 0, b = 1;

    for (int i = 0; i < 20; i++) {
        // print "F(n) = val" to serial
        uart_puts("F(");
        uart_put_dec(i);
        uart_puts(") = ");
        uart_put_dec(a);
        uart_puts("\r\n");

        // show on basys 3 LEDs
        LED_REG = a & 0xFFFF;

        int next = a + b;
        a = b;
        b = next;
    }

    uart_puts("Done.\r\n");
    return 0;
}
