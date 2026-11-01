#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    unsigned shift = 0;

    /* Remove factors of two shared by both operands. */
    while (((a | b) & 1u) == 0) {
        a >>= 1;
        b >>= 1;
        shift++;
    }

    /* Keep a odd. */
    while ((a & 1u) == 0)
        a >>= 1;

    do {
        /* Keep b odd. */
        while ((b & 1u) == 0)
            b >>= 1;

        if (a > b) {
            uint32_t tmp = a;
            a = b;
            b = tmp;
        }

        /* Both operands are odd, so their difference is even. */
        b -= a;
    } while (b != 0);

    /* Restore the shared factors of two. */
    return a << shift;
}
