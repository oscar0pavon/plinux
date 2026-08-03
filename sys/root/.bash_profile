
# This file is sourced by bash for login shells.  The following line
# runs your .bashrc and is recommended by the bash info pages.
if [[ -f ~/.bashrc ]]; then
	. ~/.bashrc
fi

if [ "${XDG_RUNTIME_DIR}" ]; then
	if [ -d "${XDG_RUNTIME_DIR}" ]; then
		mkdir "${XDG_RUNTIME_DIR}"
		chmod 0700 "${XDG_RUNTIME_DIR}"
	fi
fi

if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
 init_os
fi
