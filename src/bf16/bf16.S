# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    slli    t0, a0, 1
    lui     t1, 0xff000
    bgeu    t0, t1, .Lbf16_f32_done

    # Ordinary values: add 0x7FFF and the retained bit 0.
    srli    t0, a0, 16
    andi    t0, t0, 1
    lui     t1, 0x8
    addi    t1, t1, -1
    add     t1, t1, t0
    add     a0, a0, t1

.Lbf16_f32_done:
    # Inf and NaN also take this path, without the rounding addition.
    srli    a0, a0, 16
    jalr    zero, 0(ra)

    .size bf16_from_f32_asm, .-bf16_from_f32_asm
    
    
    

# a0 = a, a1 = b, a0 = product
# t0 = result sign
# t1/t3 = exponents, t2/t4 = significands
# t5 = result exponent, t6 = significand product
    .globl bf16_mul_asm
    .type bf16_mul_asm, @function
    .align 2
bf16_mul_asm:
    xor     t0, a0, a1
    srli    t0, t0, 15
    slli    t0, t0, 15

    srli    t1, a0, 7
    andi    t1, t1, 255
    andi    t2, a0, 127
    srli    t3, a1, 7
    andi    t3, t3, 255
    andi    t4, a1, 127

    # Examine a first: its NaN wins; its Inf can swallow b's NaN.
    addi    a2, zero, 255
    bne     t1, a2, .Lmul_check_b
    bne     t2, zero, .Lmul_return_a
    slli    a2, a1, 17
    beq     a2, zero, .Lmul_nan
    jal     zero, .Lmul_inf

.Lmul_check_b:
    addi    a2, zero, 255
    bne     t3, a2, .Lmul_check_zero
    bne     t4, zero, .Lmul_return_b
    slli    a2, a0, 17
    beq     a2, zero, .Lmul_nan
    jal     zero, .Lmul_inf

.Lmul_check_zero:
    slli    a2, a0, 17
    beq     a2, zero, .Lmul_return_sign
    slli    a2, a1, 17
    beq     a2, zero, .Lmul_return_sign

    # Normalize a if it is denormal.
    bne     t1, zero, .Lmul_a_normal
    addi    t1, zero, 1
.Lmul_a_denormal:
    andi    a2, t2, 128
    bne     a2, zero, .Lmul_b_start
    slli    t2, t2, 1
    addi    t1, t1, -1
    jal     zero, .Lmul_a_denormal
.Lmul_a_normal:
    ori     t2, t2, 128

.Lmul_b_start:
    bne     t3, zero, .Lmul_b_normal
    addi    t3, zero, 1
.Lmul_b_denormal:
    andi    a2, t4, 128
    bne     a2, zero, .Lmul_prepare
    slli    t4, t4, 1
    addi    t3, t3, -1
    jal     zero, .Lmul_b_denormal
.Lmul_b_normal:
    ori     t4, t4, 128

.Lmul_prepare:
    add     t5, t1, t3
    addi    t5, t5, -127
    addi    t6, zero, 0

    # Multiply the two 8-bit significands using shifts and additions.
.Lmul_bits:
    andi    a2, t4, 1
    beq     a2, zero, .Lmul_no_add
    add     t6, t6, t2
.Lmul_no_add:
    srli    t4, t4, 1
    beq     t4, zero, .Lmul_scaled
    slli    t2, t2, 1
    jal     zero, .Lmul_bits

.Lmul_scaled:
    srli    a2, t6, 15
    beq     a2, zero, .Lmul_fraction
    srli    t6, t6, 1
    addi    t5, t5, 1

.Lmul_fraction:
    srli    t6, t6, 7
    andi    t6, t6, 127
    addi    a2, zero, 255
    bge     t5, a2, .Lmul_inf
    bge     zero, t5, .Lmul_subnormal

    slli    t5, t5, 7
    or      a0, t0, t5
    or      a0, a0, t6
    jalr    zero, 0(ra)

.Lmul_subnormal:
    addi    a2, zero, -6
    blt     t5, a2, .Lmul_return_sign
    addi    a2, zero, 1
    sub     a2, a2, t5
    srl     t6, t6, a2
    or      a0, t0, t6
    jalr    zero, 0(ra)

.Lmul_inf:
    lui     a2, 0x8
    addi    a2, a2, -128
    or      a0, t0, a2
    jalr    zero, 0(ra)

.Lmul_nan:
    lui     a0, 0x8
    addi    a0, a0, -64
    jalr    zero, 0(ra)

.Lmul_return_b:
    addi    a0, a1, 0
.Lmul_return_a:
    jalr    zero, 0(ra)

.Lmul_return_sign:
    addi    a0, t0, 0
    jalr    zero, 0(ra)

    .size bf16_mul_asm, .-bf16_mul_asm





        .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    # t0 = exponent
    srli    t0, a0, 7
    andi    t0, t0, 255
    addi    t1, t0, -255
    beq     t1, zero, .Lsqrt_special

    # Both +0 and -0 produce +0.
    lui     t1, 0x8
    beq     a0, t1, .Lsqrt_zero

    # Negative nonzero values produce the quiet NaN.
    srli    t1, a0, 15
    bne     t1, zero, .Lsqrt_nan

    # Positive zero and denormals produce +0.
    beq     t0, zero, .Lsqrt_zero

    # t2 = significand, including its hidden leading bit.
    andi    t2, a0, 127
    ori     t2, t2, 128

    # e = exponent - 127. Make e even by doubling the
    # significand when necessary.
    addi    t0, t0, -127
    andi    t1, t0, 1
    beq     t1, zero, .Lsqrt_even
    slli    t2, t2, 1
    addi    t0, t0, -1

.Lsqrt_even:
    # t0 = encoded exponent of the answer.
    srai    t0, t0, 1
    addi    t0, t0, 127
    slli    t0, t0, 7

    # Find floor(sqrt(128 * (m + 1) - 1)).
    # This equals the largest root satisfying
    # floor(root * root / 128) <= m.
    addi    t3, t2, 1
    slli    t3, t3, 7
    addi    t3, t3, -1

    addi    t4, zero, 0       # Partial square root
    lui     t5, 0x4           # Initial bit: 1 << 14

.Lsqrt_loop:
    add     t6, t4, t5
    bltu    t3, t6, .Lsqrt_skip
    sub     t3, t3, t6
    srli    t4, t4, 1
    add     t4, t4, t5
    jal     zero, .Lsqrt_next

.Lsqrt_skip:
    srli    t4, t4, 1

.Lsqrt_next:
    srli    t5, t5, 2
    bne     t5, zero, .Lsqrt_loop

    andi    t4, t4, 127
    or      a0, t0, t4
    jalr    zero, 0(ra)

.Lsqrt_special:
    # Preserve NaNs and +Inf; -Inf produces the quiet NaN.
    andi    t1, a0, 127
    bne     t1, zero, .Lsqrt_return
    srli    t1, a0, 15
    bne     t1, zero, .Lsqrt_nan

.Lsqrt_return:
    jalr    zero, 0(ra)

.Lsqrt_nan:
    lui     a0, 0x8
    addi    a0, a0, -64      # 0x7FC0
    jalr    zero, 0(ra)

.Lsqrt_zero:
    addi    a0, zero, 0
    jalr    zero, 0(ra)

    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
