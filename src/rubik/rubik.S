# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
# a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.
#
# The cube is reduced to a permutation rank p (0..5039) and an orientation
# rank o (0..728); the solved cube is (0, 0). IDA* runs on an explicit stack
# instead of recursion, with h = max(pdb_p[p], pdb_o[o]) from tables.S.
#
# Two sorted tables from far.S, keyed by key = p << 10 | o (o < 1024, so no
# multiply), shorten the search:
#   far_tab   the 2,644 states at distance 11, entry = key << 4 | m. At the
#             root, such a state takes move m first and leaves distance 10.
#   near_tab  the 12,224 states at distance 0..5, entry = key << 3 | d. When
#             the pattern databases give h <= 5, a child's h becomes its exact
#             distance d, or 6 when the child is not listed.
#
# Registers kept across the search:
#   s0  perm_move          s5  bound (IDA* threshold)
#   s1  ori_move           s6  current stack frame
#   s2  pdb_p              s7  g, depth of the current frame
#   s3  pdb_o              s8  perm_row; reused as the solution length
#   s4  path               s9  ori_row
#   s10 1 when far_tab supplied path[0], else 0
#   s11 near_tab
#   a3  out (a1 is reused for the orientation rank)
#   a2  cap
#   a4..a7, t1, t5, t6: lower_bound arguments and scratch (a7 is its link)
#
# Stack frame, 12 bytes:
#   0 p    2 o    4 np    6 no    (.half: node, and its child in progress)
#   8 face    9 turn    10 last_face    (.byte; face 3 means exhausted)
#
# Move m = face * 3 + turn: m / 3 picks R, B or D and m % 3 picks a
# quarter turn, a half turn or a counter-clockwise turn.

    .section .rodata
names:                          # move m's name at names + 2m, ' '-padded
    .ascii "R R2R'B B2B'D D2D'"
weight:                         # (6 - i)!: Lehmer weight of position i
    .half 720, 120, 24, 6, 2, 1, 1
perm_row:                       # face * 5040 * 2: perm_move row offsets
    .word 0, 10080, 20160
ori_row:                        # face * 729 * 2: ori_move row offsets
    .word 0, 1458, 2916

    .bss
cubie:  .zero 8                 # cubie at positions 1..7, 0-based
twist:  .zero 8                 # twist at positions 1..7, 0..2

    .balign 4
stack:  .zero 132               # 11 frames: a pushed node has g <= 10
path:   .zero 12                # move ids 0..8, up to 11 moves

    .text

    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    addi sp, sp, -48
    sw s0, 0(sp)
    sw s1, 4(sp)
    sw s2, 8(sp)
    sw s3, 12(sp)
    sw s4, 16(sp)
    sw s5, 20(sp)
    sw s6, 24(sp)
    sw s7, 28(sp)
    sw s8, 32(sp)
    sw s9, 36(sp)
    sw s10, 40(sp)
    sw s11, 44(sp)

    mv   t0, a0              # read pointer
    mv   a3, a1
    la   t1, cubie              # write pointer
    li   t2, 7                  # count down
    li   t4, 0                  # cubies seen (bit mask)

parse_cubie:
    lbu  t3, 0(t0)
    addi t3, t3, -'1'           # '1'..'7' -> 0..6
    li   t5, 7
    bgeu t3, t5, illegal_input  # out of range, or the string ended early
    li   t5, 1
    sll  t5, t5, t3             # bit of this cubie
    and  t6, t4, t5
    bnez t6, illegal_input      # duplicate cubie
    or   t4, t4, t5
    sb   t3, 0(t1)
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, -1
    bnez t2, parse_cubie

    la   t1, twist              # t0 already points at input[7]
    li   t2, 7
    li   t4, 0                  # t4 now sums the twists

parse_twist:
    lbu  t3, 0(t0)
    addi t3, t3, -'1'           # '1'..'3' -> 0..2
    li   t5, 3
    bgeu t3, t5, illegal_input
    add  t4, t4, t3
    sb   t3, 0(t1)
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, -1
    bnez t2, parse_twist

    lbu  t3, 0(t0)              # input[14] must end the string
    bnez t3, illegal_input      # too long

sum_mod3:                       # twist sum mod 3 (sum <= 14)
    bltu t4, t5, sum_legal
    sub  t4, t4, t5
    j    sum_mod3
sum_legal:
    bnez t4, illegal_input      # twist sum not 0 mod 3

    # Permutation rank: every inversion p[j] < p[i], j > i, adds weight[i].
    # t0 &p[i]  t1 &weight[i]  t2 p[i]  t3 weight[i]  t4 &p[j]  t5 p[j]
    li   a0, 0
    la   t0, cubie
    la   t1, weight
    addi t6, t0, 7              # end

perm_i:
    lbu  t2, 0(t0)
    lhu  t3, 0(t1)
    addi t4, t0, 1              # j = i + 1

perm_j:
    bgeu t4, t6, perm_j_done
    lbu  t5, 0(t4)
    bgeu t5, t2, perm_skip      # not an inversion
    add  a0, a0, t3

perm_skip:
    addi t4, t4, 1
    j    perm_j

perm_j_done:
    addi t0, t0, 1
    addi t1, t1, 2              # .half
    bltu t0, t6, perm_i

    # Orientation rank: base 3 over twist[0..5]; rank * 3 = (rank << 1) + rank.
    li   a1, 0
    la   t0, twist
    addi t1, t0, 6              # twist[6] follows from the others

ori_i:
    lbu  t2, 0(t0)
    slli t3, a1, 1
    add  a1, a1, t3
    add  a1, a1, t2
    addi t0, t0, 1
    bltu t0, t1, ori_i

    la   s0, perm_move
    la   s1, ori_move
    la   s2, pdb_p
    la   s3, pdb_o
    la   s4, path
    la   s8, perm_row
    la   s9, ori_row
    li   s10, 0
    la   s11, near_tab

    or   t0, a0, a1
    beqz t0, solved_root        # already solved: empty solution

    slli a6, a0, 10
    or   a6, a6, a1             # key = p << 10 | o
    slli a6, a6, 4              # K = key << 4: far_tab entries hold m below
    la   a4, far_tab
    li   a5, 2644
    jal  a7, lower_bound
    lw   t0, 0(a4)
    srli t1, t0, 4              # key of the entry found
    srli t2, a6, 4              # key looked for
    bne  t1, t2, root_h         # not at distance 11: plain search
    andi t3, t0, 15             # m
    sb   t3, 0(s4)              # path[0] = m
    li   s10, 1
    addi s4, s4, 1              # the search writes from path + 1

    li   t4, 0                  # face
    li   t5, 3

fm_loop:                        # face = m / 3, turn = m % 3 by subtraction
    bltu t3, t5, fm_done
    addi t3, t3, -3
    addi t4, t4, 1
    j    fm_loop

fm_done:
    slli t6, t4, 2
    add  t0, s8, t6
    lw   t0, 0(t0)
    add  t0, s0, t0             # &perm_move[face][0]
    add  t1, s9, t6
    lw   t1, 0(t1)
    add  t1, s1, t1             # &ori_move[face][0]
    addi t3, t3, 1              # turn + 1 quarter turns

q_loop:
    slli t2, a0, 1
    add  t2, t0, t2
    lhu  a0, 0(t2)              # p = perm_move[face][p]
    slli t2, a1, 1
    add  t2, t1, t2
    lhu  a1, 0(t2)              # o = ori_move[face][o]
    addi t3, t3, -1
    bnez t3, q_loop

root_h:
    add  t0, s2, a0
    lbu  t1, 0(t0)              # pdb_p[p]
    add  t0, s3, a1
    lbu  t2, 0(t0)              # pdb_o[o]
    addi s5, t1, 0              # s5 = max(t1, t2)
    bgeu t1, t2, bound_loop
    addi s5, t2, 0

bound_loop:
    li   t0, 11
    bgtu s5, t0, illegal_input    # the diameter is 11
    la   s6, stack              # root frame
    li   s7, 0
    sh   a0, 0(s6)              # p
    sh   a1, 2(s6)              # o
    sh   a0, 4(s6)              # np = p
    sh   a1, 6(s6)              # no = o
    sb   zero, 8(s6)            # face
    sb   zero, 9(s6)            # turn
    li   t0, 3
    sb   t0, 10(s6)             # last_face = 3: none at the root

search_loop:
    lbu  t0, 8(s6)              # face
    li   t6, 3
    bne  t0, t6, not_popped
    beqz s7, next_bound         # root exhausted: this bound fails
    addi s6, s6, -12            # pop
    addi s7, s7, -1
    j    search_loop

not_popped:
    lbu  t1, 9(s6)              # turn
    beq  t1, t6, next_face      # three turns tried
    lbu  t5, 10(s6)
    beq  t0, t5, next_face      # same face as the last move: skip

    # Child: one more quarter turn of face on (np, no).
    slli t4, t0, 2
    add  t6, s8, t4
    lw   t6, 0(t6)              # face * 10080
    add  t6, s0, t6             # &perm_move[face][0]
    lhu  t2, 4(s6)
    slli t4, t2, 1
    add  t6, t6, t4
    lhu  t2, 0(t6)              # np = perm_move[face][np]
    sh   t2, 4(s6)

    slli t4, t0, 2
    add  t6, s9, t4
    lw   t6, 0(t6)              # face * 1458
    add  t6, s1, t6             # &ori_move[face][0]
    lhu  t3, 6(s6)
    slli t4, t3, 1
    add  t6, t6, t4
    lhu  t3, 0(t6)              # no = ori_move[face][no]
    sh   t3, 6(s6)

    slli t4, t0, 1              # path[g] = face * 3 + turn
    add  t4, t4, t0
    add  t4, t4, t1
    add  t6, s4, s7
    sb   t4, 0(t6)

    addi t1, t1, 1              # ++turn
    sb   t1, 9(s6)

    or   t4, t2, t3
    beqz t4, found              # child solved

    add  t6, s2, t2             # h = max(pdb_p[np], pdb_o[no])
    lbu  t4, 0(t6)
    add  t6, s3, t3
    lbu  t5, 0(t6)
    bgeu t4, t5, child_h_done
    addi t4, t5, 0

child_h_done:
    add  t1, t4, s7
    addi t1, t1, 1
    bgtu t1, s5, search_loop    # pdb alone prunes: no lookup needed
    li   t6, 6
    bgeu t4, t6, push_child     # h >= 6: the state is not in near_tab
    slli a6, t2, 10             # K = (np << 10 | no) << 3
    or   a6, a6, t3
    slli a6, a6, 3
    mv   a4, s11
    li   a5, 12224
    jal  a7, lower_bound
    lw   t6, 0(a4)
    srli t5, t6, 3
    srli t1, a6, 3
    li   t4, 6                  # not found: distance >= 6
    bne  t5, t1, near_done
    andi t4, t6, 7              # found: exact distance, low 3 bits

near_done:
    addi t1, s7, 1              # prune again with the new h
    add  t1, t1, t4
    bgtu t1, s5, search_loop

push_child:
    sh   t2, 12(s6)             # push: next frame at 12(s6)
    sh   t3, 14(s6)
    sh   t2, 16(s6)
    sh   t3, 18(s6)
    sb   zero, 20(s6)
    sb   zero, 21(s6)
    sb   t0, 22(s6)             # next.last_face = face
    addi s6, s6, 12
    addi s7, s7, 1
    j    search_loop

next_face:
    addi t0, t0, 1
    sb   t0, 8(s6)
    sb   zero, 9(s6)
    lhu  t2, 0(s6)              # (np, no) = (p, o)
    sh   t2, 4(s6)
    lhu  t3, 2(s6)
    sh   t3, 6(s6)
    j    search_loop

next_bound:
    addi s5, s5, 1
    j    bound_loop

illegal_input:
    li a0, -1

rs_return:
    lw s0, 0(sp)
    lw s1, 4(sp)
    lw s2, 8(sp)
    lw s3, 12(sp)
    lw s4, 16(sp)
    lw s5, 20(sp)
    lw s6, 24(sp)
    lw s7, 28(sp)
    lw s8, 32(sp)
    lw s9, 36(sp)
    lw s10, 40(sp)
    lw s11, 44(sp)
    addi sp, sp, 48    
    ret

solved_root:
    li s8, 0
    j write_out
    
found:
    addi s8, s7, 1

write_out:
    sub  s4, s4, s10            # back to path, far move included
    add  s8, s8, s10            # and count it
    la   t0, names
    mv   t1, s4
    add  t2, s4, s8             # end = path + len
    li   t3, 0                  # need: bytes, '\0' included
    li   t6, ' '

# Pass 1: each move takes its name plus one byte, a space or the final
# '\0', so need = sum of (name + 1). Nothing is written before the check.
need_loop:
    beq t1, t2, need_done      # top-tested: len may be 0
    lbu  t4, 0(t1)              # m
    slli t4, t4, 1              # 2m
    add  t4, t0, t4           # &names[2m]
    lbu  t5, 1(t4)           # second character of the name
    addi t3, t3, 2           # one character plus a separator
    beq t5, t6, need_next      # ' ' pad: one-character name
    addi t3, t3, 1

need_next:
    addi t1, t1, 1
    j    need_loop

need_done:
    bnez t3, need_ok            # need != 0 means len != 0
    li   t3, 1                  # len == 0: only the '\0'

need_ok:
    bltu a2, t3, too_small      # cap < need, unsigned: cap is size_t

# Pass 2: write. a4 is the out cursor, t1 the path cursor.
    mv   a4, a3                 # out cursor starts at out
    mv   t1, s4

put_loop:
    beq t1, t2, put_end
    beq t1, s4, put_name        # no space before the first move
    sb   t6, 0(a4)              # separator
    addi a4, a4, 1  

put_name:
    lbu  t4, 0(t1)
    slli t4, t4, 1
    add  t4, t0, t4             # &names[2m]
    lbu  t5, 0(t4)
    sb   t5, 0(a4)              # first character
    addi a4, a4, 1
    lbu  t5, 1(t4)
    beq  t5, t6, put_next       # one-character name
    sb   t5, 0(a4)
    addi a4, a4, 1

put_next:
    addi t1, t1, 1
    j    put_loop

put_end:
    sb   x0, 0(a4)              # terminator
    mv   a0, s8                 # return len
    j    rs_return

too_small:
    beqz a2, too_small_ret      # cap == 0: out may not be written
    sb   zero, 0(a3)            # out[0] = '\0'

too_small_ret:
    li   a0, -2
    j    rs_return

# lower_bound: first entry >= a6 in the ascending .word array a4[0..a5).
# In: a4 = first, a5 = n, a6 = K, a7 = return address.
# Out: a4 = &entry (may be one past the end). Clobbers a5, t1, t5, t6.
lower_bound:
    beqz a5, lb_done
    srli t1, a5, 1              # half
    slli t5, t1, 2
    add  t5, a4, t5             # &first[half]
    lw   t6, 0(t5)
    bgeu t6, a6, lb_left        # entry >= K: answer is at or left of mid
    addi a4, t5, 4              # first = mid + 1
    addi t1, t1, 1              # n -= half + 1
    sub  a5, a5, t1
    j    lower_bound

lb_left:
    mv   a5, t1                 # n = half
    j    lower_bound

lb_done:
    jr   a7                     # return through a7

    .size   rubik_solve_asm, .-rubik_solve_asm
