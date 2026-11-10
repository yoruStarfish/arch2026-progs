#include "fixed.h"



uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;

    // Repeat until there are no more carries.
    while (b != 0u) {
        // Calculate the carry bits and shift them left.
        uint32_t carry = (a & b) << 1;

        // Calculate the sum without carries using XOR.
        a ^= b;

        // Use the carry bits for the next iteration.
        b = carry;
        passes++;
    }

    // Store the number of carry propagation passes.
    *n = passes;

    // Return the final 32-bit sum.
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
    uint32_t ua = a < 0 ? 0u - (uint32_t) a : (uint32_t) a;
    uint32_t ub = b < 0 ? 0u - (uint32_t) b : (uint32_t) b;
    uint32_t al = ua & 0xffffu, ah = ua >> 16;
    uint32_t bl = ub & 0xffffu, bh = ub >> 16;

    uint64_t product = (uint64_t) (al * bl) + ((uint64_t) (al * bh) << 16) +
                       ((uint64_t) (ah * bl) << 16) +
                       ((uint64_t) (ah * bh) << 32);

    int64_t signed_product =
        (a < 0) != (b < 0) ? -(int64_t) product : (int64_t) product;
    int64_t result = (signed_product + ((int64_t) 1 << (Q - 1))) >> Q;

    return (int32_t) (uint32_t) result;
}
