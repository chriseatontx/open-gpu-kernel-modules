#!/bin/sh
set -eu

TARGET_KERNEL=6.12.107+deb13-amd64
MODULE_SOURCE=${1:-}
DEST="/lib/modules/$TARGET_KERNEL/updates/extra/nvidia-experiment"
STATE_DIR="/var/lib/nvidia-experiment-550"
MANIFEST="$STATE_DIR/installed-files"

[ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }
[ -n "$MODULE_SOURCE" ] && [ -d "$MODULE_SOURCE" ] || { echo "Usage: $0 /absolute/path/to/five-built-ko-files" >&2; exit 2; }
case "$MODULE_SOURCE" in /*) ;; *) echo "The module directory must be absolute." >&2; exit 2 ;; esac

for name in nvidia nvidia-modeset nvidia-drm nvidia-uvm nvidia-peermem; do
    [ -f "$MODULE_SOURCE/$name.ko" ] || { echo "Missing $name.ko" >&2; exit 2; }
done

mkdir -p "$DEST" "$STATE_DIR"
: > "$MANIFEST"
for pair in \
    'nvidia:nvidia-current-open.ko' \
    'nvidia-modeset:nvidia-current-open-modeset.ko' \
    'nvidia-drm:nvidia-current-open-drm.ko' \
    'nvidia-uvm:nvidia-current-open-uvm.ko' \
    'nvidia-peermem:nvidia-current-open-peermem.ko'; do
    src=${pair%%:*}; dst=${pair#*:}; target="$DEST/$dst"
    if [ -e "$target" ]; then echo "Refusing to overwrite $target." >&2; exit 1; fi
    install -m 0644 "$MODULE_SOURCE/$src.ko" "$target"
    echo "$target" >> "$MANIFEST"
done
depmod -a "$TARGET_KERNEL"
echo "Installed only for $TARGET_KERNEL. The fallback kernel was not modified."
echo "To undo: tools/remove-test-modules-6.12.107.sh"
