// hardware registers mapped to the basys 3 peripherals.
// writing to these addresses talks to LEDs, switches, and UART
// instead of regular memory. see mmio.sv for the RTL side.

#ifndef MMIO_H
#define MMIO_H

#define MMIO_BASE       0x10000000
#define LED_REG         (*(volatile unsigned int *)(MMIO_BASE + 0x00))  // basys 3 LEDs [15:0]
#define SWITCH_REG      (*(volatile unsigned int *)(MMIO_BASE + 0x04))  // basys 3 switches [15:0]
#define UART_DATA_REG   (*(volatile unsigned int *)(MMIO_BASE + 0x08))  // write a byte to send over serial
#define UART_STATUS_REG (*(volatile unsigned int *)(MMIO_BASE + 0x0C))  // bit 0 = busy

// send one byte over UART, waits if the transmitter is still busy
static inline void uart_putc(char c) {
    while (UART_STATUS_REG & 1);
    UART_DATA_REG = (unsigned int)c;
}

static inline void uart_puts(const char *s) {
    while (*s)
        uart_putc(*s++);
}

static inline void uart_put_hex(unsigned int val) {
    const char hex[] = "0123456789ABCDEF";
    uart_puts("0x");
    for (int i = 28; i >= 0; i -= 4)
        uart_putc(hex[(val >> i) & 0xF]);
}

// rv32i has no div/mod instructions so this does it with subtraction
static inline void uart_put_dec(int val) {
    if (val < 0) { uart_putc('-'); val = -val; }
    if (val == 0) { uart_putc('0'); return; }
    char buf[12];
    int i = 0;
    while (val > 0) {
        int q = 0, r = val;
        while (r >= 10) { r -= 10; q++; }
        buf[i++] = '0' + r;
        val = q;
    }
    while (i > 0) uart_putc(buf[--i]);
}

#endif
