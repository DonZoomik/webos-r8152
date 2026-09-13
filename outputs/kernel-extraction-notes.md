# LG OLED65C41LA kernel configuration recovery

Both 50 MiB kernel partition copies decode to the same ARM64 kernel image.

```text
Linux version 5.4.268-329.ptl4tv.5 (oe-user@oe-host) (gcc version 11.4.0 (GCC)) #1 SMP PREEMPT Mon Sep 8 05:02:25 UTC 2025
```

The image uses LG's LZ4P container: 32-byte header, 141 little-endian block
lengths, then independent raw LZ4 blocks. The compressed image occupies
21,112,549 bytes and expands to 36,839,936 bytes. Each block's decoded length
and the ARM64 Image magic were checked. Embedded configuration extraction
validated the gzip stream including its checksum and the IKCFG_ED end marker.

SHA-256:

| Artifact | Hash |
|---|---|
| Partition 21 full dump | `06d5e5e150e31d82efc5d953ade69b04ea3d7a3ca1e6bfc377b63bafcb4b3895` |
| Partition 22 full dump | `9efa1d65f43d53badc29759770ebb2a3cb318de70e4bd3b8b35794f984ca290a` |
| Either decompressed kernel | `6e474a337fa1629c44b25a95682c0f5d3d717697b52c4a468a143740eb470572` |
| Either extracted configuration | `d00058ca1805fe387a9589834f56aed501a262d96de318f59566e78ac8b049ab` |

The recovered configuration has 677 differing values relative to the failed
K25 build, treating absent options as disabled. Notable differences:

| Option | Failed build | Actual TV |
|---|---|---|
| ARCH_LG1K | disabled | enabled |
| ARCH_K25 / ARCH_RTK2875Q | enabled | disabled |
| PINCTRL | disabled | enabled |
| NET_NS | enabled | disabled |
| NR_CPUS | 256 | 4 |
| FUNCTION_TRACER | enabled | disabled |
| USB_RTL8152 / USB_NET_CDC_NCM | disabled | enabled |

The TV enables IKCONFIG but disables IKCONFIG_PROC, explaining why there was
no `/proc/config.gz`. MODVERSIONS is disabled. The complete configuration is
preserved unchanged in `tv-5.4.268-329.ptl4tv.5.config`.

The local WM source manifest identifies `submissions/329.ptl4tv.2`. It remains
an approximate source revision, now paired with the exact target configuration.
`build-r8152-o22.sh` stages fresh copies, preserves the existing driver rename
and PCI guard patch, and checks the USB structure offsets implicated in the
saved crash. These assertions do not verify the entire kernel/module ABI.

The script requires WSL/Linux and cross compilers for AArch64 and ARM32. The
ARM32 compiler is needed by the target's enabled COMPAT_VDSO during kernel
preparation. It prefers an installed `aarch64-linux-gnu-gcc-11`; otherwise it
uses `aarch64-linux-gnu-gcc` and reports the compiler difference. Overrides:
`R8152_CC`, `R8152_CROSS_COMPILE`, and `R8152_COMPAT_CROSS_COMPILE`.

The script does not connect to the TV or install/load a module. Its actual
Linux build has not been run from this Windows session.
