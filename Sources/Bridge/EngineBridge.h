#ifndef HM_ENGINE_BRIDGE_H
#define HM_ENGINE_BRIDGE_H
#include "MovementABI.h"
#include <stdint.h>
void HM_EngineStart(const char *iwad_path);
void HM_EngineFrame(void);
void HM_EnginePostMouse(int buttons, int dx, int dy);
int HM_EngineGametic(void);
const uint32_t *HM_EnginePixels(void);
typedef struct { int32_t in_level, gametic, x, y, angle; } HMPlayerState;
HMPlayerState HM_EnginePlayerState(void);
#endif
