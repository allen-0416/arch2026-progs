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

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    addi t0, x0, 0    
    beqz a1, end

loop:
    and t1, a0, a1
    xor a0, a0, a1
    slli a1, t1, 1

    addi t0, t0 ,1
    bnez a1, loop

end:
    sw t0 ,0(a2)
    ret

    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub a0, a0, a1
    ret

    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and t0, a0, a1
    xor t1, a0, a1
    srli t1, t1, 1
    add a0, t0, t1
    ret

    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    addi t6, a0, 0
    addi t5, a1, 0
    addi t0, a0, 0
    srai t1, a0, 31
    addi t2, x0, 0
    addi t3, x0, 0
    
    beqz a1, round

mul_loop:
    andi t4, a1, 0x0001
    beqz t4, mul_shift
    add t2, t2, t0
    sltu t4, t2, t0
    add t3, t3, t1
    add t3, t3, t4

mul_shift:
    srli t4, t0, 31
    slli t1, t1, 1
    or t1, t1, t4
    slli t0, t0, 1
    srli a1, a1, 1
    bnez a1, mul_loop

round:
    bgez t5, add_round
    sub t3, t3, t6

add_round:
    li t4, 0x80000
    add t2, t2, t4
    sltu t4, t2, t4
    add t3, t3, t4
    
    srli t2, t2, 20
    slli t3, t3, 12
    or a0, t2, t3
    ret

    .size   q_mul_asm, .-q_mul_asm
