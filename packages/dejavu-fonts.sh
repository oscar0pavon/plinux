#!/bin/bash
#
# dejavu-fonts - a font, so text is text.
#
# fontconfig, pango and cairo are all installed and none of them can draw a
# character without a font file to draw it from: an empty /usr/share/fonts
# means sway comes up with every label rendered as a box. This is the smallest
# thing that fixes that.
#
# DejaVu because it covers Latin, Greek, Cyrillic and enough punctuation for a
# terminal, and because it has a real monospace face. Data only -- nothing
# links it, nothing runs.

set -e

. "$(dirname "$(readlink -f "$0")")/common.sh"

directory=$(unpack 'dejavu-fonts-ttf-*.tar.bz2' 'dejavu-fonts-ttf-2.37')
cd "${directory}"

install -d "${build_directory}/usr/share/fonts/dejavu"
install -m 644 ttf/*.ttf "${build_directory}/usr/share/fonts/dejavu/"

# The tarball carries its own fontconfig rules, which fontconfig itself does
# not ship: the 57-* files are what make "sans-serif" and "monospace" resolve
# to DejaVu rather than to whatever sorts first, and the 20-* ones turn off
# hinting at sizes where it does more harm than good.
#
# Installed into conf.avail and symlinked from conf.d, which is the split
# fontconfig expects: available and enabled are different questions.
install -d "${build_directory}/usr/share/fontconfig/conf.avail"
install -d "${build_directory}/etc/fonts/conf.d"
install -m 644 fontconfig/*.conf "${build_directory}/usr/share/fontconfig/conf.avail/"

for rule in fontconfig/*.conf; do
  name=$(basename "${rule}")
  ln -sfn "../../../usr/share/fontconfig/conf.avail/${name}" \
          "${build_directory}/etc/fonts/conf.d/${name}"
done

# The cache is built on the target, not here: fc-cache would write the build
# machine's paths. pinit does not run it, so the first pango lookup pays for
# the scan. That is a one-off on a directory with sixteen files in it.
