#ifndef OPENDUET_COMMAND_H
#define OPENDUET_COMMAND_H
#include <stdint.h>
#include <stdio.h>

typedef enum {
    DuetIdentifier, DuetMeters, DuetModes, DuetEvents, DuetWrite, DuetMixer, DuetStartup, DuetDisplay
} DuetCommandKind;

typedef struct {
    DuetCommandKind kind;
    uint8_t request, payload;
    uint16_t firstIndex, count;
    uint8_t banks[2][8];
    char framePath[768];
} DuetCommand;

typedef struct {
    int valid;
    uint8_t pixels[160 * 128 * 2];
} DuetDisplayCache;

/// The adapter owns platform handles; protocol code depends only on this contract.
typedef struct {
    void *context;
    uint32_t (*transfer)(void *, uint8_t direction, uint8_t request,
                         uint16_t value, uint16_t index, uint16_t length,
                         void *data, uint16_t *actual);
    DuetDisplayCache *displayCache;
} DuetTransport;

int duet_parse(int argc, char **argv, DuetCommand *command);
int duet_execute(DuetTransport *transport, const DuetCommand *command, FILE *output);
int duet_session(DuetTransport *transport);
#endif
