# pinit

A small init (PID 1) for plinux.

Mounts the filesystems, brings up the network, starts a getty on each console,
then reaps orphans for the rest of the system's life.

Threads are used only where they pay for themselves. `fork` + `exec` is already
concurrent, so program launches are plain forks. Of the mounts, only the block
devices get a thread: their superblock read and journal recovery run outside
`namespace_sem` and genuinely overlap, while pseudo-filesystems cost microseconds
and serialise on that lock anyway.

All signals are blocked at startup and collected with `sigwait`:

```sh
kill -2  1    # SIGINT,  reboot
kill -12 1    # SIGUSR2, poweroff
```

## Build

    make

The binary is static against musl and packed with UPX.
