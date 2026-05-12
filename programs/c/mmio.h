#ifndef MMIO_H
#define MMIO_H

// addresses match mmio.sv
#define MMIO_BASE       0x10000000
#define LED_REG         (*(volatile unsigned int *)(MMIO_BASE + 0x00))
#define SWITCH_REG      (*(volatile unsigned int *)(MMIO_BASE + 0x04))
#define UART_DATA_REG   (*(volatile unsigned int *)(MMIO_BASE + 0x08))
#define UART_STATUS_REG (*(volatile unsigned int *)(MMIO_BASE + 0x0C))

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

static inline void uart_put_dec(int val) {
    if (val < 0) { uart_putc('-'); val = -val; }
    if (val == 0) { uart_putc('0'); return; }
    char buf[12];
    int i = 0;
    while (val > 0) { buf[i++] = '0' + (val % 10); val /= 10; }
    while (i > 0) uart_putc(buf[--i]);
}

#endif
