# Modified Realtek r8152 v2.22.1 source

This directory contains the source files used to build the published
`r8152_oot.ko` for the LG O22 TV kernel `5.4.268-329.ptl4tv.5`.

It derives from Realtek's r8152 v2.22.1 package dated 2026-06-03. The Realtek
source files retain their own licensing notices; the repository-level MIT
license applies to the surrounding project files and O22-specific additions,
not to third-party code under its own license.

O22-specific changes from the vendor package:

- `r8152.c`: module/USB-driver name changed from `r8152` to `r8152_oot`, so it
  can coexist with the built-in driver that cannot be unloaded.
- `r8152.c`: `rtl_hc_support_sg()` is conditional on `CONFIG_PCI`; the O22
  kernel has no PCI bus, so the non-PCI implementation returns zero.
- `Makefile`: builds `r8152_oot.ko` from `r8152.o` and removes `-pg` from both
  compilation paths. Removing `-pg` avoids the missing `_mcount` import on the
  TV kernel.

No kernel-source file was edited. The build uses the O22 ABI-check header and
the exact `.config` extracted from the running TV image; see `outputs/`.

Only source/package files are included here. Generated objects, `.cmd` files,
old test modules, and host udev rules are intentionally omitted.

Do not follow `ReadMe.txt`'s ordinary-Linux `make install` procedure on a TV.
It attempts actions that assume a mutable module tree and an unloadable in-tree
driver. Use the project build script and the O22-specific load/bind procedure
instead.
