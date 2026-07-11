/* baytrail-btnmon.c — diagnostic: watch every /dev/input/event* and print each key
 * event as "devN <name>: code=C value=V". Lets us see the real keycode the
 * Windows button emits and whether it autorepeats while held.
 * Build: gcc -O2 -static -o baytrail-btnmon baytrail-btnmon.c ; run, press buttons, Ctrl-C.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    struct pollfd pfd[64];
    char names[64][80];
    int n = 0;
    DIR *d = opendir("/dev/input");
    struct dirent *e;
    char path[288];
    while (d && (e = readdir(d)) && n < 64) {
        if (strncmp(e->d_name, "event", 5)) continue;
        snprintf(path, sizeof path, "/dev/input/%s", e->d_name);
        int f = open(path, O_RDONLY);
        if (f < 0) continue;
        names[n][0] = 0;
        ioctl(f, EVIOCGNAME(sizeof names[n]), names[n]);
        pfd[n].fd = f; pfd[n].events = POLLIN;
        fprintf(stderr, "watching %s = '%s'\n", e->d_name, names[n]);
        n++;
    }
    if (d) closedir(d);
    fprintf(stderr, "--- press/hold buttons now (Ctrl-C to stop) ---\n");
    for (;;) {
        if (poll(pfd, n, -1) <= 0) continue;
        for (int i = 0; i < n; i++) {
            if (!(pfd[i].revents & POLLIN)) continue;
            struct input_event ev;
            if (read(pfd[i].fd, &ev, sizeof ev) != (ssize_t)sizeof ev) continue;
            if (ev.type == EV_KEY)
                fprintf(stderr, "%s: code=%d value=%d\n", names[i], ev.code, ev.value);
        }
    }
    return 0;
}
