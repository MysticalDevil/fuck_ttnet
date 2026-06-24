#!/system/bin/sh

# Intentionally empty.
#
# Do not patch TikTok data from post-fs-data. This stage is on the critical boot
# path, and TikTok's TTNet server.json can be a very long single-line file.
# Heavy processing here can delay or block boot. Patching is done from
# service.sh, which runs later and backgrounds its work.
