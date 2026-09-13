# Build review

Module: `r8152_oot.ko`, SHA-256
`fe1691622747c106af44f7834675ec75ca3327a797c6bbec394e2998db66e8cb`.

- Build completed with GCC 15.2.0, targeting AArch64 Linux
  `5.4.268-329.ptl4tv.5` and Realtek driver 2.22.1.
- USB structure-offset assertions passed, including `usb_device.bos` at
  `0x3a0`, `usb_device.config` at `0x3a8`, and configuration-count byte at
  `0x399`. These address the field mismatch found in the earlier crash.
- Relative to the extracted TV configuration, olddefconfig changed only
  GCC_VERSION and added CC_CAN_LINK, CC_HAS_AUTO_VAR_INIT, and disabled
  INIT_STACK_ALL. The recovered feature configuration was retained.
- All 128 strong undefined symbols in the actual module ELF were matched to
  PREL32 kernel export records in the decompressed target kernel image.
  Adjacent valid export records were checked to distinguish tables from
  incidental strings/integers. All matched exports have no namespace.
- The module has no `_mcount` import. `__stack_chk_fail` is present and was
  verified as exported by the target kernel.
- The target disables MODVERSIONS. The missing Module.symvers warning did
  not prevent this build; the independent export check confirmed that every
  imported symbol is provided by the kernel itself.

These are static checks. The source revision is `329.ptl4tv.2`, while the
target is `329.ptl4tv.5`; the compiler also differs. The entire ABI and runtime
driver behavior have not been verified. No upload, module load, or USB bind
was performed during this review.
