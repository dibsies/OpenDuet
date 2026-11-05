#include "command.h"
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>

static int bank(const char *text, uint8_t bytes[8]) {
    if (strlen(text) != 16) return 0;
    for (unsigned i = 0; i < 8; ++i) {
        char pair[3] = {text[i * 2], text[i * 2 + 1], 0};
        for (unsigned j = 0; j < 2; ++j)
            if (!((pair[j] >= '0' && pair[j] <= '9') || (pair[j] >= 'a' && pair[j] <= 'f') ||
                  (pair[j] >= 'A' && pair[j] <= 'F'))) return 0;
        bytes[i] = (uint8_t)strtoul(pair, NULL, 16);
    }
    for (unsigned i = 0; i < 8; i += 2)
        if (((unsigned)bytes[i] << 8 | bytes[i + 1]) > 32768) return 0;
    return 1;
}

int duet_parse(int argc, char **argv, DuetCommand *c) {
    memset(c, 0, sizeof *c);
    c->count = 1;
    if (argc == 1) { c->kind = DuetIdentifier; return 1; }
    if (argc == 2) {
        if (!strcmp(argv[1], "--meters")) c->kind = DuetMeters;
        else if (!strcmp(argv[1], "--input-modes")) c->kind = DuetModes;
        else if (!strcmp(argv[1], "--events")) c->kind = DuetEvents;
        else return 0;
        return 1;
    }
    if (argc != 5 || strcmp(argv[4], "--apply")) return 0;
    if (!strcmp(argv[1], "--experimental-display")) {
        if (strcmp(argv[2], "device") || argv[3][0] != '/' || strlen(argv[3]) >= sizeof c->framePath) return 0;
        c->kind = DuetDisplay;
        strcpy(c->framePath, argv[3]);
        return 1;
    }
    if (!strcmp(argv[1], "--experimental-startup-muted")) {
        c->kind = DuetStartup;
        return !strcmp(argv[2], "device") && !strcmp(argv[3], "1");
    }
    if (!strcmp(argv[1], "--experimental-mixer")) {
        c->kind = DuetMixer;
        return bank(argv[2], c->banks[0]) && bank(argv[3], c->banks[1]) &&
            !c->banks[0][6] && !c->banks[0][7] && !c->banks[1][4] && !c->banks[1][5];
    }
    c->kind = DuetWrite;
    unsigned maximum;
    if (!strcmp(argv[1], "--experimental-attenuation") || !strcmp(argv[1], "--experimental-output-mute")) {
        if (!strcmp(argv[2], "main")) c->firstIndex = 1;
        else if (!strcmp(argv[2], "headphones")) c->firstIndex = 3;
        else return 0;
        c->request = !strcmp(argv[1], "--experimental-output-mute") ? 0x35 : 0x33;
        c->count = 2;
        maximum = c->request == 0x35 ? 1 : 79;
    } else if (!strcmp(argv[1], "--experimental-reference")) {
        if (strcmp(argv[2], "main")) return 0;
        c->request = 0x18; c->count = 2; maximum = 1;
    } else if (!strcmp(argv[1], "--experimental-routing")) {
        if (strcmp(argv[2], "outputs")) return 0;
        c->request = 0x37; maximum = 0x22;
    } else if (!strcmp(argv[1], "--experimental-mixer-source")) {
        if (strcmp(argv[2], "mixer")) return 0;
        c->request = 0x36; maximum = 1;
    } else if (!strcmp(argv[1], "--experimental-mono")) {
        if (strcmp(argv[2], "outputs")) return 0;
        c->request = 0x38; maximum = 17;
    } else {
        if (!strcmp(argv[2], "1")) c->firstIndex = 0;
        else if (!strcmp(argv[2], "2")) c->firstIndex = 1;
        else return 0;
        if (!strcmp(argv[1], "--experimental-mode")) { c->request = 0x16; maximum = 3; }
        else if (!strcmp(argv[1], "--experimental-mic-gain")) { c->request = 0x34; maximum = 75; ++c->firstIndex; }
        else if (!strcmp(argv[1], "--experimental-instrument-gain")) { c->request = 0x3e; maximum = 65; ++c->firstIndex; }
        else if (!strcmp(argv[1], "--experimental-phantom")) { c->request = 0x15; maximum = 1; }
        else if (!strcmp(argv[1], "--experimental-soft-limit")) { c->request = 0x11; maximum = 1; }
        else if (!strcmp(argv[1], "--experimental-phase")) { c->request = 0x13; maximum = 1; }
        else return 0;
    }
    char *end;
    errno = 0;
    long value = strtol(argv[3], &end, 10);
    if (errno || end == argv[3] || *end || value < 0 || value > maximum) return 0;
    if (c->request == 0x38 && value != 0 && value != 1 && value != 16 && value != 17) return 0;
    if (c->request == 0x37 && ((value & 15) > 2 || (value >> 4) > 2)) return 0;
    c->payload = (uint8_t)value;
    return 1;
}

static int transfer(DuetTransport *t, FILE *out, uint8_t direction, uint8_t request,
                    uint16_t index, uint16_t length, void *data) {
    uint16_t actual = 0;
    uint32_t status = t->transfer(t->context, direction, request, 0, index, length, data, &actual);
    if (direction == 0x40 || status || actual != length)
        fprintf(out, "Request %#x index %u: %#x, transferred %u bytes\n", request, index, status, actual);
    return status == 0 && actual == length;
}

int duet_execute(DuetTransport *t, const DuetCommand *c, FILE *out) {
    uint8_t reply[29] = {0};
    if (c->kind == DuetDisplay) {
        const unsigned length = 160 * 128 * 2;
        FILE *file = fopen(c->framePath, "rb");
        struct stat info;
        if (!file) { fputs("Display frame could not be opened.\n", out); return 1; }
        if (fstat(fileno(file), &info) || !S_ISREG(info.st_mode) || info.st_size != length) {
            fclose(file); fputs("Display frame must be a regular 40960-byte RGB565 file.\n", out); return 1;
        }
        uint8_t *pixels = malloc(length);
        if (!pixels) { fclose(file); return 1; }
        size_t read = fread(pixels, 1, length, file);
        fclose(file);
        if (read != length) { free(pixels); return 1; }
        unsigned sent = 0, tiles = 0;
        for (unsigned row = 0; row < 128; row += 8) {
            for (unsigned column = 0; column < 160; column += 16) {
                int changed = !t->displayCache || !t->displayCache->valid;
                uint8_t tile[16 * 8 * 2];
                for (unsigned y = 0; y < 8; ++y) {
                    unsigned offset = ((row + y) * 160 + column) * 2;
                    memcpy(tile + y * 32, pixels + offset, 32);
                    if (t->displayCache && memcmp(pixels + offset, t->displayCache->pixels + offset, 32)) changed = 1;
                }
                if (!changed) continue;
                ++tiles;
                for (unsigned offset = 0; offset < sizeof tile; offset += 64) {
                    uint8_t request = offset == 0 ? 0x21 : 0x22;
                    uint16_t value = offset == 0 ? (uint16_t)(column << 8 | row) : 0;
                    uint16_t index = offset == 0 ? (uint16_t)((column + 15) << 8 | (row + 7)) : 0;
                    uint16_t actual = 0;
                    uint32_t status = t->transfer(t->context, 0x40, request, value, index, 64, tile + offset, &actual);
                    if (status || actual != 64) {
                        fprintf(out, "Display tile %u,%u: %#x, transferred %u bytes; frame incomplete.\n", column, row, status, actual);
                        if (t->displayCache) t->displayCache->valid = 0;
                        free(pixels); return 1;
                    }
                    sent += actual;
                }
            }
        }
        if (t->displayCache) {
            memcpy(t->displayCache->pixels, pixels, length);
            t->displayCache->valid = 1;
        }
        free(pixels);
        fprintf(out, "Display updated: %u changed tiles, %u pixel bytes\n", tiles, sent);
        return 0;
    }
    if (c->kind == DuetStartup) {
        if (t->displayCache) t->displayCache->valid = 0;
        const uint8_t requests[] = {0x35, 0x33, 0xab, 0x25};
        const uint8_t values[] = {1, 64, 0, 1};
        for (unsigned stage = 0; stage < 4; ++stage) {
            unsigned first = stage < 2 ? 1 : 0, last = stage < 2 ? 4 : 0;
            for (unsigned index = first; index <= last; ++index) {
                uint8_t data = values[stage];
                if (!transfer(t, out, 0x40, requests[stage], index, 1, &data)) {
                    fputs("Startup incomplete; device state may be partial.\n", out); return 1;
                }
            }
        }
        fputs("Startup transfers completed; display and audio behavior still require confirmation.\n", out);
        return 0;
    }
    if (c->kind == DuetModes) {
        for (unsigned channel = 0; channel < 2; ++channel)
            if (!transfer(t, out, 0xc0, 0x16, channel, 1, &reply[channel]) || reply[channel] > 3) return 1;
        fprintf(out, "INPUT_MODES %u %u\n", reply[0], reply[1]); return 0;
    }
    if (c->kind == DuetWrite) {
        if (c->request == 0x34 || c->request == 0x3e) {
            if (!transfer(t, out, 0xc0, 0x16, c->firstIndex - 1, 1, reply) ||
                reply[0] != (c->request == 0x34 ? 2 : 3)) {
                fputs("Gain not sent: active input mode could not be confirmed or does not match.\n", out); return 1;
            }
        }
        for (unsigned i = 0; i < c->count; ++i) {
            uint8_t data = c->payload;
            if (!transfer(t, out, 0x40, c->request, c->firstIndex + i, 1, &data)) {
                fputs("Control update incomplete; check device state before monitoring.\n", out); return 1;
            }
        }
        return 0;
    }
    if (c->kind == DuetMixer) {
        for (unsigned side = 0; side < 2; ++side) {
            uint8_t data[8]; memcpy(data, c->banks[side], sizeof data);
            if (!transfer(t, out, 0x40, 0x10, side, 8, data)) {
                fputs("Mixer update incomplete; banks may differ.\n", out); return 1;
            }
        }
        return 0;
    }
    uint16_t length = c->kind == DuetMeters ? 20 : c->kind == DuetEvents ? 29 : 8;
    uint8_t request = c->kind == DuetMeters ? 0x14 : c->kind == DuetEvents ? 0x29 : 0x31;
    if (!transfer(t, out, 0xc0, request, 0, length, reply)) return 1;
    if (c->kind == DuetIdentifier) { fprintf(out, "Identifier read: 0, received 8 bytes\n"); return 0; }
    if (c->kind == DuetEvents && !reply[0]) return 0;
    fputs(c->kind == DuetMeters ? "METERS " : "EVENTS ", out);
    for (unsigned i = 0; i < length; ++i) fprintf(out, "%02x", reply[i]);
    fputc('\n', out);
    return 0;
}
