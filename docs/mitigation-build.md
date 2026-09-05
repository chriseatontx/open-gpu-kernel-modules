# Building the experiment with kernel mitigation flags

September 5, 2026: the targeted build completed with **zero objtool warnings**,
zero compiler errors, and 79 compiler warnings. No modules were installed or
loaded. This is build validation, not hardware validation.

## Why the original build warned

The target Debian kernel configuration enables `CONFIG_MITIGATION_RETHUNK=y`
and `CONFIG_X86_KERNEL_IBT=y`. NVIDIA's core Makefiles enable branch protection
when the compiler supports it, but do not request external return thunks.
The default core build also contains `.eh_frame` unwind metadata. The captured
ENDBR warnings reference that section.

Debian's 550.163.01-2 packaging contains `debian/patches/kernel-flags.patch`,
which proposes `-mfunction-return=thunk-extern`, but comments it out in the
patch series. Its changelog explains that the flag breaks compatibility with
kernels built without it. This experiment therefore uses an explicit build
profile for the verified target kernel; it does not change the default flags
for every kernel.

The original Debian packaged-tree build also emitted mitigation warnings.
They were not specific to the GitHub source build. Earlier counts from the
parallel logs were approximate because messages interleaved; the reported
"other objtool" category should not be read as additional distinct defects.

## Build profile

Run from this branch's repository root in an isolated workspace, as an ordinary
user. These commands remove local build products and rebuild them; they do not
install anything. Keep any earlier artifacts/logs you want before cleaning.

First verify the intended target configuration:

```sh
grep -E '^CONFIG_(MITIGATION_RETHUNK|X86_KERNEL_IBT)=y$' \
  /usr/src/linux-headers-6.12.107+deb13-amd64/.config
```

Both settings were enabled on the tested machine. Use only the verified target:

```sh
make clean KERNEL_UNAME=6.12.107+deb13-amd64
EXTRA_CFLAGS='-mfunction-return=thunk-extern -fno-asynchronous-unwind-tables -fno-unwind-tables' \
  make --output-sync=target -j4 modules KERNEL_UNAME=6.12.107+deb13-amd64 \
  > build-mitigated.log 2>&1
echo "build exit status: $?"
```

Set `EXTRA_CFLAGS` in the **environment**, before `make`. Supplying it as a make
command-line assignment overrides the kernel-interface Makefile's additions,
including required header search paths, causing missing-header errors. This
was encountered and corrected during the experiment. The successful run reused
the core objects compiled with these flags during that first attempt and then
compiled and linked the kernel interface with the corrected variable scope.

The three flags serve different purposes:

| Flag | Purpose |
| --- | --- |
| `-mfunction-return=thunk-extern` | Generate returns through the external kernel return thunk expected by this target |
| `-fno-asynchronous-unwind-tables` | Omit compiler-generated asynchronous unwind tables; also used by the target kernel's x86 Makefile |
| `-fno-unwind-tables` | Omit remaining compiler-generated unwind tables from the core objects |

The profile leaves objtool validation and the kernel's mitigation configuration
enabled. It does not declare objects nonstandard or suppress their warnings.
Do not use these artifacts on a different kernel or apply this profile globally
without checking that kernel's requirements.

## Evidence

- Final make exit status: 0; all five modules generated.
- Module version: 550.163.01; vermagic: 6.12.107+deb13-amd64.
- Objtool warning count in the synchronized final log: 0.
- `readelf -S` confirms neither rebuilt core object contains `.eh_frame`.
- `nm -u` confirms both core objects reference `__x86_return_thunk`.
- The return-thunk and ENDBR warnings disappeared with this profile. This
  supports the build-settings explanation; it does not prove runtime behavior.
- [Module hashes and structured results](build-6.12.107-mitigated-results.json).

Compiler warnings remaining in the final log:

| Type | Count |
| --- | ---: |
| Missing prototypes | 52 |
| Empty conditional bodies | 25 |
| Enum/integer declaration mismatch | 1 |
| `BITS_TO_BYTES` macro redefinition | 1 |

## Remaining work

Review the remaining compiler warnings and the PCI resize resource semantics.
The source patch still unconditionally targets a four-argument API. Recovery
boot verification, a kernel-specific installation/removal manifest, initramfs
preparation, and hardware testing remain outstanding. Compilation and metadata
checks do not test module loading, GPU initialization, or runtime mitigations.

## Sources

- [Debian 550.163.01-2 packaging archive](https://deb.debian.org/debian/pool/contrib/n/nvidia-open-gpu-kernel-modules/nvidia-open-gpu-kernel-modules_550.163.01-2.debian.tar.xz): patch, patch-series selection, and changelog examined locally.
- Target kernel headers: `arch/x86/Makefile` sets the return-thunk flag under
  `CONFIG_MITIGATION_RETHUNK` and disables asynchronous unwind tables.
- [Related NVIDIA report #1077](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1077).
