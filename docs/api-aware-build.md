# API-aware compatibility build

September 5, 2026. The branch now detects the `pci_resize_resource()` API at
build time and selects the matching call and resource-management path.

## Why this change is needed

The function has three arguments in the working `6.12.90+deb13-amd64` headers
and four arguments in the affected `6.12.107+deb13-amd64` headers. The fourth
argument is an `exclude_bars` bit mask. Stable kernel point releases can carry
this API change, so version-number checks are not sufficient.

## Implementation

`kernel-open/conftest.sh` compiles a function-pointer-style declaration to
detect the four-argument signature and records
`NV_PCI_RESIZE_RESOURCE_HAS_EXCLUDE_BARS` in the generated conftest definitions.
`kernel-open/nvidia/nv-pci.c` then does the following:

- With the new API, leaves the existing BAR assignments in place for the kernel
  to save, releases neither BAR in the caller, and passes a mask that allows
  BAR1 and BAR3 to move while excluding other BARs.
- With the old API, retains the original explicit BAR1/BAR3 release and the
  three-argument call.

This matters because the new kernel helper itself saves and releases resources,
reassigns bridge resources, and restores the old configuration on failure. The
caller must not pre-release those resources or the helper loses the original
state it is designed to restore. The target implementation documents that the
exclude mask controls which BARs may remain unreleased during reassignment.

The source also fixes two build-only warnings without changing runtime intent:

- Match the `nv_encode_caching()` declaration to its `nv_memory_type_t`
  definition.
- Rename the private SPDM `BITS_TO_BYTES` macro to avoid colliding with the
  kernel header's macro while preserving the original floor division.
- Make no-op memory-debug macros explicit empty statements, avoiding misleading
  empty-body warnings when memory debugging is disabled.

## Cross-kernel validation

Both builds used the target-specific mitigation environment described in
`mitigation-build.md`:

```sh
EXTRA_CFLAGS='-mfunction-return=thunk-extern -fno-asynchronous-unwind-tables -fno-unwind-tables' \
  make --output-sync=target -j4 modules KERNEL_UNAME="$kernel"
```

| Target | Detected API | Build result | Objtool warnings |
| --- | --- | --- | ---: |
| `6.12.90+deb13-amd64` | Three arguments | Exit status 0; five modules | 0 |
| `6.12.105+deb13-amd64` | Four arguments | Exit status 0; five modules | 0 |
| `6.12.107+deb13-amd64` | Four arguments | Exit status 0; five modules | 0 |

The final logs still contain the existing compiler warnings for missing
prototypes in test/helper code and related source warnings. They do not stop
the build. See the per-run logs retained locally. No module was installed or
loaded, and no package, initramfs, or boot configuration changed.

## What this does not prove

Compilation proves that both API forms are accepted and that the two caller
paths can link. It does not prove BAR assignment succeeds on this machine,
that the GPU initializes, or that suspend/resume and CUDA workloads work. A
live test requires a kernel-specific installation manifest, verified fallback
boot, and exact rollback steps. Keep the working `6.12.90` kernel intact.

## Kernel-scoped installation scripts

The `tools/` directory contains scripts that deliberately target only the
tested `6.12.105+deb13-amd64` or `6.12.107+deb13-amd64` kernels. Set
`NVIDIA_TEST_KERNEL` to select one; `6.12.90` is explicitly rejected. The
installer expects five uncompressed `.ko` files,
refuses to overwrite an existing test-kernel file, records every installed
path, and runs `depmod` only for that kernel. The remover accepts only paths
under its own test directory and removes only those files. Neither script
touches the `6.12.90` DKMS installation.

These scripts have not been run. Before using them, verify the boot menu and
initramfs, inspect module signatures and aliases, and retain the working
kernel. Example invocation after review:

```sh
sudo NVIDIA_TEST_KERNEL=6.12.105+deb13-amd64 \
  tools/install-test-modules-6.12.107.sh /absolute/path/to/five-built-ko-files
sudo NVIDIA_TEST_KERNEL=6.12.105+deb13-amd64 \
  tools/remove-test-modules-6.12.107.sh
```

The scripts do not install userspace libraries, create a DKMS registration, or
change the boot default. A live test still requires a one-time boot into
`6.12.107`; on failure, select `6.12.90` from the physical boot menu first.

## Local boot-readiness check

On the test machine, `6.12.90+deb13-amd64` is installed with a valid initramfs
and the five existing Debian NVIDIA modules under its DKMS directory. The
running driver is active from that installation. The `6.12.107+deb13-amd64`
image is present but its package is half-configured and no corresponding
`initrd.img-6.12.107+deb13-amd64` exists. It is therefore not ready for a live
test. No package repair, initramfs generation, GRUB change, module installation,
or reboot has been performed.

The protected `/boot/grub/grub.cfg` could not be read without the user's sudo
password. Verify the menu entries locally before proceeding; do not assume that
the saved-default settings select the fallback after a test reboot.

## References

- [Linux PCI API](https://www.kernel.org/doc/html/latest/driver-api/pci/pci.html)
- [Linux 6.12 PCI implementation](https://github.com/gregkh/linux/blob/v6.12.107/drivers/pci/setup-bus.c)
- [NVIDIA issue #1272](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1272)
