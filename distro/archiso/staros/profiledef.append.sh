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
  ["/usr/local/libexec/staros-boot-check"]="0:0:755"
)
