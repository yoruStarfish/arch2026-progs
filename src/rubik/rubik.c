#include "rubik.h"
#include <stdbool.h>
#include "pdb_data.h"
#include "transition_data.h"

enum {
    CUBIES = 7,
    PERMUTATIONS = 5040,
    ORIENTATIONS = 729,
    MOVES = 9,
    MAX_DEPTH = 11,
    ROOT_MOVE = 9
};

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;


static const char *const move_names[MOVES] = {"R",  "R2", "R'", "B", "B2",
                                              "B'", "D",  "D2", "D'"};

/* First nine rows have six successors. The root has all nine.
 * Consecutive turns of one face combine into one move (or cancel). */
static const uint8_t valid_next_moves[10][9] = {
    /*
    R: 0-2
    B: 3-5
    D: 6-8
    */
    {3, 4, 5, 6, 7, 8},         {3, 4, 5, 6, 7, 8}, {3, 4, 5, 6, 7, 8},
    {0, 1, 2, 6, 7, 8},         {0, 1, 2, 6, 7, 8}, {0, 1, 2, 6, 7, 8},
    {0, 1, 2, 3, 4, 5},         {0, 1, 2, 3, 4, 5}, {0, 1, 2, 3, 4, 5},
    {0, 1, 2, 3, 4, 5, 6, 7, 8}  // root
};
static const uint8_t successor_count[10] = {6, 6, 6, 6, 6, 6, 6, 6, 6, 9};
static const uint16_t powers_of_3[6] = {1, 3, 9, 27, 81, 243};
static const uint16_t factorial[7] = {720, 120, 24, 6, 2, 1, 1};
static const uint8_t mod3[15] = {0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2};


static uint8_t get_pdb_distance(const uint8_t *pdb, uint32_t index)
{
    // 15U = 0x0F
    // index & 1U gives 0 for even index and 1 for odd index
    // (index & 1U) << 2 gives 0 for even index and 4 for odd index
    return (uint8_t) ((pdb[index >> 1] >> ((index & 1U) << 2)) & 15U);
}

/* Least-significant trit first, matching the offline PDB generator.
 * Select 0, weight, or twice weight without multiplication. */
static uint32_t get_orientation_index(const uint8_t ori[CUBIES])
{
    /* index = summation_{i=0}^5 ori[i]*(3^i) */
    // 0U-0 = 0, 0U-1 = 0xFFFFFFFFF
    /*
    If ori[i] == 0, then index += (weight & 0) | 0, that is 0
    If ori[i] == 1, then index += (weight & 0xFFFFFFFF) | 0, that is weight
    If ori[i] == 2, then index += (weight << 1) & 0xFFFFFFFF, that is twice the
    weight
    */
    uint32_t index = 0;
    for (uint8_t i = 0; i < 6; ++i) {
        uint32_t weight = powers_of_3[i];
        index += (weight & (0U - (uint32_t) (ori[i] == 1))) |
                 ((weight << 1) & (0U - (uint32_t) (ori[i] == 2)));
    }
    return index;  // Range: 0~728
}

/* Each smaller following cubie contributes one factorial weight.
 * This is Lehmer ranking using additions, with no mul/div/rem. */
static uint32_t get_permutation_index(const uint8_t perm[CUBIES])
{
    // There are 7! = 5040 permutations of 7 cubies. The index is the Lehmer
    // code of the permutation.
    /*
    index =
    (count of smaller numbers to the right of position 0) × 6!
  + (count of smaller numbers to the right of position 1) × 5!
  + (count of smaller numbers to the right of position 2) × 4!
  + (count of smaller numbers to the right of position 3) × 3!
  + (count of smaller numbers to the right of position 4) × 2!
  + (count of smaller numbers to the right of position 5) × 1!
    */
    // for example, 0 is [0, 1, 2], 1 is [0, 2, 1], 2 is [1, 0, 2], 3 is [1, 2,
    // 0], 4 is [2, 0, 1], 5 is [2, 1, 0]
    uint32_t index = 0;
    for (uint8_t i = 0; i < 6;
         ++i)  // i means the position of the current cubie in the permutation
        for (uint8_t j = (uint8_t) (i + 1); j < CUBIES;
             ++j)  // j means the position of the cubies after the current cubie
            index += factorial[i] & (0U - (uint32_t) (perm[j] < perm[i]));
    return index;  // Range: 0~5039
    /*
    uint32_t index = 0;

    for (uint8_t i = 0; i < 6; ++i) {
        for (uint8_t j = i + 1; j < CUBIES; ++j) {
            if (perm[j] < perm[i]) {
                index += factorial[i];
            }
        }
    }

    return index;
    */
}



static inline uint8_t coordinate_heuristic(uint16_t p, uint16_t o)
{
    uint8_t ori = get_pdb_distance(pdb_orientation_packed, o);
    uint8_t perm = get_pdb_distance(pdb_permutation_packed, p);
    return ori > perm ? ori : perm;
}


static uint8_t evaluate_heuristic(const state_t *state)
{
    return coordinate_heuristic((uint16_t) get_permutation_index(state->p),
                                (uint16_t) get_orientation_index(state->o));
}


/* Coordinate DFS: each child needs two transition lookups, no cubie mapping
 * or re-ranking. Explicit frames replace recursive calls. Each depth retains
 * its state and next successor cursor, so popping restores the parent without
 * undo. Static storage: no heap or recursive call stack; not
 * reentrant/thread-safe. */
typedef struct {
    uint16_t p;              // permutation coordinate: 0..5039
    uint16_t o;              // orientation coordinate: 0..728
    uint8_t last_move;       // the last move that was applied to the cube
                             // (ROOT_MOVE=9, the first step is to try 9 moves)
    uint8_t next_successor;  // the index of the next successor to be explored
} search_frame_t;
static search_frame_t search_stack[MAX_DEPTH + 1];
/*
search_stack[0]  initial state
search_stack[1]  the state after the first move
……
search_stack[11] the state after the 11th move
*/



static int dfs_search(const state_t *state,
                      uint8_t g,
                      uint8_t bound,
                      uint8_t last_move,
                      uint8_t path[MAX_DEPTH])
/*
state: the current state of the cube
g: the current depth of the search
bound: the maximum depth of the search (the maximum number of moves that can be
applied to the cube) last_move: the last move that was applied to the cube
(ROOT_MOVE=9, the first step is to try 9 moves) path: the array that stores the
moves that have been applied to the cube
*/
{
    if (g > MAX_DEPTH || bound > MAX_DEPTH || last_move > ROOT_MOVE)
        return -1;
    const uint8_t root_depth = g;
    // Push the initial state onto the stack
    search_stack[g].p = (uint16_t) get_permutation_index(state->p);
    search_stack[g].o = (uint16_t) get_orientation_index(state->o);
    search_stack[g].last_move = last_move;
    search_stack[g].next_successor = 0;
    for (;;) {
        search_frame_t *frame = &search_stack[g];
        /* Evaluate a frame once on entry, not again after every child. */
        if (frame->next_successor ==
            0) {  // next_successor == 0 means that we have not evaluated the
                  // current state yet
            uint8_t h = coordinate_heuristic(frame->p, frame->o);
            if (g + h > bound)
                goto pop_frame;
            if (frame->p == 0 && frame->o == 0)
                return g; /* Total steps from the initial input. */
            if (g >= bound || g >= MAX_DEPTH)
                goto pop_frame;
        }
        if (frame->next_successor == successor_count[frame->last_move])
            // if all (6 or 9) successors have been explored, we need to pop the
            // current frame and return to the parent frame
            goto pop_frame;
        {
            // Select the next successor to explore, push it onto the stack, and
            // continue the search Then we will explore the next successor in
            // the next iteration of the loop (next_surcessor will be
            // incremented)
            uint8_t move =
                valid_next_moves[frame->last_move][frame->next_successor++];
            search_frame_t *child = &search_stack[g + 1];
            path[g] = move;
            child->p = permutation_transition[move][frame->p];
            child->o = orientation_transition[move][frame->o];
            child->last_move = move;
            child->next_successor = 0;
            ++g; /* Push: visit the child before trying another sibling. */
        }
        continue;
    pop_frame:
        if (g == root_depth)
            return -1;
        --g;  // Pop: return to the parent frame
    }
}

static int ida_star(const state_t *state, uint8_t path[MAX_DEPTH])
{
    for (uint8_t bound = evaluate_heuristic(state); bound <= MAX_DEPTH;
         ++bound) {
        // If we cannot find the answer in this branch, we need to redo dfs and
        // make ++bound
        int length = dfs_search(state, 0, bound, ROOT_MOVE, path);
        if (length >= 0)
            return length;
    }
    return -1;
}

static bool parse_state(const char *input, state_t *state)
{
    uint32_t seen = 0;
    uint8_t sum = 0;
    /* Stop at an early NUL before reading any later input position. */
    for (uint8_t i = 0; i < 14; ++i) {
        if (input[i] == '\0')
            return false;
    }
    if (input[14] != '\0')
        return false;
    for (uint8_t i = 0; i < CUBIES; ++i) {
        if (input[i] < '1' || input[i] > '7' || input[i + CUBIES] < '1' ||
            input[i + CUBIES] > '3')
            return false;
        state->p[i] = (uint8_t) (input[i] - '1');
        state->o[i] = (uint8_t) (input[i + CUBIES] - '1');
        uint32_t bit = 1U << state->p[i];
        if (seen & bit)
            return false;
        seen |= bit;
        sum = (uint8_t) (sum + state->o[i]);
    }
    return mod3[sum] == 0;
}



int rubik_solve(const char *input, char *out, size_t cap)
{
    state_t state;
    uint8_t path[MAX_DEPTH];

    if (!parse_state(input, &state))
        return -1;

    int moves = ida_star(&state, path);
    if (moves < 0)
        return -1;

    char text[3 * MAX_DEPTH + 1];
    size_t len = 0;

    for (int i = 0; i < moves; i++) {
        if (i != 0)
            text[len++] = ' ';

        const char *name = move_names[path[i]];
        while (*name != '\0')
            text[len++] = *name++;
    }
    text[len] = '\0';

    if (cap <= len) {
        if (cap != 0)
            out[0] = '\0';
        return -2;
    }

    for (size_t i = 0; i <= len; i++)
        out[i] = text[i];

    return moves;
}
