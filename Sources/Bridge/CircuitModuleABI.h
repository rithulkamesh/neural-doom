#ifndef HM_CIRCUIT_MODULE_ABI_H
#define HM_CIRCUIT_MODULE_ABI_H
#include <stdint.h>

// Stable envelope for modules after locomotion. All pointers refer to bounded
// spans owned by the scheduler for one tic; modules may only write result spans.
#define HM_CIRCUIT_MODULE_ABI_VERSION 1u
typedef enum {
    HM_MODULE_EXACT = 0,
    HM_MODULE_UNSUPPORTED_DOMAIN = 1,
    HM_MODULE_CAPACITY_EXCEEDED = 2,
    HM_MODULE_EXECUTION_ERROR = 3,
    HM_MODULE_PARITY_MISMATCH = 4
} HMModuleStatus;

typedef struct {
    uint32_t table_id;
    uint32_t length;
    uint32_t capacity;
    const int32_t *cells;
} HMTableViewV1;

typedef struct {
    uint32_t abi_version;
    uint32_t module_id;
    uint64_t tic_id;
    uint64_t source_hash;
    uint32_t input_count;
    uint32_t state_count;
    uint32_t table_count;
    uint32_t event_capacity;
    const int32_t *inputs;
    const int32_t *state_before;
    const HMTableViewV1 *tables;
} HMModuleInputV1;

typedef struct {
    uint32_t cell_id;
    int32_t before;
    int32_t after;
} HMStateDeltaV1;

typedef struct {
    uint32_t event_type;
    uint32_t source_id;
    uint32_t target_id;
    int32_t payload[4];
} HMModuleEventV1;

typedef struct {
    HMModuleStatus status;
    uint32_t output_count;
    uint32_t state_delta_count;
    uint32_t event_count;
    int32_t *outputs;
    HMStateDeltaV1 *state_deltas;
    HMModuleEventV1 *events;
} HMModuleResultV1;

#endif
