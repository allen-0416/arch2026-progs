#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;

    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a = (a ^ b);
        b = c;
        (*n)++;
    }

    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    uint16_t a_low = (uint32_t) a & 0xFFFF;
    uint16_t a_high = ((uint32_t) a >> 16) & 0xFFFF;
    uint16_t b_low = (uint32_t) b & 0xFFFF;
    uint16_t b_high = ((uint32_t) b >> 16) & 0xFFFF;

    uint32_t ll = (uint32_t) a_low * (uint32_t) b_low;
    uint32_t lh = (uint32_t) a_low * (uint32_t) b_high;
    uint32_t hl = (uint32_t) a_high * (uint32_t) b_low;
    uint32_t hh = (uint32_t) a_high * (uint32_t) b_high;

    uint32_t mid = (ll >> 16) + (lh & 0xFFFF) + (hl & 0xFFFF);
    uint32_t low = (mid << 16) | (ll & 0xFFFF);
    uint32_t high = (mid >> 16) + (lh >> 16) + (hl >> 16) + hh;

    if (a < 0) {
        high -= b;
    }

    if (b < 0) {
        high -= a;
    }

    return (int32_t) (((((uint64_t) high << 32) | low) + (1 << (Q - 1))) >> Q);
}
