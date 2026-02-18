#include "PulseBarSMCBridge.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PULSEBAR_SMC_CONNECT_INDEX 2
#define PULSEBAR_SMC_CMD_READ_BYTES 5
#define PULSEBAR_SMC_CMD_READ_KEYINFO 9

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} PulseBarSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpu_plimit;
    uint32_t gpu_plimit;
    uint32_t mem_plimit;
} PulseBarSMCPLimitData;

typedef struct {
    uint32_t data_size;
    uint32_t data_type;
    uint8_t data_attributes;
} PulseBarSMCKeyInfoData;

typedef struct {
    uint32_t key;
    PulseBarSMCVersion version;
    PulseBarSMCPLimitData p_limit_data;
    PulseBarSMCKeyInfoData key_info;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} PulseBarSMCParamStruct;

static void pulsebar_set_error(char *buffer, size_t size, const char *message) {
    if (buffer == NULL || size == 0) {
        return;
    }
    snprintf(buffer, size, "%s", message);
}

static uint32_t pulsebar_key_from_string(const char *key) {
    if (key == NULL || strlen(key) < 4) {
        return 0;
    }
    return ((uint32_t)key[0] << 24)
        | ((uint32_t)key[1] << 16)
        | ((uint32_t)key[2] << 8)
        | ((uint32_t)key[3]);
}

static int pulsebar_data_type_matches(uint32_t data_type, const char expected[5]) {
    uint32_t expected_type = ((uint32_t)expected[0] << 24)
        | ((uint32_t)expected[1] << 16)
        | ((uint32_t)expected[2] << 8)
        | ((uint32_t)expected[3]);
    return data_type == expected_type;
}

static kern_return_t pulsebar_call_smc(io_connect_t connection, PulseBarSMCParamStruct *input, PulseBarSMCParamStruct *output) {
    size_t output_size = sizeof(PulseBarSMCParamStruct);
    return IOConnectCallStructMethod(
        connection,
        PULSEBAR_SMC_CONNECT_INDEX,
        input,
        sizeof(PulseBarSMCParamStruct),
        output,
        &output_size
    );
}

static int pulsebar_read_key(io_connect_t connection, const char *key_name, PulseBarSMCParamStruct *output, char *error_buffer, size_t error_buffer_size) {
    PulseBarSMCParamStruct input;
    PulseBarSMCParamStruct local_output;
    memset(&input, 0, sizeof(input));
    memset(&local_output, 0, sizeof(local_output));

    input.key = pulsebar_key_from_string(key_name);
    if (input.key == 0) {
        pulsebar_set_error(error_buffer, error_buffer_size, "Invalid SMC key name");
        return -1;
    }

    input.data8 = PULSEBAR_SMC_CMD_READ_KEYINFO;
    kern_return_t result = pulsebar_call_smc(connection, &input, &local_output);
    if (result != KERN_SUCCESS) {
        pulsebar_set_error(error_buffer, error_buffer_size, "SMC read key-info command failed");
        return -1;
    }

    input.key_info = local_output.key_info;
    input.data8 = PULSEBAR_SMC_CMD_READ_BYTES;
    result = pulsebar_call_smc(connection, &input, &local_output);
    if (result != KERN_SUCCESS) {
        pulsebar_set_error(error_buffer, error_buffer_size, "SMC read-bytes command failed");
        return -1;
    }

    *output = local_output;
    return 0;
}

static int pulsebar_open_smc_connection(io_connect_t *connection, char *error_buffer, size_t error_buffer_size) {
    const char *service_names[] = {
        "AppleSMC",
        "AppleSMCKeysEndpoint",
        "SMCEndpoint1"
    };
    const uint32_t type_candidates[] = {0, 1};

    for (size_t service_index = 0; service_index < sizeof(service_names) / sizeof(service_names[0]); service_index++) {
        CFMutableDictionaryRef matching = IOServiceMatching(service_names[service_index]);
        if (matching == NULL) {
            continue;
        }

        io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, matching);
        if (service == IO_OBJECT_NULL) {
            continue;
        }

        for (size_t type_index = 0; type_index < sizeof(type_candidates) / sizeof(type_candidates[0]); type_index++) {
            io_connect_t local_connection = IO_OBJECT_NULL;
            kern_return_t open_result = IOServiceOpen(
                service,
                mach_task_self(),
                type_candidates[type_index],
                &local_connection
            );
            if (open_result == KERN_SUCCESS && local_connection != IO_OBJECT_NULL) {
                IOObjectRelease(service);
                *connection = local_connection;
                return 0;
            }
        }

        IOObjectRelease(service);
    }

    pulsebar_set_error(error_buffer, error_buffer_size, "Unable to open AppleSMC connection");
    return -1;
}

static int pulsebar_decode_unsigned(const PulseBarSMCParamStruct *entry, uint32_t *value) {
    if (entry->key_info.data_size < 1 || entry->key_info.data_size > 4) {
        return -1;
    }

    if (entry->key_info.data_size == 1 || pulsebar_data_type_matches(entry->key_info.data_type, "ui8 ")) {
        *value = entry->bytes[0];
        return 0;
    }

    if (entry->key_info.data_size == 2 || pulsebar_data_type_matches(entry->key_info.data_type, "ui16")) {
        *value = ((uint32_t)entry->bytes[0] << 8) | entry->bytes[1];
        return 0;
    }

    if (entry->key_info.data_size == 4 || pulsebar_data_type_matches(entry->key_info.data_type, "ui32")) {
        *value = ((uint32_t)entry->bytes[0] << 24)
            | ((uint32_t)entry->bytes[1] << 16)
            | ((uint32_t)entry->bytes[2] << 8)
            | entry->bytes[3];
        return 0;
    }

    return -1;
}

static int pulsebar_decode_fan_rpm(const PulseBarSMCParamStruct *entry, double *value) {
    if (entry->key_info.data_size < 2) {
        return -1;
    }

    if (pulsebar_data_type_matches(entry->key_info.data_type, "fpe2")) {
        uint16_t raw = ((uint16_t)entry->bytes[0] << 8) | entry->bytes[1];
        *value = (double)raw / 4.0;
        return 0;
    }

    if (pulsebar_data_type_matches(entry->key_info.data_type, "flt ") && entry->key_info.data_size >= 4) {
        uint32_t raw = ((uint32_t)entry->bytes[0] << 24)
            | ((uint32_t)entry->bytes[1] << 16)
            | ((uint32_t)entry->bytes[2] << 8)
            | ((uint32_t)entry->bytes[3]);
        float as_float;
        memcpy(&as_float, &raw, sizeof(float));
        if (as_float >= 0) {
            *value = (double)as_float;
            return 0;
        }
    }

    return -1;
}

int pulsebar_read_fans(PulseBarFanSnapshot *out_snapshot, char *error_buffer, size_t error_buffer_size) {
    if (out_snapshot == NULL) {
        pulsebar_set_error(error_buffer, error_buffer_size, "Output snapshot pointer is null");
        return -1;
    }

    memset(out_snapshot, 0, sizeof(PulseBarFanSnapshot));

    io_connect_t connection = IO_OBJECT_NULL;
    if (pulsebar_open_smc_connection(&connection, error_buffer, error_buffer_size) != 0) {
        return -1;
    }

    uint32_t fan_count_value = 0;
    PulseBarSMCParamStruct fan_count_entry;
    int fan_count_read_ok = 0;
    if (pulsebar_read_key(connection, "FNum", &fan_count_entry, error_buffer, error_buffer_size) == 0) {
        if (pulsebar_decode_unsigned(&fan_count_entry, &fan_count_value) == 0) {
            fan_count_read_ok = 1;
        }
    }

    int max_readable = fan_count_read_ok ? (int)fan_count_value : PULSEBAR_SMC_MAX_FANS;
    if (max_readable > PULSEBAR_SMC_MAX_FANS) {
        max_readable = PULSEBAR_SMC_MAX_FANS;
    }

    for (int fan_index = 0; fan_index < max_readable; fan_index++) {
        char key_name[5];
        snprintf(key_name, sizeof(key_name), "F%dAc", fan_index);

        PulseBarSMCParamStruct fan_entry;
        if (pulsebar_read_key(connection, key_name, &fan_entry, error_buffer, error_buffer_size) != 0) {
            continue;
        }

        double rpm = 0;
        if (pulsebar_decode_fan_rpm(&fan_entry, &rpm) != 0) {
            continue;
        }

        if (rpm < 0 || rpm > 10000) {
            continue;
        }

        out_snapshot->rpms[out_snapshot->rpm_count] = rpm;
        out_snapshot->rpm_count += 1;
    }

    if (fan_count_read_ok) {
        out_snapshot->fan_count = (int)fan_count_value;
    } else {
        out_snapshot->fan_count = out_snapshot->rpm_count;
    }

    IOServiceClose(connection);
    if (fan_count_read_ok || out_snapshot->rpm_count > 0) {
        pulsebar_set_error(error_buffer, error_buffer_size, "");
    } else {
        pulsebar_set_error(error_buffer, error_buffer_size, "Unable to decode fan count");
    }
    return 0;
}
