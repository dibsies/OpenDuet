#include "command.h"
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <signal.h>
#include <sys/select.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;
static void stop_session(int signal) { (void)signal; stopping = 1; }

int duet_session(DuetTransport *transport) {
    setvbuf(stdin, NULL, _IONBF, 0);
    struct sigaction action = {0};
    action.sa_handler = stop_session;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    signal(SIGPIPE, SIG_IGN);
    unsigned failures = 0;
    puts("SESSION_READY");
    while (!stopping) {
        fd_set input;
        FD_ZERO(&input); FD_SET(STDIN_FILENO, &input);
        struct timeval timeout = {.tv_sec = 0, .tv_usec = 50000};
        int ready = select(STDIN_FILENO + 1, &input, NULL, NULL, &timeout);
        if (ready < 0) { if (errno == EINTR) continue; return 1; }
        if (ready) {
            char line[1024];
            if (!fgets(line, sizeof line, stdin)) break;
            if (!strchr(line, '\n')) { fputs("SESSION_ERROR oversized or incomplete command\n", stdout); return 1; }
            char *save = NULL;
            char *token = strtok_r(line, " \t\r\n", &save);
            if (!token) continue;
            if (!strcmp(token, "QUIT")) break;
            // Frame IDs contain decimal digits only and never become shell input.
            if (strspn(token, "0123456789") != strlen(token) || strlen(token) > 9) {
                fputs("SESSION_ERROR invalid command ID\n", stdout); return 1;
            }
            unsigned id = (unsigned)strtoul(token, NULL, 10);
            char *arguments[6] = {"openduet-session"};
            int count = 1;
            while ((token = strtok_r(NULL, " \t\r\n", &save)) && count < 6) arguments[count++] = token;
            printf("BEGIN %u\n", id);
            DuetCommand command;
            int result = 64;
            if (count < 6 && !token && duet_parse(count, arguments, &command))
                result = duet_execute(transport, &command, stdout);
            else fputs("Invalid control command\n", stdout);
            printf("END %u %d\n", id, result);
        }
        if (stopping) break;
        DuetCommand events = {.kind = DuetEvents}, meters = {.kind = DuetMeters};
        int eventStatus = duet_execute(transport, &events, stdout);
        int meterStatus = duet_execute(transport, &meters, stdout);
        failures = eventStatus || meterStatus ? failures + 1 : 0;
        if (failures >= 3) { puts("SESSION_ERROR device polling failed"); return 1; }
        if (fflush(stdout) == EOF) return 1;
    }
    puts("SESSION_CLOSED");
    return 0;
}
