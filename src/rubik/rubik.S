# Rubik HW2 candidate: HW1 coordinate IDA* with the HW2 calling convention.
# Requires rubik_tables.S and rubik_tables.bin generated from HW1 tables.
# int rubik_solve_asm(const char *state, char *out, size_t cap)
    .option nopic
    .text
    .globl rubik_solve_asm
    .type rubik_solve_asm, @function
    .align 2
rubik_solve_asm:
    addi sp,sp,-96
    sw ra,92(sp)
    sw s0,88(sp)
    sw s1,84(sp)
    sw s2,80(sp)
    sw s3,76(sp)
    mv s1,a1                    # Output buffer.
    mv s2,a2                    # Output capacity.
    mv a1,sp                    # Decoded state at sp+0.
    call parse_target
    beqz a0,.Lhw2_invalid
    mv a0,sp
    addi a1,sp,16
    call find_depth11
    bnez a0,.Lhw2_deep
    mv a0,sp
    addi a1,sp,16              # Search path at sp+16.
    call ida_star
    blt a0,zero,.Lhw2_invalid
    mv s3,a0                    # Optimal number of moves.
    j .Lhw2_format_start
.Lhw2_deep:
    li s3,11                   # The offline table contains exact distance-11 states.
.Lhw2_format_start:
    li t0,0
    addi t1,sp,32              # Temporary output at sp+32.
    la t6,.Lhw2_move_names
.Lhw2_format:
    bge t0,s3,.Lhw2_format_done
    beqz t0,.Lhw2_first_move
    li t2,32
    sb t2,0(t1)
    addi t1,t1,1
.Lhw2_first_move:
    addi t2,sp,16
    add t2,t2,t0
    lbu t2,0(t2)
    slli t2,t2,2
    add t2,t6,t2
    lw t2,0(t2)
.Lhw2_copy_name:
    lbu t3,0(t2)
    beqz t3,.Lhw2_name_done
    sb t3,0(t1)
    addi t1,t1,1
    addi t2,t2,1
    j .Lhw2_copy_name
.Lhw2_name_done:
    addi t0,t0,1
    j .Lhw2_format
.Lhw2_format_done:
    sb zero,0(t1)
    addi t2,sp,32
    sub t3,t1,t2               # Byte count excluding the NUL.
    bgeu t3,s2,.Lhw2_small
    li t0,0
.Lhw2_copy_output:
    lbu t4,0(t2)
    sb t4,0(s1)
    beqz t4,.Lhw2_success
    addi t2,t2,1
    addi s1,s1,1
    j .Lhw2_copy_output
.Lhw2_success:
    mv a0,s3
    j .Lhw2_return
.Lhw2_small:
    beqz s2,.Lhw2_small_return
    sb zero,0(s1)
.Lhw2_small_return:
    li a0,-2
    j .Lhw2_return
.Lhw2_invalid:
    li a0,-1                   # Invalid state leaves out untouched.
.Lhw2_return:
    lw ra,92(sp)
    lw s0,88(sp)
    lw s1,84(sp)
    lw s2,80(sp)
    lw s3,76(sp)
    addi sp,sp,96
    ret
    .size rubik_solve_asm, .-rubik_solve_asm

# Return one and fill the path for a distance-11 state; otherwise return zero.
# a0 points to the decoded 14-byte state, and a1 points to the path buffer.
    .align 2
    .type find_depth11, @function
find_depth11:
    li t0,0                    # Permutation index.
    li t2,0
    la a3,.LANCHOR0
    addi a3,a3,60
.Ldeep_perm_outer:
    li t3,6
    beq t2,t3,.Ldeep_ori_start
    add t3,a0,t2
    lbu t4,0(t3)
    slli t3,t2,1
    add t3,a3,t3
    lhu a4,0(t3)
    addi t5,t2,1
.Ldeep_perm_inner:
    li t3,7
    beq t5,t3,.Ldeep_perm_next
    add t3,a0,t5
    lbu t6,0(t3)
    bgeu t6,t4,.Ldeep_perm_skip
    add t0,t0,a4
.Ldeep_perm_skip:
    addi t5,t5,1
    j .Ldeep_perm_inner
.Ldeep_perm_next:
    addi t2,t2,1
    j .Ldeep_perm_outer
.Ldeep_ori_start:
    li t1,0                    # Orientation index.
    li t2,5
.Ldeep_ori_loop:
    slli t3,t1,1
    add t1,t1,t3
    addi t3,t2,7
    add t3,a0,t3
    lbu t4,0(t3)
    add t1,t1,t4
    addi t2,t2,-1
    bge t2,zero,.Ldeep_ori_loop
    # Combine the two coordinates into a sorted 22-bit state rank.
    slli t3,t0,9
    slli t4,t0,8
    add t3,t3,t4
    slli t4,t0,5
    sub t3,t3,t4
    slli t4,t0,3
    sub t3,t3,t4
    add t3,t3,t0
    add t0,t3,t1

    la t1,rubik_depth11_table
    li t2,0
    li t3,2644
.Ldeep_binary:
    bgeu t2,t3,.Ldeep_miss
    add t4,t2,t3
    srli t4,t4,1
    slli t5,t4,3
    add t5,t1,t5
    lbu t6,0(t5)
    lbu a3,1(t5)
    slli a3,a3,8
    or t6,t6,a3
    lbu a3,2(t5)
    slli a3,a3,16
    or t6,t6,a3
    beq t6,t0,.Ldeep_found
    bltu t6,t0,.Ldeep_upper
    mv t3,t4
    j .Ldeep_binary
.Ldeep_upper:
    addi t2,t4,1
    j .Ldeep_binary
.Ldeep_miss:
    li a0,0
    ret

.Ldeep_found:
    # Read the little-endian 40-bit base-9 path from the packed record.
    lbu t2,3(t5)
    lbu t3,4(t5)
    slli t3,t3,8
    or t2,t2,t3
    lbu t3,5(t5)
    slli t3,t3,16
    or t2,t2,t3
    lbu t3,6(t5)
    slli t3,t3,24
    or t2,t2,t3
    lbu t3,7(t5)
    li a3,0                    # Number of decoded moves.
.Ldeep_digit:
    # Long division by nine produces the next move as the remainder.
    li t4,0                    # Remainder.
    li t5,40                   # Number of bits in the packed value.
    li t6,0                    # Low word of the quotient.
    li a5,0                    # High word of the quotient.
.Ldeep_bit:
    srli a6,t3,7
    andi a6,a6,1
    slli t4,t4,1
    or t4,t4,a6
    srli a6,t2,31
    slli t3,t3,1
    or t3,t3,a6
    slli t2,t2,1
    srli a6,t6,31
    slli a5,a5,1
    or a5,a5,a6
    slli t6,t6,1
    li a6,9
    bltu t4,a6,.Ldeep_no_sub
    addi t4,t4,-9
    ori t6,t6,1
.Ldeep_no_sub:
    addi t5,t5,-1
    bnez t5,.Ldeep_bit
    sb t4,0(a1)
    addi a1,a1,1
    mv t2,t6
    mv t3,a5
    addi a3,a3,1
    li a6,11
    bltu a3,a6,.Ldeep_digit
    li a0,1
    ret
    .size find_depth11, .-find_depth11

# Leaf parser: a0=NUL-terminated 14 digits, a1=14-byte state.
    .align 2
    .type parse_target, @function
parse_target:
    mv t0,a0
    li t1,14
.Linput_length:
    lbu t2,0(t0)
    beq t2,zero,.Linput_bad
    addi t0,t0,1
    addi t1,t1,-1
    bne t1,zero,.Linput_length
    lbu t2,0(t0)
    bne t2,zero,.Linput_bad
    li t0,0
    li t1,0
    li t2,0
.Linput_digits:
    lbu t3,0(a0)
    addi t3,t3,-49
    li t4,7
    bgeu t3,t4,.Linput_bad
    li t4,1
    sll t4,t4,t3
    and t5,t1,t4
    bne t5,zero,.Linput_bad
    or t1,t1,t4
    sb t3,0(a1)
    lbu t3,7(a0)
    addi t3,t3,-49
    li t4,3
    bgeu t3,t4,.Linput_bad
    sb t3,7(a1)
    add t2,t2,t3
    addi a0,a0,1
    addi a1,a1,1
    addi t0,t0,1
    li t4,7
    bne t0,t4,.Linput_digits
    li t4,3
.Linput_mod3:
    bltu t2,t4,.Linput_sum
    addi t2,t2,-3
    j .Linput_mod3
.Linput_sum:
    seqz a0,t2
    ret
.Linput_bad:
    li a0,0
    ret
    .size parse_target, .-parse_target

	.align 2
	.type evaluate_heuristic, @function
evaluate_heuristic:
	lui	t3,%hi(.LANCHOR0)
	addi	t3,t3,%lo(.LANCHOR0)
	addi	t4,t3,60
	li	t1,1
	li	a3,0
	li	a1,7
.L56:
	add	a5,a0,t1
	lbu	a7,-1(a5)
	lhu	a6,0(t4)
	mv	a4,t1
.L55:
	add	a5,a0,a4
	lbu	a5,0(a5)
	addi	a4,a4,1
	andi	a2,a4,0xff
	sltu	a5,a5,a7
	neg	a5,a5
	and	a5,a6,a5
	add	a3,a3,a5
	bne	a2,a1,.L55
	addi	t1,t1,1
	addi	t4,t4,2
	bne	t1,a1,.L56
	addi	a0,a0,7
	mv	a1,t3
	addi	t1,t3,12
	li	a6,0
.L61:
	lbu	a4,0(a0)
	lhu	a7,0(a1)
	li	a2,0
	addi	a5,a4,-1
	seqz	a5,a5
	neg	a5,a5
	addi	a4,a4,-2
	addi	a1,a1,2
	and	a5,a7,a5
	bne	a4,zero,.L58
	slli	a2,a7,1
.L58:
	or	a2,a2,a5
	add	a6,a6,a2
	addi	a0,a0,1
	bne	a1,t1,.L61
	slli	a6,a6,16
	slli	a3,a3,16
	srli	a6,a6,16
	srli	a3,a3,16
	lui	a5,%hi(pdb_permutation_packed)
	srli	a2,a6,1
	srli	a4,a3,1
	addi	a5,a5,%lo(pdb_permutation_packed)
	add	a4,a4,a5
	add	t3,t3,a2
	lbu	a5,76(t3)
	lbu	a4,0(a4)
	slli	a6,a6,2
	slli	a3,a3,2
	andi	a3,a3,4
	andi	a6,a6,4
	sra	a5,a5,a6
	sra	a4,a4,a3
	andi	a5,a5,15
	andi	a3,a4,15
	mv	a0,a5
	bgeu	a5,a3,.L62
	mv	a0,a3
.L62:
	andi	a0,a0,15
	ret
	.size	evaluate_heuristic, .-evaluate_heuristic
	.align 2
	.type ida_star, @function
ida_star:
	# HAND-OPT: s9 = search_stack + 6*g throughout DFS.
	# No extra data or stack allocation; offset 20(sp) was unused.
	addi	sp,sp,-64
	sw	s0,56(sp)
	sw	ra,60(sp)
	sw	s4,40(sp)
	sw	a1,12(sp)
	mv	s0,a0
	call	evaluate_heuristic
	li	t0,11
	bgtu	a0,t0,.L68
	lw	a1,12(sp)
	lui	a6,%hi(.LANCHOR0)
	lui	a2,%hi(.LANCHOR1)
	lui	t6,%hi(.LANCHOR0+12)
	lui	t5,%hi(permutation_transition)
	lui	t4,%hi(orientation_transition)
	lui	t3,%hi(pdb_permutation_packed)
	mv	t1,a0
	sw	s1,52(sp)
	sw	s2,48(sp)
	sw	s3,44(sp)
	sw	s5,36(sp)
	sw	s6,32(sp)
	sw	s7,28(sp)
	sw	s8,24(sp)
	sw	s9,20(sp)	# HAND: save persistent frame pointer
	addi	a6,a6,%lo(.LANCHOR0)
	addi	a2,a2,%lo(.LANCHOR1)
	addi	t6,t6,%lo(.LANCHOR0+12)
	addi	t5,t5,%lo(permutation_transition)
	addi	t4,t4,%lo(orientation_transition)
	addi	t3,t3,%lo(pdb_permutation_packed)
	lui	a0,%hi(.LANCHOR0+60)
	li	a7,7
	li	t2,9
.L85:
	mv	s9,a2	# HAND: reset frame pointer for each IDA* bound
	addi	s5,a0,%lo(.LANCHOR0+60)
	li	s4,1
	li	a3,0
.L72:
	add	a5,s0,s4
	lbu	s3,-1(a5)
	lhu	s2,0(s5)
	mv	a4,s4
.L71:
	add	a5,s0,a4
	lbu	a5,0(a5)
	addi	a4,a4,1
	andi	s1,a4,0xff
	sltu	a5,a5,s3
	neg	a5,a5
	and	a5,s2,a5
	add	a3,a3,a5
	bne	s1,a7,.L71
	addi	s4,s4,1
	addi	s5,s5,2
	bne	s4,a7,.L72
	sh	a3,0(a2)
	mv	s1,a6
	addi	s2,s0,7
	li	s4,0
.L77:
	lbu	a4,0(s2)
	lhu	s3,0(s1)
	li	a3,0
	addi	a5,a4,-1
	seqz	a5,a5
	neg	a5,a5
	addi	a4,a4,-2
	addi	s1,s1,2
	and	a5,s3,a5
	bne	a4,zero,.L74
	slli	a3,s3,1
.L74:
	or	a3,a3,a5
	add	s4,s4,a3
	addi	s2,s2,1
	bne	s1,t6,.L77
	sh	s4,2(a2)
	sh	t2,4(a2)
	li	s3,0
	li	a5,0
	li	a4,0
	andi	s2,t1,0xff
	j	.L78
.L96:
	slli	a3,s1,3
	add	a3,a3,s1
	add	a3,a6,a3
	add	a3,a3,s3
	lbu	s4,456(a3)
	lhu	s7,0(a4)
	lhu	s6,2(a4)
	slli	s5,s4,2
	add	s5,s5,s4
	slli	a3,s5,4
	add	a3,a3,s4
	slli	s1,s5,6
	sub	s1,s1,s5
	slli	s5,a3,3
	add	a3,a3,s5
	slli	s1,s1,4
	add	s1,s1,s7
	add	a3,a3,s6
	addi	s5,a5,1
	slli	s1,s1,1
	slli	a3,a3,1
	add	s1,t5,s1
	add	a3,t4,a3
	lhu	s7,0(s1)
	lhu	s1,0(a3)
	addi	s3,s3,1
	sb	s3,5(a4)
	add	a5,a1,a5
	addi	s9,s9,6	# HAND: push one six-byte frame
	mv	a4,s9
	sb	s4,0(a5)
	sb	s4,4(a4)
	sb	zero,5(a4)
	andi	a5,s5,0xff
	sh	s7,0(a4)
	sh	s1,2(a4)
.L83:
	lbu	s3,5(s9)	# HAND: current successor cursor
.L78:
	mv	s4,a5
	bne	s3,zero,.L79
	lhu	s7,0(s9)
	lhu	s6,2(s9)
	srli	s1,s7,1
	srli	a3,s6,1
	add	s1,s1,t3
	add	a3,a6,a3
	lbu	s5,0(s1)
	lbu	a3,76(a3)
	slli	s8,s6,2
	slli	s1,s7,2
	andi	s8,s8,4
	andi	s1,s1,4
	sra	a3,a3,s8
	sra	s5,s5,s1
	andi	a3,a3,15
	andi	s8,s5,15
	andi	s1,a3,0xff
	bgeu	a3,s8,.L81
	andi	s1,s8,0xff
.L81:
	add	s1,s1,a5
	bgt	s1,t1,.L80
	or	s7,s7,s6
	beq	s7,zero,.L95
	sltu	a3,a5,s2
	addi	s1,a5,-11
	seqz	a3,a3
	seqz	s1,s1
	or	a3,a3,s1
	bne	a3,zero,.L80
.L79:
	mv	a4,s9	# HAND: parent frame for successor expansion
	lbu	s1,4(a4)
	add	a3,a6,s1
	lbu	a3,444(a3)
	bne	a3,s3,.L96
.L80:
	beq	a5,zero,.L84
	addi	a5,a5,-1
	addi	s9,s9,-6	# HAND: pop; root case branches before this
	andi	a5,a5,0xff
	j	.L83
.L84:
	addi	t1,t1,1
	andi	a5,t1,0xff
	bleu	a5,t0,.L85
	lw	s1,52(sp)
	lw	s2,48(sp)
	lw	s3,44(sp)
	lw	s5,36(sp)
	lw	s6,32(sp)
	lw	s7,28(sp)
	lw	s8,24(sp)
	lw	s9,20(sp)	# HAND: restore caller s9
.L68:
	lw	ra,60(sp)
	lw	s0,56(sp)
	li	s4,-1
	mv	a0,s4
	lw	s4,40(sp)
	addi	sp,sp,64
	jr	ra
.L95:
	lw	ra,60(sp)
	lw	s0,56(sp)
	lw	s1,52(sp)
	lw	s2,48(sp)
	lw	s3,44(sp)
	lw	s5,36(sp)
	lw	s6,32(sp)
	lw	s7,28(sp)
	lw	s8,24(sp)
	lw	s9,20(sp)	# HAND: restore caller s9
	mv	a0,s4
	lw	s4,40(sp)
	addi	sp,sp,64
	jr	ra
	.size	ida_star, .-ida_star

    .section .rodata
    .balign 4
.LANCHOR0:
    .half 1,3,9,27,81,243
    .zero 48                    # Keep the HW1 factorial offset at 60.
    .half 720,120,24,6,2,1,1
    .zero 2                     # Keep the orientation PDB offset at 76.
    .byte 80,85,83,85,67,68,68,85,85,68,100,84,84,99,85,68
    .byte 67,68,68,68,101,85,84,84,66,100,85,101,69,83,68,83
    .byte 84,86,69,84,68,84,82,84,69,68,52,101,69,68,83,84
    .byte 68,84,68,68,68,68,52,68,85,82,53,84,68,84,84,68
    .byte 85,53,83,84,84,69,69,81,69,85,85,52,84,85,84,84
    .byte 83,68,84,85,84,84,68,85,85,85,52,68,68,85,84,84
    .byte 68,83,69,85,101,85,69,86,69,51,85,69,67,68,69,83
    .byte 85,68,68,86,84,67,85,69,85,83,83,51,82,85,67,85
    .byte 69,69,84,85,83,68,69,67,68,68,69,69,85,69,85,86
    .byte 84,84,85,69,70,68,85,85,69,85,86,100,69,70,85,52
    .byte 101,85,68,85,84,68,83,69,70,86,85,85,85,68,86,53
    .byte 85,69,84,37,53,85,69,68,85,69,53,68,85,69,69,85
    .byte 84,67,85,86,69,84,69,86,68,85,100,69,84,51,68,68
    .byte 68,69,86,69,68,67,84,85,81,68,100,84,83,53,69,85
    .byte 84,52,84,83,69,84,82,36,84,82,83,84,69,69,69,85
    .byte 85,68,84,85,83,85,35,99,84,67,68,83,84,68,67,85
    .byte 68,83,84,85,85,82,85,53,52,85,86,84,68,86,52,84
    .byte 84,68,68,66,84,84,85,84,86,83,85,84,85,68,53,84
    .byte 68,84,85,67,84,85,86,85,68,69,84,69,36,68,85,69
    .byte 85,84,68,86,84,84,53,68,53,70,70,51,69,85,85,83
    .byte 101,70,85,84,83,84,68,69,69,68,86,69,84,69,85,85
    .byte 102,84,69,53,86,69,84,68,101,84,84,85,69,101,85,84
    .byte 85,84,84,84,83,85,84,67,68,84,84,69,245
    .zero 3                     # Keep successor_count at offset 444.
    .byte 6,6,6,6,6,6,6,6,6,9
    .zero 2                     # Keep valid_next_moves at offset 456.
    .byte 3,4,5,6,7,8,0,0,0,3,4,5,6,7,8,0,0,0,3,4,5,6,7,8,0,0,0
    .byte 0,1,2,6,7,8,0,0,0,0,1,2,6,7,8,0,0,0,0,1,2,6,7,8,0,0,0
    .byte 0,1,2,3,4,5,0,0,0,0,1,2,3,4,5,0,0,0,0,1,2,3,4,5,0,0,0
    .byte 0,1,2,3,4,5,6,7,8
    .balign 4
.Lhw2_move_names:
    .word .Lmove_r,.Lmove_r2,.Lmove_ri,.Lmove_b,.Lmove_b2,.Lmove_bi
    .word .Lmove_d,.Lmove_d2,.Lmove_di
.Lmove_r:  .asciz "R"
.Lmove_r2: .asciz "R2"
.Lmove_ri: .asciz "R'"
.Lmove_b:  .asciz "B"
.Lmove_b2: .asciz "B2"
.Lmove_bi: .asciz "B'"
.Lmove_d:  .asciz "D"
.Lmove_d2: .asciz "D2"
.Lmove_di: .asciz "D'"
    .section .bss
    .balign 4
.LANCHOR1:
    .zero 72                    # Twelve six-byte search frames.
    .section .note.GNU-stack,"",@progbits
