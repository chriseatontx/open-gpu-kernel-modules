# Experimental fix: NVIDIA 550 and Debian 6.12 PCI API compatibility

Status as of September 5, 2026: **compilation prototype; no hardware validation**.

Update: a [target-specific build profile](mitigation-build.md) now produces all
five modules with zero objtool warnings. The original build results below are
retained as history; 79 compiler warnings and runtime validation remain.
This is an independent experiment, not an NVIDIA or Debian release.

## Problem

Debian's `nvidia-open-kernel-dkms` version `550.163.01-2` fails to build with
`6.12.107+deb13-amd64` headers at this call:

```c
pci_resize_resource(pci_dev, NV_GPU_BAR1, requested_size);
```

The compiler reports:

```text
nv-pci.c:237:9: error: too few arguments to function 'pci_resize_resource'
```

The installed newer headers declare a fourth argument, `int exclude_bars`.
Failure during a DKMS build can prevent a kernel package from finishing its
configuration. The upstream report describes the same failure starting with
Debian's 6.12.100 headers; this experiment directly tested 6.12.107.

## Branch base and code change

- Upstream release: NVIDIA `550.163.01`.
- Base commit: `23e9e7621487fe632040a370249f690a456967dd`.
- Branch: `fix/550-pci-resize-debian-6.12`.
- Changed source: `kernel-open/nvidia/nv-pci.c`, in `nv_resize_pcie_bars()`.

```diff
-    r = pci_resize_resource(pci_dev, NV_GPU_BAR1, requested_size);
+    r = pci_resize_resource(pci_dev, NV_GPU_BAR1, requested_size, 0);
```

The kernel documentation defines the new parameter as a mask of BARs that
should not be released. Passing zero excludes none. This supplies the missing
argument and allows the compilation test to complete.

This does **not** establish that zero preserves all resource-allocation behavior
of the older kernel implementation. Review the new API's handling of other BARs
and the driver's existing resource release/reassignment sequence before a live
test. Runtime correctness remains unverified.

This intentionally narrow prototype uses the four-argument API unconditionally.
It is unsuitable for older three-argument headers, including 6.12.90. A general
fix should add compile-time API detection using NVIDIA's conftest machinery,
rather than assume all kernels with the same major/minor version share an API.
Do not register this prototype for automatic DKMS builds across all kernels.

## Validation record

The initial local test used a copy of the installed **Debian package build tree**,
containing Debian's kernel interface source and prebuilt core objects. That initial test did
not compile every file in this GitHub repository. Debian packaging also contains
compatibility changes that the upstream release alone may lack.

| Check | Result |
| --- | --- |
| Unchanged Debian 550.163.01-2 tree, headers 6.12.107 | Failed with the missing-argument error; make exit status 2 |
| Same tree with the one-line change | Build completed; make exit status 0 |
| Generated modules | nvidia, nvidia-modeset, nvidia-drm, nvidia-uvm, nvidia-peermem |
| Module metadata | Version 550.163.01; vermagic targets 6.12.107+deb13-amd64 |
| Full upstream source build | Completed at commit `1c12344303bd22a68e62d526024a025d18600b81`; exit status 0, with unresolved warnings |
| Installation or module loading | Not performed |
| Desktop, CUDA, suspend/resume, GPU stability | Not tested |

The compilation command, run as an ordinary user inside the copied Debian
module tree, was:

```sh
make -j4 modules KERNEL_UNAME=6.12.107+deb13-amd64
```

Local original logs are retained separately. This public record omits machine
identifiers, home-directory paths, boot configuration, and recovery archives.

## Reproducing the packaged-tree compilation test

Use a disposable workspace on a system with the matching package source and
kernel headers already present. The following commands copy files and compile;
they do not install or load the result. Allow several hundred megabytes of
workspace storage and use a new empty directory.

```sh
mkdir nvidia-550-experiment
cd nvidia-550-experiment
cp -a /usr/src/nvidia-current-open-550.163.01 baseline
cp -a baseline patched

# Expected failure on the affected headers; preserve its log and exit code.
make -C baseline -j4 modules KERNEL_UNAME=6.12.107+deb13-amd64 > baseline.log 2>&1
echo "baseline exit status: $?"
```

In `patched/nvidia/nv-pci.c`, apply the one-line change shown above. Then:

```sh
make -C patched -j4 modules KERNEL_UNAME=6.12.107+deb13-amd64 > patched.log 2>&1
echo "patched exit status: $?"
modinfo patched/nvidia.ko
```

The path inside the Debian package is `nvidia/nv-pci.c`; the corresponding
upstream path includes the `kernel-open/` prefix. The subsequent full upstream source build completed without additional
source patches, but emitted substantial warnings (see below). Keep firmware and userspace components matched to 550.163.01.

## Full GitHub source build result

The branch at commit `1c12344303bd22a68e62d526024a025d18600b81` was built
from the repository root, including the core code that the Debian package
provides as prebuilt objects:

```sh
make -j4 modules KERNEL_UNAME=6.12.107+deb13-amd64
```

The build completed with exit status 0 using GCC 14.2.0 (Debian 14.2.0-19)
and GNU Make 4.4.1. All five modules report version 550.163.01 and a vermagic
for 6.12.107+deb13-amd64. No additional source changes were needed for this
compilation. See the [machine-readable result and module hashes](build-6.12.107-results.json).
Hashes identify these local build artifacts; they are not signed release checksums.

**The build was not warning-free.** The captured log contains 79 compiler
warning lines, 11,343 objtool naked-return warnings in a MITIGATION_RETHUNK
build, 158 objtool ENDBR warnings, and 44 other objtool warnings. Counts are
log occurrences, not unique defects. These require investigation of the build
flags and kernel mitigation requirements before loading these artifacts.
Successful linking does not establish runtime safety or correct mitigations.
The complete log remains local; this public summary includes no recovery files.

At the time of this build record, no modules were installed or loaded and no
boot/package configuration had changed. A later live test is recorded in
`api-aware-build.md`.

## Recovery and live-test plan

At the compilation stage, stopping requires no system rollback: discard the
workspace or retain it for another attempt. A Git revert changes source code;
it does not undo a driver installation.

Before installing anything:

1. Verify a working older kernel and GPU module can be selected from the boot
   menu. The local fallback is `6.12.90+deb13-amd64`; leave its modules intact.
2. Confirm physical console access and prepare rescue media. Keep instructions
   available on another device. A freeze may require a reset and can lose
   unsaved work.
3. Inspect the real boot entries and saved-default behavior. Establish a tested
   one-time boot procedure that preserves the working default.
4. Prepare exact install and undo manifests limited to the test kernel, with
   backups of every replaced file. Preserve Debian's module naming and aliases.
5. Inspect package configuration and the test kernel's initramfs. The local
   6.12.107 kernel is partially configured and lacks an initramfs; successful
   module compilation alone does not make it ready to boot.
6. Review BAR handling, complete the relevant build validation, and determine
   signing requirements if Secure Boot is enabled.

If a live test fails, reboot into the verified older kernel. Remove only the
experimental files identified in the installation manifest, restore affected
files, and regenerate the affected metadata/initramfs as needed. Use rescue
media if the boot menu cannot be reached. Exact commands depend on the verified
installation method; they have not yet been prepared or tested.

## Next validation steps

- Review resource-allocation semantics of the fourth argument.
- Review the remaining 79 compiler warnings after the mitigation build profile
  eliminated the objtool warnings.
- Implement API detection and test both old and new headers before treating the
  change as a general compatibility fix.
- Prepare and verify the installation/rollback procedure before reboot testing.
- Record hardware test results, including kernel, GPU, firmware/userspace
  version, desktop behavior, GPU workloads, and kernel error logs.

## Change history

| Date | Change | Evidence/status |
| --- | --- | --- |
| 2026-09-05 | Add the fourth argument to `pci_resize_resource()` | Debian packaged-tree compilation passes on 6.12.107; runtime untested |
| 2026-09-05 | Publish experiment scope and recovery plan | No installed system changes |
| 2026-09-05 | Complete full GitHub source build on 6.12.107 | Five modules generated; initial objtool warnings recorded; no installation |
| 2026-09-05 | Test target-specific mitigation flags | Zero objtool warnings; 79 compiler warnings remain; no installation |

Future changes should update this record with their reason, exact test scope,
results, and remaining limitations. Keep source changes in reviewable commits.

## References

- [NVIDIA issue #1272](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1272)
- [Linux PCI API documentation](https://www.kernel.org/doc/html/latest/driver-api/pci/pci.html)
- [Upstream 550.163.01 source](https://github.com/NVIDIA/open-gpu-kernel-modules/tree/550.163.01)
- [Debian source package tracker](https://tracker.debian.org/pkg/nvidia-open-gpu-kernel-modules)
