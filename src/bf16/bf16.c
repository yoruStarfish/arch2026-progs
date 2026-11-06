#include "bf16.h"

/*
 * Convert an IEEE 754 FP32 bit pattern to BF16.
 *
 * Input:
 *   f32bits: The raw 32-bit representation of an FP32 value.
 *
 * Output:
 *   The 16-bit BF16 representation.
 *
 * FP32 format:
 *   1 sign bit | 8 exponent bits | 23 fraction bits
 *
 * BF16 format:
 *   1 sign bit | 8 exponent bits | 7 fraction bits
 *
 * Since FP32 and BF16 have the same exponent width,
 * conversion mainly requires reducing the fraction
 * from 23 bits to 7 bits.
 *
 * Rounding mode:
 *   Round to Nearest, Ties to Even (RNE).
 */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    /*
     * Extract the 8-bit exponent from FP32.
     *
     * f32bits >> 23:
     *   Move the exponent field to the lowest 8 bits.
     *
     * & 0xffu:
     *   Keep only the lowest 8 bits.
     *
     * exponent == 0xff:
     *   The input is either Infinity or NaN.
     */
    uint32_t exponent = (f32bits >> 23) & 0xffu;

    /*
     * Handle special values (Infinity and NaN).
     *
     * Exponent = 255 indicates Infinity or NaN.
     * Return the upper 16 bits without normal rounding.
     *
     * Note: For some NaN bit patterns, truncation may
     * discard all nonzero fraction bits, producing Infinity.
     */
    if (exponent == 0xffu)
        return (uint16_t) (f32bits >> 16);

    /*
     * Extract the least significant bit of the
     * upper 16 bits that will be retained.
     *
     * f32bits >> 16:
     *   Move the retained upper 16 bits to the right.
     *
     * & 1u:
     *   Extract the LSB of the retained BF16 value.
     *
     * retained_lsb = 0: retained value is even.
     * retained_lsb = 1: retained value is odd.
     *
     * This bit is used to resolve halfway cases
     * according to the RNE rounding rule.
     */
    uint32_t retained_lsb = (f32bits >> 16) & 1u;

    /*
     * Round FP32 to BF16 using RNE.
     *
     * 0x7fff:
     *   Rounding bias, equal to 2^15 - 1.
     *
     * retained_lsb:
     *   Adds 1 only when the retained value is odd.
     *   This ensures ties are rounded to an even result.
     *
     * Adding the bias may generate a carry into
     * the upper 16 bits, rounding the BF16 value up.
     *
     * >> 16:
     *   Discard the lower 16 bits after rounding.
     *
     * (uint16_t):
     *   Return only the final 16-bit BF16 bit pattern.
     */
    return (uint16_t) ((f32bits + 0x7fffu + retained_lsb) >> 16);
}



/*
 * Multiply two BF16 values using integer arithmetic.
 *
 * Input:
 *   a: Raw 16-bit BF16 representation of the first operand.
 *   b: Raw 16-bit BF16 representation of the second operand.
 *
 * Output:
 *   Raw 16-bit BF16 representation of a * b.
 *
 * BF16 bit layout:
 *   Bit 15     : Sign (1 bit)
 *   Bits 14-7  : Exponent (8 bits, bias = 127)
 *   Bits 6-0   : Fraction (7 bits)
 *
 * For normal BF16 values:
 *   value = (-1)^sign * (1 + fraction / 128) * 2^(exponent - 127)
 *
 * Special exponent values:
 *   exponent = 0   : Zero or subnormal
 *   exponent = 255 : Infinity or NaN
 *
 * This implementation uses integer operations and truncates
 * the product fraction rather than applying RNE rounding.
 */
uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    /*
     * Step 1: Calculate the result sign.
     *
     * a ^ b:
     *   XOR the bits of a and b.
     *
     * & 0x8000u:
     *   Keep only bit 15, which is the BF16 sign bit.
     *
     * Equal signs produce a positive result.
     * Different signs produce a negative result.
     *
     * The sign remains in bit 15, ready to be combined
     * with the exponent and fraction later.
     */
    uint16_t sign = (uint16_t) ((a ^ b) & 0x8000u);

    /*
     * Step 2: Extract the exponent fields.
     *
     * >> 7:
     *   Move bits 14-7 into the lowest 8 positions.
     *
     * & 0xffu:
     *   Keep only those 8 exponent bits.
     *
     * The extracted exponents are biased values.
     * Their actual exponents are normally E - 127.
     */
    int exp_a = (a >> 7) & 0xffu;
    int exp_b = (b >> 7) & 0xffu;

    /*
     * Step 3: Extract the 7-bit fraction fields.
     *
     * 0x7f = binary 01111111.
     *
     * This mask removes the sign and exponent bits.
     *
     * The fraction does not include the implicit
     * leading 1 used by normal floating-point values.
     */
    uint32_t frac_a = a & 0x7fu;
    uint32_t frac_b = b & 0x7fu;

    /*
     * Step 4: Handle special values in operand a first.
     *
     * Exponent = 255 means Infinity or NaN.
     *
     * If the fraction is nonzero:
     *   a is NaN, so return its original bit pattern.
     *
     * Otherwise:
     *   a is positive or negative Infinity.
     *
     * Infinity multiplied by zero is invalid and
     * produces the canonical NaN 0x7fc0.
     *
     * Infinity multiplied by a nonzero finite value
     * produces signed Infinity.
     *
     * The order of these checks is intentional.
     */
    if (exp_a == 0xff) {
        if (frac_a != 0)
            return a;

        /*
         * 0x7fff clears the sign bit.
         * If the remaining bits are zero, b is +0 or -0.
         */
        if ((b & 0x7fffu) == 0)
            return 0x7fc0u;

        /*
         * 0x7f80 is positive BF16 Infinity.
         * OR with sign to select +Infinity or -Infinity.
         */
        return (uint16_t) (sign | 0x7f80u);
    }

    /*
     * Step 5: Handle special values in operand b.
     *
     * This follows the same logic as operand a.
     *
     * NaN is returned directly.
     * Infinity * zero produces NaN.
     * Infinity * nonzero finite value produces Infinity.
     */
    if (exp_b == 0xff) {
        if (frac_b != 0)
            return b;

        if ((a & 0x7fffu) == 0)
            return 0x7fc0u;

        return (uint16_t) (sign | 0x7f80u);
    }

    /*
     * Step 6: Handle multiplication by zero.
     *
     * Ignore the sign bit when checking for zero.
     *
     * If either operand is +0 or -0, return signed zero.
     *
     * Returning sign preserves the XOR result:
     *   sign = 0x0000 -> +0
     *   sign = 0x8000 -> -0
     */
    if ((a & 0x7fffu) == 0 || (b & 0x7fffu) == 0)
        return sign;

    /*
     * Step 7: Construct integer mantissas.
     *
     * For a normal BF16 number:
     *   Mantissa = 1.fraction (binary).
     *
     * The leading 1 is implicit, so restore it
     * by setting bit 7 with 0x80.
     *
     * Example:
     *   Fraction = 1000000
     *   Mantissa = 11000000 = 192
     *   Actual significand = 192 / 128 = 1.5
     *
     * For a subnormal number (exponent = 0):
     *   There is no implicit leading 1.
     *   The mantissa initially contains only the fraction.
     */
    uint32_t mant_a = frac_a | (exp_a != 0 ? 0x80u : 0u);
    uint32_t mant_b = frac_b | (exp_b != 0 ? 0x80u : 0u);

    /*
     * Step 8: Normalize subnormal operand a.
     *
     * Subnormal BF16:
     *   exponent = 0
     *   significand = 0.fraction
     *   actual exponent = -126
     *
     * Start with exponent = 1 so that the effective
     * exponent is 1 - 127 = -126.
     *
     * Shift the mantissa left until bit 7 becomes 1.
     * Each left shift doubles the mantissa.
     *
     * Decrease the exponent by 1 after each shift
     * to preserve the numerical value:
     *
     *   M * 2^e = (2M) * 2^(e-1)
     *
     * The operand is known to be nonzero here,
     * so this loop eventually terminates.
     */
    if (exp_a == 0) {
        exp_a = 1;

        while (mant_a < 0x80u) {
            mant_a <<= 1;
            exp_a--;
        }
    }

    /*
     * Step 9: Normalize subnormal operand b.
     *
     * Apply the same procedure to the second operand.
     */
    if (exp_b == 0) {
        exp_b = 1;

        while (mant_b < 0x80u) {
            mant_b <<= 1;
            exp_b--;
        }
    }

    /*
     * Step 10: Calculate the biased result exponent.
     *
     * Actual exponent of a = exp_a - 127
     * Actual exponent of b = exp_b - 127
     *
     * Their product has actual exponent:
     *   (exp_a - 127) + (exp_b - 127)
     *
     * Add 127 to store it in biased BF16 format:
     *   exponent = exp_a + exp_b - 127
     */
    int exponent = exp_a + exp_b - 127;

    /*
     * Step 11: Multiply the integer mantissas.
     *
     * Each normalized mantissa represents an
     * 8-bit fixed-point number with 7 fraction bits.
     *
     * Actual significand:
     *   mantissa / 128
     *
     * Therefore:
     *   actual product = (mant_a * mant_b) / 2^14
     *
     * Multiplying two 8-bit mantissas can produce
     * a result requiring up to 16 bits.
     */
    uint32_t product = mant_a * mant_b;

    /*
     * Step 12: Normalize the mantissa product.
     *
     * Each normalized significand lies in [1, 2).
     * Their product therefore lies in [1, 4).
     *
     * If bit 15 is set, the product is at least 2.
     * Shift right once and increase the exponent.
     *
     * Example:
     *   1.5 * 1.5 = 2.25
     *   2.25 * 2^e = 1.125 * 2^(e+1)
     */
    if ((product & 0x8000u) != 0) {
        product >>= 1;
        exponent++;
    }

    /*
     * Step 13: Extract the 7-bit BF16 fraction.
     *
     * After normalization, the leading 1 is at bit 14.
     *
     * >> 7:
     *   Move product bits 13-7 into positions 6-0.
     *
     * & 0x7f:
     *   Keep only the 7 stored fraction bits.
     *
     * The implicit leading 1 is not stored.
     *
     * Important:
     *   This discards the lower product bits.
     *   No Round-to-Nearest-Even rounding is performed.
     */
    uint32_t fraction = (product >> 7) & 0x7fu;

    /*
     * Step 14: Handle exponent overflow.
     *
     * Exponent 255 is reserved for Infinity and NaN.
     *
     * If the calculated biased exponent is >= 255,
     * return signed Infinity.
     */
    if (exponent >= 0xff)
        return (uint16_t) (sign | 0x7f80u);

    /*
     * Step 15: Handle exponent underflow.
     *
     * A normal BF16 exponent must be at least 1.
     *
     * If exponent <= 0, the result may need
     * subnormal representation or may underflow to zero.
     *
     * If exponent < -6, this implementation
     * immediately returns signed zero.
     *
     * Otherwise, shift the extracted fraction right
     * to construct a subnormal fraction.
     *
     * IMPORTANT:
     *   This implementation loses the implicit leading 1
     *   before the subnormal shift.
     *   Therefore this branch is not generally correct
     *   for subnormal results.
     */
    if (exponent <= 0) {
        if (exponent < -6)
            return sign;

        return (uint16_t) (sign | (fraction >> (1 - exponent)));
    }

    /*
     * Step 16: Assemble the final BF16 representation.
     *
     * sign:
     *   Already located at bit 15.
     *
     * exponent << 7:
     *   Move the 8-bit biased exponent into bits 14-7.
     *
     * fraction:
     *   Occupies bits 6-0.
     *
     * Bitwise OR combines the three non-overlapping fields.
     */
    return (uint16_t) (sign | ((uint32_t) exponent << 7) | fraction);
}



/*
 * Compute the square root of a BF16 value using integer arithmetic.
 *
 * BF16 format:
 *   Bit 15     : Sign (1 bit)
 *   Bits 14-7  : Exponent (8 bits, bias = 127)
 *   Bits 6-0   : Fraction (7 bits)
 *
 * For a normal positive BF16 value:
 *
 *   x = (1 + fraction / 128) * 2^(exponent - 127)
 *
 * The square root is:
 *
 *   sqrt(x) = sqrt(mantissa) * 2^(e / 2)
 *
 * This implementation:
 *   1. Handles special values.
 *   2. Extracts and adjusts the exponent and mantissa.
 *   3. Uses binary search to approximate the square root.
 *   4. Normalizes and assembles the BF16 result.
 *
 * Note:
 *   This is an approximate implementation.
 *   It does not implement full IEEE 754 rounding.
 */
uint16_t bf16_sqrt(uint16_t a)
{
    /*
     * Step 1: Extract the sign, exponent, and fraction.
     *
     * 0x8000 selects the sign bit.
     * 0xff selects the 8-bit exponent.
     * 0x7f selects the 7-bit fraction.
     */
    uint32_t sign = a & 0x8000u;
    uint32_t exponent = (a >> 7) & 0xffu;
    uint32_t fraction = a & 0x7fu;

    /*
     * Step 2: Handle Infinity and NaN.
     *
     * exponent == 255 indicates Infinity or NaN.
     *
     * If fraction != 0:
     *   The input is NaN. Preserve its original bit pattern.
     *
     * If fraction == 0:
     *   The input is Infinity.
     *
     * sqrt(+Infinity) = +Infinity
     * sqrt(-Infinity) = NaN
     *
     * 0x7fc0 is a canonical quiet NaN in BF16.
     */
    if (exponent == 0xffu) {
        if (fraction != 0)
            return a; /* Preserve the NaN pattern. */

        return sign != 0 ? 0x7fc0u : a;
    }

    /*
     * Step 3: Handle positive and negative zero.
     *
     * 0x7fff removes the sign bit.
     *
     * If all remaining bits are zero, the input is
     * either +0 or -0.
     *
     * This implementation returns +0 for both.
     */
    if ((a & 0x7fffu) == 0)
        return 0;

    /*
     * Step 4: Handle negative finite numbers.
     *
     * The square root of a negative real number is
     * not a real number.
     *
     * Return the canonical BF16 NaN.
     */
    if (sign != 0)
        return 0x7fc0u;

    /*
     * Step 5: Handle subnormal numbers.
     *
     * exponent == 0 and fraction != 0 indicates
     * a subnormal BF16 number.
     *
     * This implementation flushes positive
     * subnormal inputs to +0.
     *
     * This is a simplification rather than
     * IEEE 754 compliant square-root behavior.
     */
    if (exponent == 0)
        return 0;

    /*
     * Step 6: Convert the biased exponent into
     * the actual exponent.
     *
     * BF16 uses an exponent bias of 127.
     *
     * Example:
     *   Stored exponent = 130
     *   Actual exponent = 130 - 127 = 3
     */
    int32_t e = (int32_t) exponent - 127;

    /*
     * Step 7: Restore the implicit leading 1.
     *
     * For normal BF16 values, the significand is:
     *
     *   1.fraction (binary)
     *
     * 0x80 sets bit 7, restoring the hidden leading 1.
     *
     * The integer mantissa is scaled by 128:
     *
     *   Actual significand = mantissa / 128
     *
     * Example:
     *   1.5 = 1.1000000 (binary)
     *   mantissa = 11000000 = 192
     *   192 / 128 = 1.5
     */
    uint32_t mantissa = 0x80u | fraction;

    /*
     * Step 8: Make the actual exponent even.
     *
     * sqrt(M * 2^e) = sqrt(M) * 2^(e/2)
     *
     * If e is odd, move one factor of 2
     * from the exponent into the mantissa.
     *
     * Doubling the mantissa and decreasing e by 1
     * preserves the original numerical value:
     *
     *   M * 2^e = (2M) * 2^(e-1)
     *
     * The resulting exponent is even.
     */
    if (e % 2 != 0) {
        mantissa <<= 1;
        e--;
    }

    /*
     * Step 9: Calculate the result exponent.
     *
     * Since e is now even, e / 2 is an integer.
     *
     * Add the BF16 bias back to obtain
     * the stored exponent field.
     */
    int32_t result_exponent = e / 2 + 127;

    /*
     * Step 10: Initialize the binary-search range.
     *
     * The result mantissa is represented as an
     * integer scaled by 128.
     *
     * Let R be the candidate result mantissa.
     *
     * The target is approximately:
     *
     *   (R / 128)^2 = mantissa / 128
     *
     * Multiplying both sides by 128:
     *
     *   R^2 / 128 = mantissa
     *
     * Therefore, the search compares:
     *
     *   (R * R) >> 7
     *
     * against the input mantissa.
     *
     * low and high define the search interval.
     * result stores the best accepted candidate.
     */
    uint32_t low = 90;
    uint32_t high = 256;
    uint32_t result = 128;

    /*
     * Step 11: Use binary search to find the largest
     * candidate whose scaled square does not exceed
     * the input mantissa.
     *
     * If mid^2 / 128 <= mantissa:
     *   mid is accepted, and the search moves right.
     *
     * Otherwise:
     *   mid is too large, and the search moves left.
     *
     * Because >> 7 discards fractional bits,
     * this is an integer approximation.
     */
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        uint32_t scaled_square = (mid * mid) >> 7;

        if (scaled_square <= mantissa) {
            result = mid;
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }

    /*
     * Step 12: Normalize the resulting mantissa.
     *
     * A normal BF16 significand should be in [1, 2).
     *
     * Since result is scaled by 128:
     *   Normalized result must be in [128, 256).
     *
     * If result >= 256:
     *   Shift right once and increment the exponent.
     *
     * If result < 128:
     *   Shift left and decrement the exponent,
     *   provided the stored exponent remains above 1.
     */
    if (result >= 256) {
        result >>= 1;
        result_exponent++;
    } else {
        while (result < 128 && result_exponent > 1) {
            result <<= 1;
            result_exponent--;
        }
    }

    /*
     * Step 13: Handle exponent overflow.
     *
     * Exponent 255 is reserved for Infinity and NaN.
     *
     * Return positive Infinity if the result exponent
     * exceeds the normal BF16 exponent range.
     */
    if (result_exponent >= 0xff)
        return 0x7f80u;

    /*
     * Step 14: Handle exponent underflow.
     *
     * This implementation returns +0 if the
     * result exponent is zero or negative.
     */
    if (result_exponent <= 0)
        return 0;

    /*
     * Step 15: Assemble the final BF16 representation.
     *
     * The square root of a positive number is positive,
     * so the sign bit is zero.
     *
     * result_exponent << 7:
     *   Place the exponent into bits 14-7.
     *
     * result & 0x7f:
     *   Keep only the lowest 7 fraction bits.
     *
     * The implicit leading 1 is not stored.
     */
    return (uint16_t) (((uint32_t) result_exponent << 7) | (result & 0x7fu));
}
