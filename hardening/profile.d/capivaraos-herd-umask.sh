# shellcheck shell=sh
# CapivaraOS HERD — restrictive umask for login sessions.
# 027: new files are not readable by "others" (group can read).
# Covers interactive logins (ssh/console), which is how HERD is used (headless).
umask 027
