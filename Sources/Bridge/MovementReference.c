#include "MovementABI.h"

static int bit(const HMMovementInput *in, int at) { return in->cell[at] != 0; }
static int pos(int value) { return value > 0; }
static int neg(int value) { return value < 0; }
static int clamp50(int value) { return value > 50 ? 50 : (value < -50 ? -50 : value); }

int HM_InputInDomain(const HMMovementInput *in) {
    for (int i = 0; i <= HM_MOUSE_STRAFE_RIGHT; ++i)
        if (in->cell[i] != 0 && in->cell[i] != 1) return 0;
    for (int i = HM_JOY_STRAFE; i <= HM_JOY_STRAFE_RIGHT; ++i)
        if (in->cell[i] != 0 && in->cell[i] != 1) return 0;
    for (int i = HM_JOY_X; i <= HM_JOY_SIDE; ++i)
        if (in->cell[i] < -1 || in->cell[i] > 1) return 0;
    return in->cell[HM_MOUSE_X] >= -256 && in->cell[HM_MOUSE_X] <= 256
        && in->cell[HM_MOUSE_Y] >= -8192 && in->cell[HM_MOUSE_Y] <= 8192
        && in->cell[HM_TURNHELD] >= 0 && in->cell[HM_TURNHELD] <= 16777212
        && in->cell[HM_TICDUP] >= 1 && in->cell[HM_TICDUP] <= 4;
}

HMMovementOutput HM_ReferenceMovement(const HMMovementInput *in) {
    const int *v = in->cell;
    int strafe = v[HM_KEY_STRAFE] || v[HM_MOUSE_STRAFE] || v[HM_JOY_STRAFE];
    int speed = v[HM_SPEED];
    int turn = v[HM_JOY_X] || v[HM_KEY_RIGHT] || v[HM_KEY_LEFT];
    int held = turn ? v[HM_TURNHELD] + v[HM_TICDUP] : 0;
    int tspeed = held < 6 ? 2 : speed;
    const int forwardmove[2] = {25, 50};
    const int sidemove[2] = {24, 40};
    const int angleturn[3] = {640, 1280, 320};
    int side = 0, forward = 0, angle = 0;
    if (strafe) {
        if (v[HM_KEY_RIGHT]) side += sidemove[speed];
        if (v[HM_KEY_LEFT]) side -= sidemove[speed];
        if (pos(v[HM_JOY_X])) side += sidemove[speed];
        if (neg(v[HM_JOY_X])) side -= sidemove[speed];
    } else {
        if (v[HM_KEY_RIGHT]) angle -= angleturn[tspeed];
        if (v[HM_KEY_LEFT]) angle += angleturn[tspeed];
        if (pos(v[HM_JOY_X])) angle -= angleturn[tspeed];
        if (neg(v[HM_JOY_X])) angle += angleturn[tspeed];
    }
    if (v[HM_KEY_UP]) forward += forwardmove[speed];
    if (v[HM_KEY_DOWN]) forward -= forwardmove[speed];
    if (neg(v[HM_JOY_Y])) forward += forwardmove[speed];
    if (pos(v[HM_JOY_Y])) forward -= forwardmove[speed];
    if (v[HM_KEY_STRAFE_LEFT] || v[HM_JOY_STRAFE_LEFT]
        || v[HM_MOUSE_STRAFE_LEFT] || neg(v[HM_JOY_SIDE])) side -= sidemove[speed];
    if (v[HM_KEY_STRAFE_RIGHT] || v[HM_JOY_STRAFE_RIGHT]
        || v[HM_MOUSE_STRAFE_RIGHT] || pos(v[HM_JOY_SIDE])) side += sidemove[speed];
    if (v[HM_MOUSE_FORWARD]) forward += forwardmove[speed];
    if (v[HM_MOUSE_BACKWARD]) forward -= forwardmove[speed];
    forward += v[HM_MOUSE_Y];
    if (strafe) side += v[HM_MOUSE_X] * 2;
    else angle -= v[HM_MOUSE_X] * 8;
    return (HMMovementOutput){clamp50(forward), clamp50(side), angle, held};
}
