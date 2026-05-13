// runs on the rv32i processor on the basys 3.
// sorts an array, prints before/after over UART, shows element count on LEDs.

#include "mmio.h"

void bubble_sort(int *arr, int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - i - 1; j++) {
            if (arr[j] > arr[j + 1]) {
                int temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
            }
        }
    }
}

int main(void) {
    int arr[] = {64, 25, 12, 22, 11, 90, 45, 3};
    int n = sizeof(arr) / sizeof(arr[0]);

    uart_puts("Bubble Sort\r\n");

    uart_puts("Before: ");
    for (int i = 0; i < n; i++) {
        uart_put_dec(arr[i]);
        if (i < n - 1) uart_puts(", ");
    }
    uart_puts("\r\n");

    bubble_sort(arr, n);

    uart_puts("After:  ");
    for (int i = 0; i < n; i++) {
        uart_put_dec(arr[i]);
        if (i < n - 1) uart_puts(", ");
    }
    uart_puts("\r\n");

    // show how many elements were sorted
    LED_REG = n;
    uart_puts("Done. LED = ");
    uart_put_dec(n);
    uart_puts("\r\n");

    return 0;
}
