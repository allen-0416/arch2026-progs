#include "bf16.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint16_t exp = (f32bits >> 23) & 0xFF;

    if (exp == 0xFF) {
        return f32bits >> 16;  // NaN or Infinity
    } else {
        int bit16 = (f32bits >> 16) & 1u;
        f32bits += 0x7FFF;
        f32bits += bit16;
        return f32bits >> 16;
    }
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint8_t sign_a = (a >> 15) & 0x1;
    uint8_t exp_a = (a >> 7) & 0xFF;
    uint8_t mant_a = a & 0x7F;

    uint8_t sign_b = (b >> 15) & 0x1;
    uint8_t exp_b = (b >> 7) & 0xFF;
    uint8_t mant_b = b & 0x7F;

    uint8_t sign_result = sign_a ^ sign_b;

    if (exp_a == 0xFF) {
        if (mant_a != 0) {
            return a;  // NaN
        } else if (exp_b == 0 && mant_b == 0) {
            return 0x7FC0;
        } else {
            return sign_result << 15 | 0x7F80;  // Infinity
        }
    }

    if (exp_b == 0xFF) {
        if (mant_b != 0) {
            return b;  // NaN
        } else if (exp_a == 0 && mant_a == 0) {
            return 0x7FC0;
        } else {
            return sign_result << 15 | 0x7F80;  // Infinity
        }
    }

    if (exp_a == 0 && mant_a == 0) {
        return sign_result << 15;  // Zero
    }

    if (exp_b == 0 && mant_b == 0) {
        return sign_result << 15;  // Zero
    }

    uint8_t significand_a;
    uint8_t significand_b;
    int k = 0;

    if (exp_a != 0) {
        significand_a = mant_a | 0x80;
    } else {
        significand_a = mant_a;
        while (((significand_a >> 7) & 0x1) == 0) {
            significand_a <<= 1;
            k += 1;
        }
        exp_a = 0x01;
    }

    if (exp_b != 0) {
        significand_b = mant_b | 0x80;
    } else {
        significand_b = mant_b;
        while (((significand_b >> 7) & 0x1) == 0) {
            significand_b <<= 1;
            k += 1;
        }
        exp_b = 0x01;
    }

    uint32_t product = significand_a * significand_b;
    int exp_result = exp_a + exp_b - 127 - k;

    if (product & 0x8000) {
        product >>= 8;
        exp_result += 1;
    } else {
        product >>= 7;
    }

    uint8_t mant_result = product & 0x7F;

    if (exp_result >= 0xFF) {
        return (sign_result << 15) | 0x7F80;  // Infinity
    } else if (exp_result < -6) {
        return sign_result << 15;  // Zero
    } else if (exp_result <= 0) {
        int shamt = 1 - exp_result;
        mant_result >>= shamt;
        return (sign_result << 15) | mant_result;
    } else {
        return (sign_result << 15) | ((exp_result & 0xFF) << 7) | mant_result;
    }
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint8_t sign = (a >> 15) & 0x1;
    uint8_t exp = (a >> 7) & 0xFF;
    uint8_t mant = a & 0x7F;

    if (exp == 0xFF) {
        if (mant != 0) {
            return a;  // NaN
        } else if (sign == 0) {
            return a;  // Infinity
        } else {
            return 0x7FC0;  // -Infinity
        }

    } else if (exp == 0 && mant == 0) {
        return 0x0000;  // Zero

    } else if (sign == 1) {
        return 0x7FC0;  // NaN

    } else if (exp == 0) {
        return 0x0000;  // denormalized number, return 0
    }

    int e = exp - 127;
    uint16_t m = mant | 0x80;  // Add implicit leading 1

    if ((e & 0x1) == 1) {
        m <<= 1;
        e -= 1;
    }

    int exp_result = (e / 2) + 127;

    int low = 90, high = 256, result = 0;
    while (low <= high) {
        int mid = (low + high) / 2;
        uint32_t mid_squared = (uint32_t) mid * (uint32_t) mid;
        if (mid_squared / 128 <= m) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    return (sign << 15) | ((exp_result & 0xFF) << 7) | (result & 0x7F);
}
