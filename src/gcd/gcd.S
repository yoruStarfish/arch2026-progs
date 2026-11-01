
# gcd_u32_asm: Binary GCD (Stein's Algorithm), implemented in RV32I.
#
# Function prototype:
#   uint32_t gcd_u32_asm(uint32_t a, uint32_t b)
#
# Description:
#   Compute the greatest common divisor (GCD) of two unsigned
#   32-bit integers using bitwise operations, subtraction,
#   and unsigned comparison instead of division or modulo.
#
# Input:
#   a0 = a (first unsigned 32-bit integer)
#   a1 = b (second unsigned 32-bit integer)
#
# Output:
#   a0 = gcd(a, b)
#
# Registers:
#   a0 = a, also used to store the final result
#   a1 = b
#   a2 = shift, number of shared factors of 2
#   t0 = temporary register used for parity checking
#   ra = return address of the calling function
#   zero (x0) = constant zero; writes to x0 are discarded
#
# Mathematical properties:
#   gcd(0, b) = b
#   gcd(a, 0) = a
#   gcd(2a, 2b) = 2 * gcd(a, b)
#   gcd(2a, b) = gcd(a, b), when b is odd
#   gcd(a, 2b) = gcd(a, b), when a is odd
#   gcd(a, b) = gcd(a, b-a), when b >= a
#   gcd(a, b) = gcd(a-b, b), when a > b
#
# RV32I and Zicsr only:
#   No mul, div, rem, floating-point, or compressed instructions.
#
# Tests: tests/tgcd.c

    # Place the following instructions in the code section.
    .text

    # Make gcd_u32_asm visible to the linker.
    .globl gcd_u32_asm

    # Declare gcd_u32_asm as a function symbol.
    .type gcd_u32_asm, @function

    # Align the function to a 2^2 = 4-byte boundary.
    .align 2

gcd_u32_asm:
    # Handle special cases before entering the main algorithm.
    #
    # beq rs1, rs2, label:
    # Branch to label if rs1 == rs2.

    # If a == 0, jump to .Lreturn_b and return b.
    # a0 = a, zero = 0
    beq     a0, zero, .Lreturn_b

    # If b == 0, return a directly.
    # a1 = b, zero = 0
    beq     a1, zero, .Lreturn

    # Initialize shift = 0.
    #
    # addi rd, rs1, imm:
    # rd = rs1 + immediate
    #
    # a2 = zero + 0 = 0
    addi    a2, zero, 0


.Lcommon_twos:
    # Step 1: Remove factors of 2 shared by both operands.
    #
    # Mathematical property:
    # gcd(2a, 2b) = 2 * gcd(a, b)
    #
    # Each time both operands are divided by 2,
    # increment shift to remember the removed factor.

    # or rd, rs1, rs2:
    # rd = rs1 | rs2 (bitwise OR)
    #
    # t0 = a | b
    # The least significant bit is 0 only if both are even.
    or      t0, a0, a1

    # andi rd, rs1, imm:
    # rd = rs1 & immediate (bitwise AND)
    #
    # t0 = (a | b) & 1
    #
    # t0 == 0: both a and b are even.
    # t0 == 1: at least one operand is odd.
    andi    t0, t0, 1

    # bne rs1, rs2, label:
    # Branch if rs1 != rs2.
    #
    # If t0 != 0, at least one operand is odd.
    # Stop removing common factors of 2.
    bne     t0, zero, .Lmake_a_odd

    # Both operands are even.
    #
    # srli rd, rs1, shamt:
    # Logical right shift by a constant number of bits.
    #
    # a = a >> 1 (unsigned division by 2)
    srli    a0, a0, 1

    # b = b >> 1 (unsigned division by 2)
    srli    a1, a1, 1

    # shift = shift + 1
    # Record one additional shared factor of 2.
    addi    a2, a2, 1

    # jal rd, label:
    # Jump to label and write the return address into rd.
    #
    # Here rd = zero (x0), so the return address is discarded.
    # This acts as an unconditional jump (goto).
    #
    # Repeat the common-factor removal process.
    jal     zero, .Lcommon_twos


.Lmake_a_odd:
    # Step 2: Remove the remaining factors of 2 from a.
    #
    # After .Lcommon_twos, at least one operand is odd.
    # If a is even, b must be odd.
    #
    # Mathematical property:
    # gcd(2a, b) = gcd(a, b), when b is odd.
    #
    # These shifts do not increase shift because
    # the removed factors of 2 are not shared.

    # t0 = a & 1
    #
    # t0 == 0: a is even.
    # t0 == 1: a is odd.
    andi    t0, a0, 1

    # If a is already odd, proceed to process b.
    bne     t0, zero, .Lmake_b_odd

    # Otherwise, divide a by 2.
    # a = a >> 1
    srli    a0, a0, 1

    # Repeat until a becomes odd.
    jal     zero, .Lmake_a_odd


.Lmake_b_odd:
    # Step 3: Remove the remaining factors of 2 from b.
    #
    # At this point, a is already odd.
    #
    # Mathematical property:
    # gcd(a, 2b) = gcd(a, b), when a is odd.
    #
    # The main algorithm requires both operands to be odd.

    # t0 = b & 1
    #
    # t0 == 0: b is even.
    # t0 == 1: b is odd.
    andi    t0, a1, 1

    # If b is odd, both operands are now odd.
    # Proceed to the main GCD loop.
    bne     t0, zero, .Lmain

    # Otherwise, divide b by 2.
    # b = b >> 1
    srli    a1, a1, 1

    # Repeat until b becomes odd.
    jal     zero, .Lmake_b_odd


.Lmain:
    # Step 4: Compare a and b and reduce the larger operand.
    #
    # Both a and b are positive odd integers.
    #
    # Case 1: b >= a
    #   gcd(a, b) = gcd(a, b-a)
    #   Reduce b.
    #
    # Case 2: b < a
    #   gcd(a, b) = gcd(a-b, b)
    #   Reduce a.
    #
    # Unlike the swap-based implementation,
    # this version directly reduces the larger operand.

    # bltu rs1, rs2, label:
    # Branch if rs1 < rs2 using unsigned comparison.
    #
    # a1 = b, a0 = a
    #
    # If b < a, jump to .Lreduce_a.
    # Otherwise, continue and reduce b.
    bltu    a1, a0, .Lreduce_a

    # Case 1: b >= a
    #
    # sub rd, rs1, rs2:
    # rd = rs1 - rs2
    #
    # b = b - a
    # Both operands are odd, so the difference is even.
    sub     a1, a1, a0

    # beq rs1, rs2, label:
    # Branch if rs1 == rs2.
    #
    # If b == 0, the remaining a is the GCD
    # after removing the shared factors of 2.
    #
    # This happens when a == b before subtraction.
    beq     a1, zero, .Ldone


.Lshift_b:
    # Step 5A: Remove factors of 2 from b after subtraction.
    #
    # b is guaranteed to be positive and even here,
    # because b was obtained by subtracting two odd
    # integers and the zero case was handled above.
    #
    # Therefore, at least one right shift is required.

    # b = b >> 1
    # Remove one factor of 2 from b.
    srli    a1, a1, 1

    # t0 = b & 1
    # Check the least significant bit of b.
    andi    t0, a1, 1

    # If t0 == 0, b is still even.
    # Continue removing factors of 2.
    beq     t0, zero, .Lshift_b

    # Now b is odd again.
    # Return to the main comparison and subtraction loop.
    jal     zero, .Lmain


.Lreduce_a:
    # Case 2: a > b
    #
    # Mathematical property:
    # gcd(a, b) = gcd(a-b, b)
    #
    # Reduce a instead of swapping the operands.

    # a = a - b
    #
    # Since a > b and both are odd,
    # the difference is positive and even.
    sub     a0, a0, a1


.Lshift_a:
    # Step 5B: Remove factors of 2 from a after subtraction.
    #
    # a is guaranteed to be positive and even here.
    # At least one right shift is required.

    # a = a >> 1
    # Remove one factor of 2 from a.
    srli    a0, a0, 1

    # t0 = a & 1
    # Check whether a is odd.
    andi    t0, a0, 1

    # If a is still even, continue shifting.
    beq     t0, zero, .Lshift_a

    # Now a is odd again.
    # Return to the main comparison and subtraction loop.
    jal     zero, .Lmain


.Ldone:
    # Step 6: Restore the shared factors of 2.
    #
    # The algorithm terminates when b becomes zero.
    # At this point, a contains the GCD of the reduced
    # operands, without the original shared factors of 2.
    #
    # Mathematical property:
    # gcd(original_a, original_b) = a * (2 ^ shift)
    #
    # sll rd, rs1, rs2:
    # Logical left shift by the amount in rs2.
    #
    # a0 = a0 << a2
    # Restore the common factors of 2.
    # The result is stored in a0.
    sll     a0, a0, a2


.Lreturn:
    # Return to the calling function.
    #
    # jalr rd, offset(rs1):
    # Jump to the address (rs1 + offset) with bit 0 cleared.
    # Write the return address into rd.
    #
    # ra contains the caller's return address.
    # rd = zero, so the link address is discarded.
    #
    # Equivalent to the RISC-V pseudoinstruction "ret".
    # The return value is already stored in a0.
    jalr    zero, 0(ra)


.Lreturn_b:
    # Special case: a == 0
    #
    # gcd(0, b) = b
    #
    # Copy b (a1) into a0, the return-value register.
    #
    # a0 = a1 + 0 = b
    addi    a0, a1, 0

    # Return to the caller.
    jalr    zero, 0(ra)

    # Mark the size of gcd_u32_asm for the assembler.
    # Function size = current address - function start address.
    .size gcd_u32_asm, .-gcd_u32_asm

