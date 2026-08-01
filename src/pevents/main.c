#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <linux/input.h>
#include <errno.h>

// Function to check if a device has EV_KEY capability
int is_keyboard(int fd) {
    unsigned long evbit[1];
    int ret;

    // EVIOCGBIT(EV_KEY, sizeof(evbit)) is a macro that tells the kernel
    // to copy the EV_KEY bitmask into our buffer.
    ret = ioctl(fd, EVIOCGBIT(0, sizeof(evbit)), evbit);
    if (ret < 0) {
        perror("ioctl EVIOCGBIT(0) failed");
        return 0;
    }

    // Check if the EV_KEY bit is set.
    if (evbit[0] & (1 << EV_KEY)) {
        return 1;
    }

    return 0;
}

int main() {
    DIR *dir;
    struct dirent *ent;
    const char *path = "/dev/input/";

    dir = opendir(path);
    if (dir == NULL) {
        perror("Failed to open /dev/input/");
        return EXIT_FAILURE;
    }

    printf("Scanning for keyboard devices...\n");

    while ((ent = readdir(dir)) != NULL) {
        // Look for event files like "event0", "event1", etc.
        if (strncmp(ent->d_name, "event", 5) == 0) {
            char dev_path[256];
            snprintf(dev_path, sizeof(dev_path), "%s%s", path, ent->d_name);

            int fd = open(dev_path, O_RDONLY);
            if (fd < 0) {
                fprintf(stderr, "Could not open %s: %s\n", dev_path, strerror(errno));
                continue;
            }

            if (is_keyboard(fd)) {
                printf("Found potential keyboard device: %s\n", dev_path);

                // Optional: Get the device name for better identification
                char name[256];
                if (ioctl(fd, EVIOCGNAME(sizeof(name)), name) >= 0) {
                    printf("  Device name: %s\n", name);
                }
            }

            close(fd);
        }
    }

    closedir(dir);
    return EXIT_SUCCESS;
}
