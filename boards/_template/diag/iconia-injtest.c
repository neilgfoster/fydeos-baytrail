/* iconia-injtest.c — one-shot: does a uinput-injected Ctrl+Alt+T open crosh?
 * Creates a virtual keyboard, waits for ozone to enumerate it, injects
 * Ctrl+Alt+T once, holds briefly, then destroys the device and exits.
 * Purpose: separate "injection works" from "button wiring" before rebuilding
 * the daemon.  Build: gcc -O2 -static -o iconia-injtest iconia-injtest.c
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <linux/uinput.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void emit(int fd, int type, int code, int val) {
    struct input_event ev;
    memset(&ev, 0, sizeof ev);
    ev.type = type; ev.code = code; ev.value = val;
    write(fd, &ev, sizeof ev);
}
static void syn(int fd) { emit(fd, EV_SYN, SYN_REPORT, 0); }

int main(void) {
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) { perror("open /dev/uinput"); return 1; }
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_KEYBIT, KEY_LEFTCTRL);
    ioctl(fd, UI_SET_KEYBIT, KEY_LEFTALT);
    ioctl(fd, UI_SET_KEYBIT, KEY_T);
    struct uinput_setup us; memset(&us, 0, sizeof us);
    us.id.bustype = BUS_USB; us.id.vendor = 0x1234; us.id.product = 0x5678;
    strcpy(us.name, "iconia-injtest");
    ioctl(fd, UI_DEV_SETUP, &us);
    ioctl(fd, UI_DEV_CREATE);

    fprintf(stderr, "uinput kbd created; injecting Ctrl+Alt+T in 1.5s...\n");
    usleep(1500000);                 /* let ozone register the device */

    emit(fd, EV_KEY, KEY_LEFTCTRL, 1); syn(fd); usleep(30000);
    emit(fd, EV_KEY, KEY_LEFTALT, 1);  syn(fd); usleep(30000);
    emit(fd, EV_KEY, KEY_T, 1);        syn(fd); usleep(60000);
    emit(fd, EV_KEY, KEY_T, 0);        syn(fd); usleep(30000);
    emit(fd, EV_KEY, KEY_LEFTALT, 0);  syn(fd); usleep(30000);
    emit(fd, EV_KEY, KEY_LEFTCTRL, 0); syn(fd);

    fprintf(stderr, "injected. destroying device in 0.5s.\n");
    usleep(500000);
    ioctl(fd, UI_DEV_DESTROY);
    close(fd);
    return 0;
}
