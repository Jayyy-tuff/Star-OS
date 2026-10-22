# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck shell=bash disable=SC2034
#
# Appended to the end of releng's profiledef.sh by scripts/build-iso.sh, so
# these assignments override releng's values. mkarchiso sources the result.

iso_name="staros"
iso_label="STAROS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Star OS project <https://github.com/Jayyy-tuff/Star-OS>"
iso_application="Star OS live (prototype)"
file_permissions+=(
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-staros-live"]="0:0:440"
  ["/usr/local/bin/startstaros"]="0:0:755"
  ["/usr/local/libexec/staros-boot-check"]="0:0:755"
  ["/usr/local/libexec/staros-session-report"]="0:0:755"
)
# Replaces %KERNEL_PARAMS% in every boot entry (scripts/build-iso.sh checks
# them): the copy-on-write RAM disk may grow to half the memory, so per-user
# Flatpak apps from Sun Store fit on the live medium (M0.3).
kernel_params_x86_64="cow_spacesize=50%"
