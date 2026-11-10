# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    addi    t1, zero, 0       # passes = 0
    beq     a1, zero, .Lop1_done

.Lop1_loop:
    and     t0, a0, a1        # Carry bits
    xor     a0, a0, a1        # Sum without carry
    slli    a1, t0, 1         # Carry for the next pass
    addi    t1, t1, 1
    bne     a1, zero, .Lop1_loop

.Lop1_done:
    sw      t1, 0(a2)         # *n = passes
    jalr    zero, 0(ra)

    .size   op1_asm, .-op1_asm



    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    jalr    zero, 0(ra)
    .size   op2_asm, .-op2_asm




    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    jalr    zero, 0(ra)
    .size   op3_asm, .-op3_asm
    
    
    

        .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    # a2 = 1 if the product is negative.
    xor     a2, a0, a1
    srli    a2, a2, 31

    # t1 and t2 = unsigned magnitudes of a and b.
    srai    t0, a0, 31
    xor     t1, a0, t0
    sub     t1, t1, t0

    srai    t0, a1, 31
    xor     t2, a1, t0
    sub     t2, t2, t0

    # t3:t1 = shifted multiplicand.
    # t5:t4 = accumulated 64-bit product.
    addi    t3, zero, 0
    addi    t4, zero, 0
    addi    t5, zero, 0
    beq     t2, zero, .Lqmul_product_ready

.Lqmul_loop:
    andi    t6, t2, 1
    beq     t6, zero, .Lqmul_shift

    add     t4, t4, t1
    sltu    t6, t4, t1       # Carry from the low word
    add     t5, t5, t3
    add     t5, t5, t6

.Lqmul_shift:
    srli    t6, t1, 31
    slli    t3, t3, 1
    or      t3, t3, t6
    slli    t1, t1, 1
    srli    t2, t2, 1
    bne     t2, zero, .Lqmul_loop

.Lqmul_product_ready:
    # Negate the full 64-bit product when signs differ.
    beq     a2, zero, .Lqmul_round
    sub     t4, zero, t4
    sltu    t6, zero, t4
    sub     t5, zero, t5
    sub     t5, t5, t6

.Lqmul_round:
    # Add 2^19 before shifting right by 20.
    lui     t6, 0x80
    add     t4, t4, t6
    sltu    t6, t4, t6
    add     t5, t5, t6

    # Low 32 bits of the arithmetic 64-bit shift by 20.
    srli    t4, t4, 20
    slli    t5, t5, 12
    or      a0, t4, t5
    jalr    zero, 0(ra)

    .size   q_mul_asm, .-q_mul_asm
