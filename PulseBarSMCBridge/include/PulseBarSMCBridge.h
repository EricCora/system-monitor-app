#ifndef PULSEBAR_SMC_BRIDGE_H
#define PULSEBAR_SMC_BRIDGE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PULSEBAR_SMC_MAX_FANS 8

typedef struct PulseBarFanSnapshot {
    int fan_count;
    int rpm_count;
    double rpms[PULSEBAR_SMC_MAX_FANS];
} PulseBarFanSnapshot;

int pulsebar_read_fans(PulseBarFanSnapshot *out_snapshot, char *error_buffer, size_t error_buffer_size);

#ifdef __cplusplus
}
#endif

#endif
