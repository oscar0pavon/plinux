#set +h


# Escapes sequences
color_name="\033[32m"
white_color="\033[0m"
directory_color="\033[36m"

color_name="\[${color_name}\]"
directory_color="\[${directory_color}\]"
white_color="\[${white_color}"
user="\u"
work_space="\w"
# Bash prompt
#export PS1="\r${color_name}${user}:${directory_color}${work_space}${white_color}$\]"
export PS1="\r${color_name}plinux:${directory_color}${work_space}${white_color}$\]"


# On the workstation this file is a symlink into the repo and the first path
# exists. In the installed image there is no /root/plinux, so build.sh puts
# shell_config.sh next to this file instead. First one found wins.
for shell_config in /root/plinux/sys/root/shell_config.sh \
                    "${HOME:-/root}/shell_config.sh"; do
	if [ -f "${shell_config}" ]; then
		source "${shell_config}"
		break
	fi
done
unset shell_config

