
# This file is sourced by bash for login shells.  The following line
# runs your .bashrc and is recommended by the bash info pages.
if [[ -f ~/.bashrc ]]; then
	. ~/.bashrc
fi

# Wayland requires this to exist and be private before anything starts. It
# used to be set in init_os, which runs after this block, so the outer test
# never passed and the directory was never created here. That went unnoticed
# because /tmp was part of the root filesystem, so a directory made once
# survived every reboot and hid the fact that nothing was making it.
#
# pinit mounts /tmp as a tmpfs now, which is what the specification wants --
# XDG_RUNTIME_DIR must not survive a reboot -- and which means this mkdir is
# load-bearing on every boot rather than only on a fresh image.
# :- keeps a value set by a real session manager if one ever sets it.
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/00-runtime-dir}

# -m sets the mode as it is created, so no separate chmod is needed. This is
# a root-only system, so the mode guards nothing; it is kept because some
# wayland clients complain about a world-accessible runtime directory.
# mkdir is coreutils, which a minimal image does not have yet. Skipping
# quietly is right: nothing that needs this directory can run there either.
if command -v mkdir > /dev/null; then
	mkdir -p -m 0700 "${XDG_RUNTIME_DIR}"
fi

# tty is coreutils too; without it this stays quiet and simply does not
# autostart, which is what you want on a system that has no compositor
if [[ -z $DISPLAY ]] && [[ $(tty 2>/dev/null) = /dev/tty1 ]]; then
 init_os
fi
