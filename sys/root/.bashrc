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
export PS1="\r${color_name}${user}:${directory_color}${work_space}${white_color}$\]"


source /root/plinux/sys/root/shell_config.sh

