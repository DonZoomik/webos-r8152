#!/usr/bin/env bash
# Build an experimental module in fresh staging directories. No TV access.
set -euo pipefail

files_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
source_tree=${R8152_KERNEL_SOURCE:-/mnt/c/lg/webOS25 WM_ReNew/linux-and-kdriver-1637/linux-rockhopper}
driver_source=${R8152_DRIVER_SOURCE:-/mnt/c/lg/extract/r8152-v2.22.1}
target_config="$files_dir/tv-5.4.268-329.ptl4tv.5.config"
target_release=5.4.268-329.ptl4tv.5
cross=${R8152_CROSS_COMPILE:-aarch64-linux-gnu-}
compat_cross=${R8152_COMPAT_CROSS_COMPILE:-arm-linux-gnueabihf-}

if [[ -n ${R8152_CC:-} ]]; then
    compiler=$R8152_CC
elif command -v "${cross}gcc-11" >/dev/null 2>&1; then
    compiler="${cross}gcc-11"
else
    compiler="${cross}gcc"
fi

for tool in make flex bison bc python3 "$compiler" "${cross}ld" \
            "${cross}readelf" "${cross}nm" "${compat_cross}gcc" "${compat_cross}ld"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'Required build tool not found: %s\n' "$tool" >&2
        printf 'Ubuntu prerequisites: build-essential gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf binutils-aarch64-linux-gnu binutils-arm-linux-gnueabihf flex bison bc libssl-dev libelf-dev python3\n' >&2
        exit 1
    fi
done
for file in "$source_tree/Makefile" "$target_config" "$files_dir/tv_abi_checks.h" \
            "$driver_source/r8152.c" "$driver_source/compatibility.h" "$driver_source/Makefile"; do
    [[ -r $file ]] || { printf 'Required input not readable: %s\n' "$file" >&2; exit 1; }
done
grep -Eq '^#define[[:space:]]+MODULENAME[[:space:]]+"r8152_oot"' "$driver_source/r8152.c" || {
    printf 'The driver must retain the existing r8152_oot rename.\n' >&2; exit 1;
}
grep -Eq 'obj-m[[:space:]]*:?=[[:space:]]*r8152_oot\.o' "$driver_source/Makefile" || {
    printf 'The driver Makefile must retain the existing r8152_oot module target.\n' >&2; exit 1;
}
grep -q '^CONFIG_ARCH_LG1K=y$' "$target_config"
grep -q '^CONFIG_PINCTRL=y$' "$target_config"
grep -q '^# CONFIG_MODVERSIONS is not set$' "$target_config"

stage=$(mktemp -d /tmp/lg-r8152-o22.XXXXXX)
results=$(mktemp -d "$files_dir/build-result.XXXXXX")
exec > >(tee "$results/build.log") 2>&1
trap 'printf "Build stopped at line %s. Log: %s/build.log\nStaging retained: %s\n" "$LINENO" "$results" "$stage"' ERR

printf 'Staging: %s\nResults: %s\n' "$stage" "$results"
"$compiler" --version
compiler_version=$("$compiler" -dumpfullversion)
if [[ $compiler_version != 11.4.0 ]]; then
    printf 'Compiler differs from TV GCC 11.4.0: %s. This build is for compatibility review.\n' "$compiler_version"
fi
printf 'Copying the source to a path without spaces; this may take several minutes.\n'
mkdir -p "$stage/source" "$stage/build" "$stage/driver"
cp -a "$source_tree/." "$stage/source/"
cp -- "$target_config" "$stage/build/.config"
cp -- "$driver_source/r8152.c" "$driver_source/compatibility.h" \
      "$driver_source/Makefile" "$files_dir/tv_abi_checks.h" "$stage/driver/"
cp -- "$target_config" "$results/tv-original.config"

export PKG_CONFIG_SYSROOT_DIR=/
args=(-C "$stage/source" O="$stage/build" ARCH=arm64
      "CROSS_COMPILE=$cross" "CROSS_COMPILE_COMPAT=$compat_cross"
      "CC=$compiler" LOCALVERSION=-329.ptl4tv.5)

make "${args[@]}" olddefconfig
cp -- "$stage/build/.config" "$results/effective.config"
python3 "$stage/source/scripts/diffconfig" "$target_config" "$stage/build/.config" \
    | tee "$results/config-differences.txt"
make "${args[@]}" modules_prepare

grep -Fqx '#define UTS_RELEASE "5.4.268-329.ptl4tv.5"' \
    "$stage/build/include/generated/utsrelease.h" || {
    printf 'Generated kernel release does not match the intended target.\n' >&2; exit 1;
}

# The header causes a compilation error if the previously incorrect USB field
# offsets still do not match the observed TV layout.
make "${args[@]}" M="$stage/driver" \
    "KCFLAGS=-include $stage/driver/tv_abi_checks.h" modules

module="$stage/driver/r8152_oot.ko"
"${cross}readelf" -h "$module" | tee "$results/elf-header.txt"
"${cross}readelf" -p .modinfo "$module" | tee "$results/module-info.txt"
"${cross}nm" -u "$module" | tee "$results/undefined-symbols.txt"
grep -q 'Machine:.*AArch64' "$results/elf-header.txt"
grep -Fq "vermagic=$target_release " "$results/module-info.txt"
grep -Fq 'name=r8152_oot' "$results/module-info.txt"
if grep -Eq '[[:space:]]_mcount$' "$results/undefined-symbols.txt"; then
    printf 'Unexpected _mcount dependency: review build configuration.\n' >&2
    exit 1
fi
cp -- "$module" "$results/r8152_oot.ko"
sha256sum "$results/r8152_oot.ko" "$results/effective.config"
printf '\nBuilt module and audit files: %s\n' "$results"
printf 'USB layout assertions passed. Review config-differences.txt and build.log before a TV attach test.\n'
