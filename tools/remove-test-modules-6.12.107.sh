#!/bin/sh
set -eu

TARGET_KERNEL=${NVIDIA_TEST_KERNEL:-6.12.107+deb13-amd64}
STATE_DIR="/var/lib/nvidia-experiment-550"
MANIFEST="$STATE_DIR/installed-files"

[ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }
[ "$TARGET_KERNEL" = 6.12.105+deb13-amd64 ] || [ "$TARGET_KERNEL" = 6.12.107+deb13-amd64 ] || { echo "Only tested 6.12.105 or 6.12.107 may be targeted; 6.12.90 is protected." >&2; exit 2; }
[ -f "$MANIFEST" ] || { echo "No experimental installation manifest found." >&2; exit 2; }

while IFS= read -r path; do
    case "$path" in
        "/lib/modules/$TARGET_KERNEL/updates/extra/nvidia-experiment/"*) [ -f "$path" ] && rm -- "$path" ;;
        *) echo "Unexpected manifest path: $path" >&2; exit 1 ;;
    esac
done < "$MANIFEST"

depmod -a "$TARGET_KERNEL"
rmdir "/lib/modules/$TARGET_KERNEL/updates/extra/nvidia-experiment" 2>/dev/null || true
rm -- "$MANIFEST"
rmdir "$STATE_DIR" 2>/dev/null || true
echo "Removed experimental modules only from $TARGET_KERNEL."
