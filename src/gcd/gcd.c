#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0) {
        return b;
    }

    if (b == 0) {
        return a;
    }

    int k = 0;

    while ((a & 0x0001) == 0 && (b & 0x0001) == 0) {
        k += 1;
        a = a >> 1;
        b = b >> 1;
    }

    while ((a & 0x0001) == 0) {
        a = a >> 1;
    }

    while ((b & 0x0001) == 0) {
        b = b >> 1;
    }

    while (a != b) {
        if (a > b) {
            a = a - b;
            while ((a & 0x0001) == 0) {
                a = a >> 1;
            }
        } else {
            b = b - a;
            while ((b & 0x0001) == 0) {
                b = b >> 1;
            }
        }
    }

    return (a << k);
}
