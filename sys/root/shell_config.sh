export LC_ALL=C.UTF-8
export LANG=C.UTF-8
LFS_TGT=x86_64-lfs-linux-gnu
LFS_TGT32=i686-lfs-linux-gnu
export LFS_TGT
export LFS_TGT32

force_color_prompt=yes

alias ls='ls --color'
alias b='cd ..'
alias t='tar xvf'
alias make='make -j32'
alias m='make'
alias i='make install'
alias c='make clean'
alias fc='cd /root/.mozilla/firefox/of30bpm1.default-default'
alias s='git status'
alias gm='git commit -m'
alias ni='ninja install'
alias r='./start'
alias sw='swordfish > compositor.log 2>&1'
alias test='make test'
alias gc='git clone --depth=1'
alias d='source /scripts/download_package '

alias e='m && i && /root/virtual_machine/start'

PATH=$PATH:/usr/bin
PATH=$PATH:/usr/sbin
PATH=$PATH:/usr/local/bin
PATH=$PATH:/usr/local/sbin
PATH=$PATH:/scripts
PATH=$PATH:/root/plinux/sys/scripts
PATH=$PATH:/opt/rustc/bin
PATH=$PATH:/usr/local/bin/go/bin:
PATH=$PATH:/opt/libreoffice/bin
#export PATH=$PATH:/opt/qt6/bin
#export PATH=$PATH:/opt/qt5/bin
PATH=$PATH:/scripts
PATH=$PATH:/opt/android-studio/bin/
PATH=$PATH:/opt/ziglang
PATH=$PATH:/musl/bin
PATH=$PATH:/opt/maven/bin

PATH=$PATH:/root/sources/lua-language-server/bin
PATH=$PATH:/usr/local/mysql/bin
PATH=$PATH:/usr/local/nginx/sbin
PATH=$PATH:/root/.local/bin

PATH=$PATH:/root/sources/fzf/bin

PATH=$PATH:/opt/texlive/2026/bin/x86_64-linux

export PATH

export LIBSEAT_BACKEND=seatd


TEXLIVE_PREFIX=/opt/texlive/2026/
export TEXLIVE_PREFIX

export XORG_PREFIX=/usr
export XORG_CONFIG="--prefix=$XORG_PREFIX --sysconfdir=/etc \
    --localstatedir=/var"


### The ROCK

export PATH=$PATH:/opt/rocm/bin
export PATH=$PATH:/opt/rocm/llvm/bin
export ROCM_PATH=/opt/rocm/
export LD_LIBRARY_PATH=/usr/lib:/opt/rocm/lib:/opt/rocm/llvm/lib
export HSA_OVERRIDE_GFX_VERSION=10.3.0
export HIP_VISIBLE_DEVICES=0
export HIP_PLATFORM=amd
export PYTORCH_ROCM_ARCH=gfx1030
export USE_ROCM=1
export USE_CUDA=0
export GPU_TARGETS="gfx1030_mod0" 

JAVA_HOME=/opt/jdk
export PATH=$PATH:$JAVA_HOME/bin
export JAVA_HOME

#QT6DIR=/opt/qt6

#export QT6DIR=/opt/qt6

#export QT6PREFIX=/opt/qt6

export QT_PLUGIN_PATH=/opt/qt6/plugins

#export QT_QPA_PLATFORM_PLUGIN_PATH=$QT6DIR/plugins/platforms

export GODOT_SILENCE_ROOT_WARNING=1

export ANDROID_SDK_ROOT=/root/disk/android/sdk/
export ANDROID_SDK=/root/disk/android/sdk/

_JAVA_OPTIONS="-XX:-UsePerfData"
#export _JAVA_OPTIONS


export STEAM_LINUX_RUNTIME_LOG=1
export STEAM_LINUX_RUNTIME_VERBOSE=1

export CCACHE_DISABLE=1
#export USE_CCACHE=1
#export CCACHE_EXEC=/usr/bin/ccache
#export CCACHE_DIR=/ccache/

export GRIM_DEFAULT_DIR=/root/grim

# The editor anything that spawns one will use: git, crontab, less's "v",
# sudoedit. Without it they fall back to whatever they were compiled with,
# which is usually a plain vi that this system does not have under that name
# until vim installs the symlink.
export EDITOR=vim
export VISUAL=vim

# Same idea for anything that pipes output to a pager. Without it the
# fallback is more(1) from util-linux, which cannot scroll backwards.
export PAGER=less

