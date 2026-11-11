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
    li t0, 0x7F800000
    and t1, a0, t0
    beq t0, t1, done
    
    srli t1, a0, 16
    andi t1, t1, 0x0001
    add a0, a0, t1
    li t2, 0x7FFF
    add a0, a0, t2

done:
    srli a0, a0, 16
    ret

    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    xor t0, a0, a1
    srli t0, t0, 15
    andi t0, t0, 0x1
    slli t0, t0, 15
    srli t1, a0, 7
    srli t2, a1, 7
    andi t1, t1, 0xFF
    andi t2, t2, 0xFF
    li t6, 0xFF
    beq t1, t6, a_special
    beq t2, t6, b_specail

    slli t6, a0, 17
    beqz t6, ret_zero
    slli t6, a1, 17
    beqz t6, ret_zero

    andi t3, a0, 0x7F
    beqz t1, a_denorm
    ori t3, t3, 0x80

a_ready:
    andi t4, a1, 0x7F
    beqz t2, b_denorm
    ori t4, t4, 0x80

b_ready:
    li t5, 0

mul_loop:
    andi t6, t4, 0x0001
    beqz t6, shift_left
    add t5, t5, t3
    
shift_left:    
    slli t3, t3, 1
    srli t4, t4, 1
    bnez t4, mul_loop
    add t1, t1, t2
    addi t1, t1, -127
    srli t4, t5, 15
    bnez t4, shift_eight
    srli t5, t5, 7
    j mul_conti

shift_eight:
    srli t5, t5, 8
    addi t1, t1, 1

mul_conti:
    andi t5, t5, 0x7F
    li t6, 0xFF
    bge t1, t6, ret_inf
    li t6, -6
    blt t1, t6, ret_zero
    blez t1, make_denorm
    slli t1, t1, 7
    add a0, t0, t1
    add a0, a0, t5 
    ret

a_denorm:
    li t1, 1

a_norm_loop:
    slli t3, t3, 1
    addi t1, t1, -1
    srli t6, t3, 7
    beqz t6, a_norm_loop
    j a_ready

b_denorm:
    li t2, 1

b_norm_loop:
    slli t4, t4, 1
    addi t2, t2, -1
    srli t6, t4, 7
    beqz t6, b_norm_loop
    j b_ready

make_denorm:
    li t6, 1
    sub t6, t6, t1
    srl t5, t5, t6
    or a0, t0, t5
    ret

a_special:
    andi t6, a0, 0x007F
    bnez t6, ret_a
    slli t6, a1, 17
    beqz t6, ret_nan
    j ret_inf

b_specail:
    andi t6, a1, 0x007F
    bnez t6, ret_b
    slli t6, a0, 17
    beqz t6, ret_nan
    j ret_inf

ret_a:
    ret

ret_b:
    mv a0, a1
    ret

ret_nan:
    li a0, 0x7FC0
    ret

ret_inf:
    li t6, 0x7F80
    or a0, t0, t6
    ret

ret_zero:
    mv a0, t0
    ret

    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli t1, a0, 7
    andi t1, t1, 0xFF
    andi t2, a0, 0x007F
    li t3, 0xFF
    beq t1, t3, sq_special
    slli t3, a0, 17
    beqz t3, sq_zero
    srli t3, a0, 15
    bnez t3, sq_neg
    beqz t1, sq_zero

    ori t3, t2, 0x80
    andi t4, t1, 1
    bnez t4, sqrt_conti
    slli t3, t3, 1

sqrt_conti:     
    addi t1, t1, 127
    srai t1, t1, 1
    slli t3, t3, 7
    ori t3, t3, 127
    li t4, 0
    li t5, 0x4000

sq_loop:
    add t6, t4, t5
    bltu t3, t6, sq_skip
    sub t3, t3, t6
    srai t4, t4, 1
    add t4, t4, t5
    j sq_next

sq_skip:
    srli t4, t4, 1

sq_next:
    srli t5, t5, 2
    bnez t5, sq_loop
    slli a0, t1, 7
    andi t4, t4, 0x7F
    or a0, a0, t4
    ret

sq_special:
    bnez t2, sq_nan
    srli t4, a0, 15
    beqz t4, sq_inf
    li a0, 0x7FC0
    ret

sq_nan:
    ret

sq_neg:
    li a0, 0x7FC0
    ret

sq_inf:
    ret

sq_zero:
    li a0, 0
    ret

    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
