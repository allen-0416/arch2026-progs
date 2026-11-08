#include "rubik.h"

enum { CUBIES = 7, PERMUTATIONS = 5040, ORIENTATIONS = 729, MOVES = 9 };

/* Move m = face * 3 + turn: turn + 1 quarter turns of face R, B or D. */
static const char *const move_names[MOVES] = {"R",  "R2", "R'", "B", "B2",
                                              "B'", "D",  "D2", "D'"};

/* A quarter turn of face f puts cubie source[f][i] at position i and adds
 * twist[f][i] to its orientation, mod 3.
 */
static const uint8_t source[3][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};

static const uint8_t twist[3][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

/* ---- Ranks ---- */

/* (6 - i)!, the Lehmer weight of position i. */
static const uint16_t weight[CUBIES] = {720, 120, 24, 6, 2, 1, 1};

static uint16_t rank_perm(const uint8_t p[CUBIES])
{
    uint16_t rank = 0;
    /* Each inversion p[j] < p[i] with j > i adds weight[i]. */
    for (uint8_t i = 0; i < CUBIES; ++i) {
        for (uint8_t j = (uint8_t) (i + 1U); j < CUBIES; ++j) {
            if (p[j] < p[i]) {
                rank += weight[i];
            }
        }
    }

    return rank;
}

static uint16_t rank_ori(const uint8_t o[CUBIES])
{
    uint16_t rank = 0;
    /* Base 3 over o[0..5]; o[6] follows. rank * 3 = (rank << 1) + rank. */
    for (uint8_t i = 0; i < 6; ++i) {
        rank = (rank << 1) + rank + o[i];
    }

    return rank;
}

/* ---- Quarter-turn tables ---- */

/* Rank after one quarter turn of face f: perm_move[f][r], ori_move[f][r]. */
static uint16_t perm_move[3][PERMUTATIONS];
static uint16_t ori_move[3][ORIENTATIONS];

/* Next permutation in lexicographic order, which is the next rank; returns 0
 * after the last one.
 */
static int next_perm(uint8_t p[CUBIES])
{
    int i = CUBIES - 2, j = CUBIES - 1;
    while (i >= 0 && p[i] > p[i + 1]) {
        i--;
    }

    if (i < 0) {
        return 0;
    }

    while (p[j] < p[i]) {
        j--;
    }

    uint8_t temp = p[i];
    p[i] = p[j];
    p[j] = temp;

    for (int a = i + 1, b = CUBIES - 1; a < b; a++, b--) {
        temp = p[a];
        p[a] = p[b];
        p[b] = temp;
    }

    return 1;
}

/* Base-3 odometer over o[0..5]; o[6] keeps the twist sum 0 mod 3. */
static void next_ori(uint8_t o[CUBIES])
{
    int i = 5, sum = 0;
    while (i >= 0 && o[i] == 2) {
        o[i] = 0;
        i--;
    }

    if (i >= 0) {
        o[i] += 1;
    }

    for (int j = 0; j < 6; j++) {
        sum += o[j];
    }

    while (sum >= 3) {
        sum -= 3;
    }

    o[6] = sum ? 3 - sum : 0;
}

/* Walk the states in rank order, so no unranking is needed. */
static void build_move_tables(void)
{
    uint8_t p[CUBIES] = {0, 1, 2, 3, 4, 5, 6}, o[CUBIES] = {0};
    uint8_t next[CUBIES];
    uint16_t rank = 0;

    do {
        for (uint8_t face = 0; face < 3; ++face) {
            for (uint8_t i = 0; i < CUBIES; ++i)
                next[i] = p[source[face][i]];
            perm_move[face][rank] = rank_perm(next);
        }
        ++rank;
    } while (next_perm(p));

    for (rank = 0; rank < ORIENTATIONS; ++rank) {
        for (uint8_t face = 0; face < 3; ++face) {
            for (uint8_t i = 0; i < CUBIES; ++i) {
                uint8_t t = (uint8_t) (o[source[face][i]] + twist[face][i]);
                next[i] = (t >= 3 ? t - 3U : t);
            }
            ori_move[face][rank] = rank_ori(next);
        }
        next_ori(o);
    }
}

/* ---- Distance tables ---- */

/* Moves needed to solve the permutation alone (pdb_p) or the orientation
 * alone (pdb_o): lower bounds on the real distance.
 */
static uint8_t pdb_p[PERMUTATIONS], pdb_o[ORIENTATIONS];
static int tables_ready;

/* Rank of x after one quarter turn of face; is_perm picks the table. */
static uint16_t turn_once(int is_perm, uint8_t face, uint16_t x)
{
    return is_perm ? perm_move[face][x] : ori_move[face][x];
}

/* BFS without a queue: pass d expands every entry at depth d, until a pass
 * finds nothing new.
 */
static void build_pdb_scan(uint8_t pdb[], uint16_t n, int is_perm)
{
    for (uint16_t x = 0; x < n; ++x) {
        pdb[x] = UINT8_MAX;
    }

    pdb[0] = 0;
    uint8_t depth = 0;
    int visit = 1;

    while (visit) {
        visit = 0;
        for (uint16_t x = 0; x < n; ++x) {
            if (pdb[x] != depth) {
                continue;
            }
            for (uint8_t face = 0; face < 3; ++face) {
                uint16_t y = x;
                for (uint8_t turn = 0; turn < 3; ++turn) {
                    y = turn_once(is_perm, face, y);
                    if (pdb[y] == UINT8_MAX) {
                        pdb[y] = depth + 1;
                        visit = 1;
                    }
                }
            }
        }
        depth++;
    }
}

static void init_tables(void)
{
    build_move_tables();
    build_pdb_scan(pdb_p, PERMUTATIONS, 1);
    build_pdb_scan(pdb_o, ORIENTATIONS, 0);
}

/* ---- IDA* search ---- */

static uint8_t heuristic(uint16_t p, uint16_t o)
{
    uint8_t h1 = pdb_p[p];
    uint8_t h2 = pdb_o[o];
    return (h1 > h2 ? h1 : h2);
}

/* One level of the explicit search stack (12 bytes). */
typedef struct {
    uint16_t p, o;      /* this node */
    uint16_t np, no;    /* after `turn` quarter turns of `face` */
    uint8_t face, turn; /* the next child to try */
    uint8_t last_face;  /* skip moves of the same face */
} frame_t;

/* A pushed node has h >= 1 and g + h <= bound <= 11, so g <= 10. */
static frame_t stack[11];

/* Depth-first search within bound; returns the solution length, or -1. */
static int search(uint16_t p, uint16_t o, uint8_t bound, uint8_t path[])
{
    frame_t *fr = stack; /* &stack[g] */
    uint8_t g = 0;

    /* Root: not solved, and h <= bound (solve_ranks checks both). */
    fr->p = fr->np = p;
    fr->o = fr->no = o;
    fr->face = fr->turn = 0;
    fr->last_face = 3;

    for (;;) {
        if (fr->face == 3) {
            if (g == 0)
                return -1; /* nothing within this bound */
            /* pop */
            --g;
            fr = &stack[g];
            continue;
        }
        if (fr->turn == 3 || fr->face == fr->last_face) {
            /* next face, from this node again */
            ++fr->face;
            fr->turn = 0;
            fr->np = fr->p;
            fr->no = fr->o;
            continue;
        }

        /* next child: one more quarter turn of face */
        fr->np = perm_move[fr->face][fr->np];
        fr->no = ori_move[fr->face][fr->no];
        path[g] = (fr->face << 1U) + fr->face + fr->turn;
        ++fr->turn;
        if (fr->np == 0 && fr->no == 0)
            return g + 1;
        if (g + 1 + heuristic(fr->np, fr->no) > bound)
            continue;
        /* push */
        ++g;
        fr = &stack[g];
        fr->face = 0;
        fr->turn = 0;
        fr->last_face = stack[g - 1].face;
        fr->p = fr->np = stack[g - 1].np;
        fr->o = fr->no = stack[g - 1].no;
    }
}

/* Raise the bound from h(root) until a search succeeds (diameter 11). */
static int solve_ranks(uint16_t p, uint16_t o, uint8_t path[])
{
    if (p == 0 && o == 0)
        return 0;

    uint8_t bound = heuristic(p, o);

    while (bound <= 11) {
        int len = search(p, o, bound, path);
        if (len >= 0)
            return len;
        ++bound;
    }

    return -1;
}

/* ---- Interface ---- */

/* Exactly 14 chars: 7 distinct cubies '1'..'7', then 7 twists '1'..'3'
 * summing to 0 mod 3. Fills p[] and o[] 0-based; returns 0 if invalid.
 */
static int parse_state(const char *s, uint8_t p[CUBIES], uint8_t o[CUBIES])
{
    uint8_t seen = 0, sum = 0;
    for (int i = 0; i < CUBIES; ++i) {
        uint8_t c = (uint8_t) (s[i] - '1');
        if (c >= CUBIES || (seen >> c) & 1U)
            return 0;
        seen |= (uint8_t) (1U << c);
        p[i] = c;
    }
    for (int i = 0; i < CUBIES; ++i) {
        uint8_t t = (uint8_t) (s[CUBIES + i] - '1');
        if (t >= 3)
            return 0;
        o[i] = t;
        sum = (uint8_t) (sum + t);
    }
    while (sum >= 3)
        sum = (uint8_t) (sum - 3U);
    return s[14] == '\0' && sum == 0;
}

/* Write the moves separated by spaces. Returns len, or -2 (and an empty
 * string if cap > 0) when the text does not fit.
 */
static int write_solution(const uint8_t path[], int len, char *out, size_t cap)
{
    size_t need = 1; /* the terminator */
    for (int i = 0; i < len; i++) {
        if (i > 0) {
            need += 1;
        }
        need += (move_names[path[i]][1] == '\0') ? 1 : 2;
    }

    if (need > cap) {
        if (cap > 0) {
            out[0] = '\0';
        }
        return -2;
    }

    size_t pos = 0;
    for (int i = 0; i < len; i++) {
        if (i > 0) {
            out[pos++] = ' ';
        }

        const char *name = move_names[path[i]];
        for (int k = 0; name[k] != '\0'; k++) {
            out[pos++] = name[k];
        }
    }

    out[pos] = '\0';

    return len;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    uint8_t p[CUBIES], o[CUBIES], path[11];

    if (!parse_state(state, p, o)) {
        return -1;
    }

    if (!tables_ready) {
        init_tables();
        tables_ready = 1;
    }

    int len = solve_ranks(rank_perm(p), rank_ori(o), path);

    return write_solution(path, len, out, cap);
}
