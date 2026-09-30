#!/system/bin/sh
#
# Verify the E2BIG boundary that default_network_validated() used to hit.
#
# Android's mksh refuses to exec a program when a single argument exceeds
# MAX_ARG_STRLEN (128 KiB). `dumpsys connectivity` on modern Android is
# routinely larger than that, so code like
#
#   connectivity_dump="$(dumpsys connectivity)"
#   printf '%s\n' "$connectivity_dump" | grep -q PATTERN
#
# fails with "/system/bin/printf: Argument list too long" on the real device.
# A host-side test cannot reproduce this, because Linux (glibc) is far more
# permissive about a single argument than Android's shell is.
#
# Run this on a rooted device or over adb shell:
#
#   adb push scripts/verify_e2big_boundary.sh /data/local/tmp/
#   adb shell sh /data/local/tmp/verify_e2big_boundary.sh
#
# It does not modify anything; it only measures the boundary and confirms the
# file-redirection pattern used by default_network_validated() stays safe.

set -u

LIMIT=131072
failures=0

note() {
  printf '%s\n' "$*"
}

fail() {
  printf 'verify: FAIL %s\n' "$*" >&2
  failures=$((failures + 1))
}

# Report the largest single argument this shell can pass to printf.
largest_ok=0
smallest_fail=0
n=1
while [ "$n" -le 262144 ]; do
  payload="$(awk -v n="$n" 'BEGIN { s = ""; for (i = 0; i < n; i++) s = s "x"; print s }')"
  if printf '%s' "$payload" >/dev/null 2>&1; then
    largest_ok="$n"
    n=$((n * 2))
  else
    smallest_fail="$n"
    break
  fi
done

if [ "$smallest_fail" -eq 0 ]; then
  note "verify: this shell accepted 256 KiB in one argument; E2BIG boundary not observable"
  note "verify: SKIP argument-size assertions"
else
  note "verify: largest single argument accepted = $largest_ok bytes"
  note "verify: smallest single argument rejected  = $smallest_fail bytes"

  if [ "$smallest_fail" -gt "$LIMIT" ]; then
    fail "expected the boundary at or below $LIMIT bytes, saw $smallest_fail"
  fi
  if [ "$largest_ok" -ge "$smallest_fail" ]; then
    fail "boundary search is inconsistent ($largest_ok >= $smallest_fail)"
  fi

  # Exactly at the documented boundary.
  at_limit="$(awk -v n="$LIMIT" 'BEGIN { s = ""; for (i = 0; i < n; i++) s = s "x"; print s }')"
  if printf '%s' "$at_limit" >/dev/null 2>&1; then
    fail "a $LIMIT byte argument was accepted; expected MAX_ARG_STRLEN rejection"
  fi
fi

note ""

# Confirm the file-redirection pattern survives a dumpsys that is larger than
# the argument boundary, and that the old variable-passing pattern does not.
work="$(mktemp -d "${TMPDIR:-/tmp}/fuck_ttnet_e2big.XXXXXX")" || {
  printf 'verify: cannot create temp dir\n' >&2
  exit 1
}
trap 'rm -rf "$work"' EXIT HUP INT TERM

fake="$work/dumpsys.txt"
{
  i=0
  while [ "$i" -lt 2400 ]; do
    printf '  filler record %s      NetworkRequest [ LISTEN id=1, [ Capabilities: INTERNET Uid: 1000 ] ]\n' "$i"
    i=$((i + 1))
  done
  printf '%s\n' '  NetworkAgentInfo{network{100} handle{1} ni{WIFI CONNECTED}}'
  printf '%s\n' '    nc{[ Transports: WIFI Capabilities: INTERNET&TRUSTED&VALIDATED ]}'
} > "$fake"

fake_size="$(wc -c < "$fake" | tr -d ' ')"
note "verify: synthetic dumpsys size = $fake_size bytes"

if [ "$fake_size" -le "$LIMIT" ]; then
  fail "synthetic dumpsys ($fake_size) must exceed $LIMIT to be meaningful"
fi

# The old pattern: whole blob in a variable, then passed as an argument.
huge="$(cat "$fake")"
old_out="$(printf '%s\n' "$huge" | grep -q 'VALIDATED' && printf yes || printf no)"
if [ "$old_out" != "yes" ]; then
  note "verify: old variable-passing pattern returned '$old_out' for a $fake_size byte dumpsys"
else
  note "verify: WARNING old variable-passing pattern still worked for a $fake_size byte dumpsys"
fi

# The new pattern: keep it on disk, let the tools read the file.
new_out="$(grep -q 'VALIDATED' "$fake" && printf yes || printf no)"
if [ "$new_out" != "yes" ]; then
  fail "file-redirection pattern failed on a $fake_size byte dumpsys (got '$new_out')"
else
  note "verify: file-redirection pattern handled a $fake_size byte dumpsys correctly"
fi

# When the boundary is observable, the old pattern must fail at this size.
# That is the regression this script exists to prove.
if [ "$smallest_fail" -ne 0 ] && [ "$fake_size" -ge "$smallest_fail" ]; then
  if [ "$old_out" = "yes" ]; then
    fail "old variable-passing pattern survived a $fake_size byte dumpsys, but the shell rejects arguments at $smallest_fail bytes; this script is no longer proving the bug"
  else
    note "verify: reproduced the original bug - variable passing lost the payload, file redirection did not"
  fi
fi

note ""
if [ "$failures" -eq 0 ]; then
  note "verify: all checks passed"
  exit 0
fi

note "verify: $failures check(s) failed"
exit 1
