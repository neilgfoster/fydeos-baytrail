/* iconia-buttond.c — remap the Windows/home button.
 *
 * The soc_button_array driver emits KEY_LEFTMETA for the Windows button.
 * ChromeOS has no long-press remap, so this tiny daemon watches that evdev
 * node and times the KEY_LEFTMETA press:
 *   - long hold  (>= HOLD_MS)                 -> inject Ctrl+Alt+T (open crosh)
 *   - double-tap (two short presses <= GAP)   -> ask powerd to suspend (sleep)
 *
 * The sleep gesture is our only user-facing way to sleep on demand: the tablet
 * has no working RTC wake and Chrome's tablet power-menu offers no "Sleep", but
 * kernel s2idle suspend/resume works and the power button reliably wakes it
 * (S24). We shell out to powerd_dbus_suspend so suspend goes through the normal
 * ChromeOS pipeline (suspend delays, dark-resume, lock policy), not a raw
 * /sys/power/state write.
 *
 * We deliberately do NOT EVIOCGRAB the device: soc_button_array also carries
 * power + volume, and grabbing would swallow those (dangerous on power). So the
 * short press keeps its normal "home" action; the long press / double-tap ADD
 * their actions.
 *
 * Build (static, so it runs on the libstdc++-less ChromeOS base):
 *   gcc -O2 -static -o iconia-buttond iconia-buttond.c
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>

#define HOLD_MS 2000        /* long-press threshold -> crosh                */
#define DOUBLE_GAP_MS 500   /* max gap between two short taps -> sleep      */

#define POWERD_SUSPEND "/usr/bin/powerd_dbus_suspend"

static long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

#define BITS_PER_LONG (sizeof(long) * 8)
#define NBITS(x) (((x) / BITS_PER_LONG) + 1)
#define TEST_BIT(bit, arr) ((arr[(bit) / BITS_PER_LONG] >> ((bit) % BITS_PER_LONG)) & 1)

/* find the event node that reports KEY_LEFTMETA (the Windows button). The
 * soc_button_array driver names its nodes "gpio-keys", so match by capability
 * rather than name — robust regardless of how the buttons are split up. */
static int open_buttons(void) {
    DIR *d = opendir("/dev/input");
    struct dirent *e;
    char path[288];
    unsigned long keybits[NBITS(KEY_MAX)];
    int fd = -1;
    if (!d) return -1;
    while ((e = readdir(d))) {
        if (strncmp(e->d_name, "event", 5)) continue;
        snprintf(path, sizeof path, "/dev/input/%s", e->d_name);
        int f = open(path, O_RDONLY);
        if (f < 0) continue;
        memset(keybits, 0, sizeof keybits);
        if (ioctl(f, EVIOCGBIT(EV_KEY, sizeof keybits), keybits) >= 0 &&
            TEST_BIT(KEY_LEFTMETA, keybits)) {
            fd = f;
            break;
        }
        close(f);
    }
    closedir(d);
    return fd;
}

static int make_uinput(void) {
    int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) return -1;
    ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ioctl(fd, UI_SET_KEYBIT, KEY_LEFTCTRL);
    ioctl(fd, UI_SET_KEYBIT, KEY_LEFTALT);
    ioctl(fd, UI_SET_KEYBIT, KEY_T);
    /* Match the id of the proven-working injtest: ChromeOS/ozone routes
     * accelerator keys from a BUS_USB keyboard but appears to ignore a
     * BUS_VIRTUAL one, so Ctrl+Alt+T never reached the crosh accelerator. */
    struct uinput_setup us;
    memset(&us, 0, sizeof us);
    us.id.bustype = BUS_USB;
    us.id.vendor = 0x1234;
    us.id.product = 0x5678;
    strcpy(us.name, "iconia-buttond");
    ioctl(fd, UI_DEV_SETUP, &us);
    ioctl(fd, UI_DEV_CREATE);
    return fd;
}

static void emit(int fd, int type, int code, int val) {
    struct input_event ev;
    memset(&ev, 0, sizeof ev);
    ev.type = type;
    ev.code = code;
    ev.value = val;
    write(fd, &ev, sizeof ev);
}

/* Request a normal ChromeOS suspend. fork+exec so we never block the evdev
 * read loop; SIGCHLD is ignored (see main) so the child is auto-reaped. */
static void do_suspend(int dbg) {
    if (dbg) fprintf(stderr, "buttond: FIRE (powerd_dbus_suspend)\n");
    pid_t p = fork();
    if (p == 0) {
        /* --delay=1: keep our injected/close-in-time input from being read as
         * user activity that immediately cancels the suspend request. */
        execl(POWERD_SUSPEND, "powerd_dbus_suspend", "--delay=1", (char *)NULL);
        _exit(127);
    }
}

static void send_crosh(int u) {
    emit(u, EV_KEY, KEY_LEFTCTRL, 1);
    emit(u, EV_KEY, KEY_LEFTALT, 1);
    emit(u, EV_KEY, KEY_T, 1);
    emit(u, EV_SYN, SYN_REPORT, 0);
    usleep(20000);
    emit(u, EV_KEY, KEY_T, 0);
    emit(u, EV_KEY, KEY_LEFTALT, 0);
    emit(u, EV_KEY, KEY_LEFTCTRL, 0);
    emit(u, EV_SYN, SYN_REPORT, 0);
}

int main(void) {
    int dbg = getenv("BUTTOND_DEBUG") != 0;
    int bfd = open_buttons();
    if (bfd < 0) { fprintf(stderr, "no KEY_LEFTMETA device found\n"); return 1; }
    int ufd = make_uinput();
    if (ufd < 0) { fprintf(stderr, "cannot open /dev/uinput (module loaded?)\n"); return 1; }
    /* auto-reap the powerd_dbus_suspend children we fork on the sleep gesture */
    signal(SIGCHLD, SIG_IGN);
    if (dbg) fprintf(stderr, "buttond: watching fd, uinput ready, HOLD_MS=%d GAP=%d\n",
                     HOLD_MS, DOUBLE_GAP_MS);

    struct input_event ev;
    long press_ms = 0;        /* monotonic ms of the last KEY_LEFTMETA press   */
    long last_tap_ms = 0;     /* release time of the previous short tap        */

    /* Fire on RELEASE after a long-enough hold. We must NOT inject while the
     * button is held: the Windows button *is* KEY_LEFTMETA, so injecting
     * Ctrl+Alt+T while it is physically down makes Chrome see Meta+Ctrl+Alt+T,
     * not the crosh accelerator. Waiting for release gives a clean Ctrl+Alt+T. */
    while (read(bfd, &ev, sizeof ev) == (ssize_t)sizeof ev) {
        if (ev.type != EV_KEY || ev.code != KEY_LEFTMETA) continue;
        if (ev.value == 1) {                    /* press */
            press_ms = now_ms();
            if (dbg) fprintf(stderr, "buttond: press\n");
        } else if (ev.value == 0 && press_ms) { /* release */
            long rel = now_ms();
            long held = rel - press_ms;
            press_ms = 0;
            if (dbg) fprintf(stderr, "buttond: release after %ldms\n", held);
            if (held >= HOLD_MS) {
                if (dbg) fprintf(stderr, "buttond: FIRE (send Ctrl+Alt+T)\n");
                send_crosh(ufd);
                last_tap_ms = 0;            /* a long hold isn't a tap       */
            } else if (last_tap_ms && (rel - last_tap_ms) <= DOUBLE_GAP_MS) {
                do_suspend(dbg);            /* second short tap -> sleep      */
                last_tap_ms = 0;
            } else {
                last_tap_ms = rel;          /* first short tap; await a second*/
            }
        }
    }
    return 0;
}
