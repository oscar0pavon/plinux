#!/bin/bash
#
# freetype, second pass - the same build with harfbuzz available.
#
# freetype and harfbuzz depend on each other: harfbuzz reads fonts through
# freetype, and freetype's autohinter asks harfbuzz which glyphs are related
# so it can hint them consistently. The first pass, packages/freetype.sh,
# builds without harfbuzz so harfbuzz has something to link; this one rebuilds
# once harfbuzz exists.
#
# A separate script only because obj/.packages is keyed on the package name,
# so listing freetype twice in packages/order would skip the second one.

set -e

PLINUX_FREETYPE_PASS=2 exec "$(dirname "$(readlink -f "$0")")/freetype.sh"
