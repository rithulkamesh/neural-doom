#ifndef HM_MOVEMENT_ABI_H
#define HM_MOVEMENT_ABI_H
#include <stdint.h>
#include "CircuitModuleABI.h"

// Version 1: integer-valued Doom-normalized state before a command is built.
enum { HM_INPUT_COUNT = 24 };
enum HMInputCell {
    HM_KEY_STRAFE, HM_SPEED, HM_KEY_RIGHT, HM_KEY_LEFT,
    HM_KEY_UP, HM_KEY_DOWN, HM_KEY_STRAFE_LEFT, HM_KEY_STRAFE_RIGHT,
    HM_MOUSE_STRAFE, HM_MOUSE_FORWARD, HM_MOUSE_BACKWARD,
    HM_MOUSE_STRAFE_LEFT, HM_MOUSE_STRAFE_RIGHT, HM_MOUSE_X, HM_MOUSE_Y,
    HM_JOY_STRAFE, HM_JOY_STRAFE_LEFT, HM_JOY_STRAFE_RIGHT,
    HM_JOY_X, HM_JOY_Y, HM_JOY_SIDE, HM_TURNHELD, HM_TICDUP,
    HM_RESERVED
};
typedef struct { int32_t cell[HM_INPUT_COUNT]; } HMMovementInput;
typedef struct {
    int32_t forwardmove, sidemove, angleturn, turnheld;
} HMMovementOutput;

// The reference is a pure extraction of DoomGeneric's locomotion branch.
HMMovementOutput HM_ReferenceMovement(const HMMovementInput *input);
int HM_InputInDomain(const HMMovementInput *input);
// Test-only implementation in the adapted upstream g_game.c. It executes the
// original G_BuildTiccmd against a synthetic normalized snapshot, with the
// circuit callback disabled in the test target.
HMMovementOutput HM_TestOriginalMovement(const HMMovementInput *input);

// Implemented by the native runtime. Called on the engine's serial queue.
// Returns 1 only when circuit results are committed; 0 selects original C.
int HM_EvaluateMovement(const HMMovementInput *input,
                        const HMMovementOutput *reference,
                        HMMovementOutput *committed);
#endif
