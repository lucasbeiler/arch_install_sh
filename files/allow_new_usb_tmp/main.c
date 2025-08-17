#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

void set_sysctl_value(const char *path, int new_value) {
    int fd = open(path, O_WRONLY);
    if (fd == -1) {
        perror("Failed to open sysctl file");
        exit(EXIT_FAILURE);
    }

    dprintf(fd, "%d", new_value);
    close(fd);
}

static void signal_handling() {
    printf("Signal detected. Exiting...\n");
    set_sysctl_value("/proc/sys/kernel/deny_new_usb", 1); // Lock it back.
    printf("The program was successfully interrupted!\n");
    exit(0);
}

int main() {
    // Setting some signal handlers.
    signal(SIGINT, signal_handling);
    signal(SIGTERM, signal_handling);
    signal(SIGKILL, signal_handling);

    // Allow the USB subsystem to work normally for 30 seconds.
    set_sysctl_value("/proc/sys/kernel/deny_new_usb", 0);
    printf("Go on. You have 30 seconds...\n");
    sleep(30);

    // Lock it back.
    set_sysctl_value("/proc/sys/kernel/deny_new_usb", 1);
    printf("Done! Bye!\n");

    return EXIT_SUCCESS;
}
