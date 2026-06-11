#!/bin/bash

# android12-5.10 GKI Kernel Build Script

set -e

# Error handler
trap 'echo "Build failed at line $LINENO. Exit code: $?" >&2' ERR

# ── Environment setup ────────────────────────────────────────────────────────
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export KBUILD_BUILD_USER="Whiskiesweet"
export KBUILD_BUILD_HOST="Azure-vR4"

# ── Clang toolchain ──────────────────────────────────────────────────────────
if [ -z "$CLANG_PATH" ]; then
    echo "ERROR: CLANG_PATH is not set. Did you run this from the workflow?" >&2
    exit 1
fi
export PATH="${CLANG_PATH}/bin:${PATH}"
echo "CLANG_VARIANT : '${CLANG_VARIANT}'"
echo "Toolchain path : $CLANG_PATH"
echo "Clang version  : $("$CLANG_PATH/bin/clang" --version | head -n1)"

echo "=== Stripping EXTRAVERSION from Makefile ==="
BEFORE_EXTRA=$(grep "^EXTRAVERSION" Makefile || echo "(tidak ditemukan)")
sed -i 's/^EXTRAVERSION[[:space:]]*=.*/EXTRAVERSION =/' Makefile
echo "  Sebelum : $BEFORE_EXTRA"
echo "  Sesudah : $(grep '^EXTRAVERSION' Makefile)"

# ── Polly availability check ─────────────────────────────────────────────────
POLLY_FLAGS=""
if "$CLANG_PATH/bin/clang" -mllvm -polly -x c /dev/null -o /dev/null 2>/dev/null; then
    echo "Polly : available — enabling loop optimizations"
    POLLY_FLAGS="-mllvm -polly \
-mllvm -polly-run-dce \
-mllvm -polly-run-inliner \
-mllvm -polly-reschedule=1 \
-mllvm -polly-loopfusion-greedy=1 \
-mllvm -polly-vectorizer=stripmine \
-mllvm -polly-detect-keep-going"
else
    echo "Polly : not available in this toolchain — skipping"
fi

# ── KCFLAGS ──────────────────────────────────────────────────────────────────
export KCFLAGS="-w -march=armv8.2-a+crypto+fp16+dotprod -mtune=cortex-a55 \
-fno-semantic-interposition \
${POLLY_FLAGS}"

# ── NTSYNC SELinux policy injection ─────────────────────────────────────────
RULES_FILE="drivers/kernelsu/selinux/rules.c"
if [ -f "$RULES_FILE" ]; then
    echo "Injecting NTSYNC SELinux rules into KernelSU..."
    sed -i '/rcu_assign_pointer(selinux_state.policy, pol);/i \
// NTSYNC SEPol — allow kernel worker to chmod and relabel /dev/ntsync\n\
ksu_allow(db, "kernel", "device", "chr_file", "setattr");\n\
ksu_allow(db, "kernel", "device", "chr_file", "relabelfrom");\n\
ksu_allow(db, "kernel", "gpu_device", "chr_file", "relabelto");\n\
ksu_allow(db, "kernel", "gpu_device", "chr_file", "setattr");\n\
\n\
// NTSYNC SEPol — allow Winlator (untrusted_app) to use /dev/ntsync\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "read");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "write");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "open");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "ioctl");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "map");\n' \
    "$RULES_FILE"
    echo "NTSYNC SELinux rules injected."
else
    echo "No KernelSU rules.c found — skipping NTSYNC SELinux injection."
fi

if command -v ld.lld >/dev/null 2>&1; then
    export LD=ld.lld
    echo "Using ld.lld from PATH: $(which ld.lld)"
elif [ -n "${CLANG_PATH}" ] && [ -x "${CLANG_PATH}/bin/ld.lld" ]; then
    export LD="${CLANG_PATH}/bin/ld.lld"
    echo "using ld.lld from CLANG_PATH: $LD"
else
    echo "error: ld.lld not found in PATH or in ${CLANG_PATH}/bin. install 'lld' on the runner"
    exit 1
fi
echo "Linker $LD"

# ── Generate kernel config ───────────────────────────────────────────────────
echo "Generating GKI defconfig..."
make O=out gki_defconfig

# ── Configure Kernel Tweaks ──────────────────────────────────────────────────
echo "Configuring Kernel Tweaks..."

scripts/config --file out/.config \
    -e LTO_CLANG \
    -d LTO_NONE \
    -e LTO_CLANG_THIN \
    -d LTO_CLANG_FULL \
    -e THINLTO

scripts/config --file out/.config \
    -e LRU_GEN \
    -e LRU_GEN_ENABLED \
    -e LRU_GEN_STATS

scripts/config --file out/.config \
    -e TCP_CONG_BBR \
    -e DEFAULT_BBR \
    -e NET_SCH_FQ \
    -e NET_SCH_FQ_CODEL

scripts/config --file out/.config \
    -e ZRAM \
    -e ZSMALLOC \
    -e CRYPTO_ZSTD \
    -e CRYPTO_LZ4 \
    -e CRYPTO_LZ4HC

scripts/config --file out/.config \
    --set-str ZRAM_DEF_COMP "lz4hc"

scripts/config --file out/.config \
    -e ZRAM_MULTI_COMP \
    --set-str ZRAM_DEF_RECOMP "zstd"
    
echo "--- [PATCH] Inject native ZRAM Multi-Comp boot default ---"
sed -i '/comp_algs\[0\].*CONFIG_ZRAM_DEF_COMP/a \	strscpy(zram->comp_algs[1], "zstd", sizeof(zram->comp_algs[1]));' drivers/block/zram/zram_drv.c

    
scripts/config --file out/.config \
    -e CONFIG_UCLAMP_TASK \
    -e CONFIG_UCLAMP_TASK_GROUP

scripts/config --file out/.config \
    -d CONFIG_NUMA \
    -d CONFIG_NODES_SPAN_OTHER_NODES

echo "Configuring Power Management for deep sleep..."
scripts/config --file out/.config \
    -e SUSPEND \
    -e SUSPEND_FREEZER \
    -e PM_SLEEP \
    -e PM_AUTOSLEEP \
    -e PM_WAKELOCKS \
    -e PM_WAKELOCKS_GC \
    --set-val PM_WAKELOCKS_LIMIT 100 \
    -d PM_WAKELOCKS_GC \
    -e CPU_IDLE \
    -e CPU_IDLE_GOV_MENU \
    -e CPU_IDLE_GOV_TEO \
    -e ARM_CPUIDLE \
    -e ARM_PSCI_CPUIDLE

scripts/config --file out/.config \
    -d LOCALVERSION_AUTO

echo "Applying new configs..."
make O=out CC=clang LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

echo "Kernel Release:"
make O=out CC=clang LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease

# ── Build kernel image ───────────────────────────────────────────────────────
echo "Building kernel image..."
make -j$(nproc --all) O=out CC=clang LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- Image

# ── Post-build verification ──────────────────────────────────────────────────
echo ""
echo "=== Post-build verification ==="

echo "--- Compiler used (from vmlinux .comment) ---"
readelf -p .comment out/vmlinux 2>/dev/null \
    | grep -v "^$\|String dump" || echo "Could not read .comment"

echo "--- LTO config check ---"
grep -E "CONFIG_LTO|CONFIG_THINLTO" out/.config || echo "No LTO configs found"

echo "--- ThinLTO cache ---"
if [ -d out/.thinlto-cache ] && [ "$(ls -A out/.thinlto-cache)" ]; then
    echo "ThinLTO cache present — ThinLTO ran successfully"
    ls -lah out/.thinlto-cache/ | head -5
else
    echo "No ThinLTO cache found"
fi

echo "--- Polly flags used ---"
echo "KCFLAGS: $KCFLAGS"

echo "--- ZRAM Multi-Comp check ---"
grep -E "CONFIG_ZRAM_MULTI_COMP|CONFIG_ZRAM_DEF_RECOMP" \
    out/.config | grep -v "^#" || echo "WARNING: ZRAM_MULTI_COMP tidak aktif!"

echo "--- [FIX #1] PM / Deep sleep config check ---"
grep -E "CONFIG_SUSPEND|CONFIG_PM_SLEEP|CONFIG_PM_AUTOSLEEP|CONFIG_PM_WAKELOCKS|CONFIG_ARM_PSCI_CPUIDLE" \
    out/.config | grep -v "^#" || echo "WARNING: beberapa PM config mungkin tidak aktif!"

echo "--- [FIX #2] LZ4HC config check ---"
grep -E "CONFIG_LZ4HC_COMPRESS|CONFIG_CRYPTO_LZ4HC|CONFIG_ZRAM_DEF_COMP" \
    out/.config || echo "WARNING: LZ4HC config tidak ditemukan!"
    
echo "--- ZRAM + LZ4HC check ---"
grep -E "CONFIG_ZRAM|CONFIG_ZSMALLOC|CONFIG_CRYPTO_LZ4HC|ZRAM_DEF_COMP" \
    out/.config | grep -v "^#"
    
echo "--- [FIX #3] Kernel version string check ---"
KRELEASE=$(make -s O=out CC=clang LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease 2>/dev/null)
echo "Kernel release: $KRELEASE"
if echo "$KRELEASE" | grep -q "\-rc"; then
    echo "WARNING: masih ada -rc di kernel release string. Cek EXTRAVERSION di Makefile!"
else
    echo "OK: tidak ada -rc suffix."
fi

echo "--- Kernel compile.h ---"
cat out/include/generated/compile.h 2>/dev/null || echo "compile.h not found"

echo "=== Verification complete ==="

# ── KMI validation ───────────────────────────────────────────────────────────
echo "Running KMI validation..."
python3 KMI_function_symbols_test.py

echo "Build completed successfully! Toolchain: ${CLANG_VARIANT}"
