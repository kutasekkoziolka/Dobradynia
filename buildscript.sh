#!/bin/env bash
# shellcheck disable=SC2034,SC2155
set -euo pipefail

# ╔══════════════════════════════════════════════════════════════════╗
#   NovaKernel — Build Script
#   Devices: Galaxy A73 5G (a73xq) · A52s 5G (a52sxq) · M52 5G (m52xq)
# ╚══════════════════════════════════════════════════════════════════╝


# ══════════════════════════════════════════════════════════════════
#  § 1  CONFIG  —  All user-editable values live here
# ══════════════════════════════════════════════════════════════════

# ── Toolchain versions ─────────────────────────────────────────────
SDLLVM_VER="10.0.9"
GNU_NAME="arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu"

# ── Toolchain download URLs ────────────────────────────────────────
SDLLVM_URL="https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/llvm-arm-toolchain-ship-${SDLLVM_VER}.tar.gz"
GNU_URL="https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/${GNU_NAME}.tar.xz"

# ── Stock images (pinned firmware, per device) ─────────────────────
declare -A STOCK_IMAGES=(
    [A73]="https://github.com/nicodotgit/proprietary_vendor_samsung_a73xq/releases/download/A736BXXSAGZA1_ODM/A736BXXSAGZA1_kernel.tar"
    [A52S]="https://github.com/RisenID/proprietary_vendor_samsung_a52sxq/releases/download/A528BXXUAGXK8_BTU/A528BXXUAGXK8_kernel.tar"
    [M52]="https://github.com/nicodotgit/proprietary_vendor_samsung_m52xq/releases/download/M526BXXS7CYE1_CAU/M526BXXS7CYE1_kernel.tar"
)

# ── KernelSU defaults ──────────────────────────────────────────────
KSU_DEFAULT_REPO="https://github.com/KernelSU-Next/KernelSU-Next.git"
KSU_DEFAULT_BRANCH="stable"

# ── Kernel settings ────────────────────────────────────────────────
KERNEL_BRANCH="android11"
KMI_GENERATION=2
KBUILD_USER="@sopellodu"

# ── KMI additional symbol lists ────────────────────────────────────
KMI_EXTRA_LISTS=(
    android/abi_gki_aarch64_cuttlefish  android/abi_gki_aarch64_db845c
    android/abi_gki_aarch64_exynos      android/abi_gki_aarch64_exynosauto
    android/abi_gki_aarch64_fcnt        android/abi_gki_aarch64_galaxy
    android/abi_gki_aarch64_goldfish    android/abi_gki_aarch64_hikey960
    android/abi_gki_aarch64_imx         android/abi_gki_aarch64_microsoft
    android/abi_gki_aarch64_oneplus     android/abi_gki_aarch64_oplus
    android/abi_gki_aarch64_qcom        android/abi_gki_aarch64_sony
    android/abi_gki_aarch64_sonywalkman android/abi_gki_aarch64_sunxi
    android/abi_gki_aarch64_trimble     android/abi_gki_aarch64_unisoc
    android/abi_gki_aarch64_vivo        android/abi_gki_aarch64_xiaomi
    android/abi_gki_aarch64_zebra
)


# ══════════════════════════════════════════════════════════════════
#  § 2  LOGGING
# ══════════════════════════════════════════════════════════════════

_GHA="${GITHUB_ACTIONS:-false}"

# ANSI colors
_R="\e[0m";  _B="\e[1m";  _D="\e[2m"
_CY="\e[1;36m"; _GR="\e[1;32m"; _YL="\e[1;33m"; _RE="\e[1;31m"

# Opens a collapsible group in GHA; prints a bordered header locally
log_phase() {   # usage: log_phase "emoji" "Title"
    if [[ "$_GHA" == "true" ]]; then
        echo "::group::${1}  ${2}"
    else
        local title="${1}  ${2}"
        printf "\n${_CY}${_B}  ┌─────────────────────────────────────────┐\n"
        printf              "  │  %-41s│\n" "$title"
        printf              "  └─────────────────────────────────────────┘${_R}\n\n"
    fi
}

log_end()    { [[ "$_GHA" == "true" ]] && echo "::endgroup::"; }
log_step()   { echo -e "${_GR}${_B}  ▸  $*${_R}"; }
log_ok()     { echo -e "${_GR}  ✔  $*${_R}"; }
log_warn()   { echo -e "${_YL}  ⚠  $*${_R}"; [[ "$_GHA" == "true" ]] && echo "::warning::$*"; }
log_err()    { echo -e "${_RE}${_B}  ✖  $*${_R}" >&2; [[ "$_GHA" == "true" ]] && echo "::error::$*"; }
log_info()   { echo -e "${_D}     $*${_R}"; }
log_kv()     { printf "  ${_D}%-16s${_R}${_B}%s${_R}\n" "$1" "$2"; }
log_sep()    { echo -e "${_D}  ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌${_R}"; }
log_notice() { [[ "$_GHA" == "true" ]] && echo "::notice::$*" || true; }

elapsed() { date -u -d @$(( $(date +%s) - $1 )) +'%-Mm %-Ss'; }
now()     { date '+%H:%M:%S'; }


# ══════════════════════════════════════════════════════════════════
#  § 3  INIT
# ══════════════════════════════════════════════════════════════════

# Installs all build dependencies via apt.
# Skipped on subsequent runs if the sentinel file ~/.nova_deps_ok exists.
install_deps() {
    [[ -f "$HOME/.nova_deps_ok" ]] && { log_ok "Dependencies — already installed ✓"; return; }

    log_phase "📦" "Install Dependencies"
    log_step "Running apt update..."
    sudo apt-get update -qq

    log_step "Installing packages..."
    sudo apt-get install -y --fix-missing \
        git device-tree-compiler lz4 xz-utils zlib1g-dev \
        openjdk-17-jdk gcc g++ python3 python-is-python3 \
        p7zip-full android-sdk-libsparse-utils erofs-utils \
        gnupg flex bison gperf build-essential zip curl \
        libncurses-dev libx11-dev libreadline-dev libgl1 libgl1-mesa-dev \
        bc grep tofrodos python3-markdown libxml2-utils xsltproc \
        libtinfo6 cpio kmod openssl libelf-dev pahole libssl-dev \
        libarchive-tools zstd rsync repo

    log_step "Installing libtinfo5 (required by older clang binaries)..."
    local deb="$HOME/libtinfo5.deb"
    wget -q "http://security.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2ubuntu0.1_amd64.deb" \
        -O "$deb"
    sudo dpkg -i "$deb"
    rm "$deb"

    touch "$HOME/.nova_deps_ok"
    log_ok "All packages installed"
    log_end
}

# Verifies required tools are present after installation
check_deps() {
    log_phase "🔍" "Dependency Check"
    local all_ok=true
    for tool in git curl wget unzip tar lz4 awk sed zip patch make; do
        if command -v "$tool" &>/dev/null; then
            log_info "$(printf '%-12s' "$tool")✔  $(command -v "$tool")"
        else
            log_err "Missing tool: $tool"; all_ok=false
        fi
    done
    $all_ok || { log_err "Install missing tools and retry."; exit 1; }
    log_ok "All dependencies satisfied"
    log_end
}

# Derives all runtime paths from CONFIG values and builds MAKE_OPTS array
init_vars() {
    SRC_DIR="$(pwd)"
    OUT_DIR="$SRC_DIR/out"
    TC_DIR="$HOME/toolchains"
    JOBS=$(nproc)

    SDLLVM_DIR="$TC_DIR/llvm-arm-toolchain-ship/$SDLLVM_VER"
    SDLLVM_BIN="$SDLLVM_DIR/bin"
    GNU_DIR="$TC_DIR/gcc/$GNU_NAME"
    GNU_BIN="$GNU_DIR/bin"

    BUILD_CC="$SDLLVM_BIN/clang"
    BUILD_CROSS_COMPILE="$GNU_BIN/aarch64-none-linux-gnu-"

    export PATH="$SDLLVM_BIN:$GNU_BIN:$TC_DIR:$PATH"
    export LD_LIBRARY_PATH="$SDLLVM_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    # Shared make flags — used by build_kernel() and build_modules()
    MAKE_OPTS=(
        -C "$SRC_DIR"
        O="$OUT_DIR"
        -j"$JOBS"
        ARCH=arm64
        CC="$BUILD_CC"
        CROSS_COMPILE="$BUILD_CROSS_COMPILE"
        CLANG_TRIPLE="aarch64-linux-gnu-"
        KBUILD_BUILD_USER="$KBUILD_USER"
    )

    export SRC_DIR OUT_DIR TC_DIR JOBS
    export SDLLVM_DIR SDLLVM_BIN GNU_DIR GNU_BIN
    export BUILD_CC BUILD_CROSS_COMPILE
}


# ══════════════════════════════════════════════════════════════════
#  § 4  PROMPTS  —  Interactive (local builds only)
# ══════════════════════════════════════════════════════════════════

prompt_variant() {
    echo -e "${_CY}${_B}"
    echo "  Select target device:"
    echo "  [1] Galaxy A73 5G   (a73xq)"
    echo "  [2] Galaxy A52s 5G  (a52sxq)"
    echo "  [3] Galaxy M52 5G   (m52xq)"
    echo -e "${_R}"
    read -rp "  → Choice [1-3]: " _c
    case "$_c" in
        1) VARIANT="a73xq";; 2) VARIANT="a52sxq";; 3) VARIANT="m52xq";;
        *) log_err "Invalid choice"; exit 1;;
    esac
}

prompt_ksu() {
    echo -e "${_CY}${_B}"
    echo "  Build with KernelSU?"
    echo "  [1] No   — standard kernel"
    echo "  [2] Yes  — KernelSU kernel"
    echo -e "${_R}"
    read -rp "  → Choice [1-2]: " _c
    case "$_c" in
        1) KERNELSU=false;; 2) KERNELSU=true;;
        *) log_err "Invalid choice"; exit 1;;
    esac
}

prompt_ksu_branch() {
    echo -e "${_CY}${_B}"
    echo "  Select KernelSU branch:"
    echo "  [1] legacy           (stable, recommended)"
    echo "  [2] main             (latest stable)"
    echo "  [3] next             (bleeding edge)"
    echo "  [4] susfs-main       (SuSFS + main)"
    echo "  [5] susfs-next       (SuSFS + next)"
    echo "  [6] legacy-susfs-v2  (SuSFS v2 + legacy)"
    echo "  [7] custom           (enter manually)"
    echo -e "${_R}"
    read -rp "  → Choice [1-7]: " _c
    case "$_c" in
        1) KSU_BRANCH="legacy";;       2) KSU_BRANCH="main";;
        3) KSU_BRANCH="next";;         4) KSU_BRANCH="susfs-main";;
        5) KSU_BRANCH="susfs-next";;   6) KSU_BRANCH="legacy-susfs-v2";;
        7) read -rp "  → Branch name: " KSU_BRANCH
           [[ -z "$KSU_BRANCH" ]] && { log_err "Branch name cannot be empty"; exit 1; };;
        *) log_err "Invalid choice"; exit 1;;
    esac
}

prompt_hook_type() {
    echo -e "${_CY}${_B}"
    echo "  Select KernelSU hook type:"
    echo "  [1] kprobes        — kprobe-based (no patches needed)"
    echo "  [2] scope-min-1.6  — scope-min manual hook (5.4)"
    echo "  [3] rksu           — rksu manual hook (4.19 / 5.4)"
    echo "  [4] syscall        — syscall hook patches"
    echo "  [5] inline         — inline / susfs hook patches"
    echo -e "${_R}"
    read -rp "  → Choice [1-5]: " _c
    case "$_c" in
        1) HOOK_TYPE="kprobes";; 2) HOOK_TYPE="scope-min-1.6";;
        3) HOOK_TYPE="rksu";;    4) HOOK_TYPE="syscall";;
        5) HOOK_TYPE="inline";;
        *) log_err "Invalid choice"; exit 1;;
    esac
}

prompt_backport() {
    echo -e "${_CY}${_B}"
    echo "  Apply backport patches?"
    echo "  [1] No"
    echo "  [2] Yes"
    echo -e "${_R}"
    read -rp "  → Choice [1-2]: " _c
    case "$_c" in
        1) BACKPORT=false;; 2) BACKPORT=true;;
        *) log_err "Invalid choice"; exit 1;;
    esac
}


# ══════════════════════════════════════════════════════════════════
#  § 5  COMPILER
# ══════════════════════════════════════════════════════════════════

# Downloads Snapdragon LLVM and ARM GNU toolchain if not already present.
# In GitHub Actions this is a no-op when the toolchain job pre-populates cache.
fetch_compiler() {
    log_phase "🧰" "Compiler Toolchain"
    mkdir -p "$TC_DIR"

    # Snapdragon LLVM
    if [[ ! -d "$SDLLVM_BIN" ]]; then
        log_step "Downloading Snapdragon LLVM $SDLLVM_VER..."
        wget --progress=bar:force:noscroll "$SDLLVM_URL" -O "$TC_DIR/llvm.tar.gz"
        tar xf "$TC_DIR/llvm.tar.gz" -C "$TC_DIR"
        rm "$TC_DIR/llvm.tar.gz"
        log_ok "Snapdragon LLVM $SDLLVM_VER — ready"
    else
        log_ok "Snapdragon LLVM $SDLLVM_VER — cached ✓"
    fi

    # ARM GNU (aarch64-none-linux-gnu)
    if [[ ! -d "$GNU_DIR" ]]; then
        log_step "Downloading ARM GNU Toolchain 14.2..."
        mkdir -p "$TC_DIR/gcc"
        wget --progress=bar:force:noscroll "$GNU_URL" -O "$TC_DIR/gcc/gnu.tar.xz"
        tar xf "$TC_DIR/gcc/gnu.tar.xz" -C "$TC_DIR/gcc"
        rm "$TC_DIR/gcc/gnu.tar.xz"
        log_ok "ARM GNU Toolchain — ready"
    else
        log_ok "ARM GNU Toolchain — cached ✓"
    fi

    log_end
}


# ══════════════════════════════════════════════════════════════════
#  § 6  ASSETS
# ══════════════════════════════════════════════════════════════════

# Downloads magiskboot and avbtool (needed during image repack)
fetch_boot_tools() {
    log_phase "🛠️" "Boot Tools"

    if [[ ! -f "$TC_DIR/magiskboot" ]]; then
        log_step "Fetching magiskboot from latest Magisk release..."
        local apk_url
        apk_url="$(curl -s ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
            "https://api.github.com/repos/topjohnwu/Magisk/releases" \
            | grep -oE 'https://[^"]+\.apk' | grep 'Magisk[-.]v' | head -n1)"
        wget -q --show-progress "$apk_url" -O "$TC_DIR/magisk.apk"
        unzip -p "$TC_DIR/magisk.apk" "lib/x86_64/libmagiskboot.so" > "$TC_DIR/magiskboot"
        chmod +x "$TC_DIR/magiskboot"
        rm "$TC_DIR/magisk.apk"
        log_ok "magiskboot — ready"
    else
        log_ok "magiskboot — cached ✓"
    fi

    if [[ ! -f "$TC_DIR/avbtool" ]]; then
        log_step "Fetching avbtool from AOSP..."
        curl -s "https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py?format=TEXT" \
            | base64 --decode > "$TC_DIR/avbtool"
        chmod +x "$TC_DIR/avbtool"
        log_ok "avbtool — ready"
    else
        log_ok "avbtool — cached ✓"
    fi

    log_end
}

# Downloads stock kernel images for all three devices.
# Called once; the GHA images job caches the result for subsequent builds.
fetch_stock_images() {
    log_phase "📱" "Stock Images"
    mkdir -p "$TC_DIR/images"

    local all_cached=true
    for name in "${!STOCK_IMAGES[@]}"; do
        [[ ! -d "$TC_DIR/images/$name" ]] && { all_cached=false; break; }
    done

    if $all_cached; then
        log_ok "Stock images — all cached ✓"
        log_end; return
    fi

    for name in "${!STOCK_IMAGES[@]}"; do
        if [[ -d "$TC_DIR/images/$name" ]]; then
            log_ok "$name — cached ✓"; continue
        fi
        log_step "Downloading $name stock image..."
        mkdir -p "$TC_DIR/images/$name"
        wget -qO- "${STOCK_IMAGES[$name]}" | tar xf - -C "$TC_DIR/images/$name"
        lz4 -dm --rm "$TC_DIR/images/$name/"*
        log_ok "$name — ready"
    done

    log_end
}


# ══════════════════════════════════════════════════════════════════
#  § 7  KERNELSU
# ══════════════════════════════════════════════════════════════════

# Clones and integrates KernelSU-Next into the kernel source tree
setup_kernelsu() {
    log_phase "⚡" "KernelSU Setup"

    local repo="${NK_KSU_REPO:-$KSU_DEFAULT_REPO}"
    local branch="${KSU_BRANCH:-$KSU_DEFAULT_BRANCH}"

    log_step "Running tiann/KernelSU setup script..."
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
    rm -rf KernelSU

    log_step "Cloning KernelSU-Next  [branch: $branch]"
    log_info "Repo: $repo"
    git clone --depth=1 -b "$branch" "$repo" KernelSU

    log_ok "KernelSU-Next integrated"
    log_end
}

# Applies the selected hook patch to the kernel source.
# kprobes is handled natively by KernelSU — no patch needed.
apply_hook() {
    [[ "$HOOK_TYPE" == "kprobes" ]] && {
        log_ok "Hook: kprobes — handled by KernelSU, no patches needed"
        return
    }

    log_phase "🪝" "Hook Patches  [$HOOK_TYPE]"
    local T0=$(date +%s)

    # Idempotency guard — skip if already applied
    if grep -q "ksu_handle_execveat" "$SRC_DIR/fs/exec.c" 2>/dev/null; then
        log_warn "Hook already applied — skipping"
        log_end; return
    fi

    case "$HOOK_TYPE" in
        scope-min-1.6)
            local url="https://raw.githubusercontent.com/OmarAlsmehan/Random-stuff/refs/heads/main/scope-min-manual-hook.1.6-5.4.patch"
            log_step "Downloading scope-min-1.6 patch..."
            wget -q "$url" -O "$TC_DIR/hook.patch"
            patch -p1 -d "$SRC_DIR" < "$TC_DIR/hook.patch"
            ;;
        rksu)
            local url="https://raw.githubusercontent.com/rksuorg/kernel_patches/refs/heads/master/manual_hook/kernel-4.19_5.4.patch"
            log_step "Downloading RKSU hook patch..."
            wget -q "$url" -O "$TC_DIR/hook.patch"
            patch -p1 -d "$SRC_DIR" < "$TC_DIR/hook.patch"
            ;;
        syscall)
            local url="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/syscall_hook_patches.sh"
            log_step "Downloading syscall hook script..."
            wget -q "$url" -O "$TC_DIR/hook.sh" && chmod +x "$TC_DIR/hook.sh"
            ( cd "$SRC_DIR" && bash "$TC_DIR/hook.sh" )
            ;;
        inline)
            local url="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/susfs_inline_hook_patches.sh"
            log_step "Downloading inline hook script..."
            wget -q "$url" -O "$TC_DIR/hook.sh" && chmod +x "$TC_DIR/hook.sh"
            ( cd "$SRC_DIR" && bash "$TC_DIR/hook.sh" )
            ;;
    esac

    log_ok "Hook [$HOOK_TYPE] applied in $(elapsed $T0)"
    log_end
}

# Applies backport patches (path_umount etc.) to the kernel source
apply_backport() {
    log_phase "⬆️" "Backport Patches"
    local T0=$(date +%s)

    if grep -q "path_umount" "$SRC_DIR/fs/namespace.c" 2>/dev/null; then
        log_warn "Backport already applied — skipping"
        log_end; return
    fi

    local url="https://raw.githubusercontent.com/JackA1ltman/NonGKI_Kernel_Build_2nd/refs/heads/mainline/Patches/backport_patches.sh"
    log_step "Downloading backport patches..."
    wget -q "$url" -O "$TC_DIR/backport.sh" && chmod +x "$TC_DIR/backport.sh"
    ( cd "$SRC_DIR" && bash "$TC_DIR/backport.sh" )

    log_ok "Backport applied in $(elapsed $T0)"
    log_end
}


# ══════════════════════════════════════════════════════════════════
#  § 8  BUILD
# ══════════════════════════════════════════════════════════════════

# Resolves VARIANT/DEVICE, sets all kernel env vars, then compiles
build_kernel() {
    log_phase "🔨" "Kernel Compile  [$(now)]"

    case "$1" in
        a73xq)  VARIANT="a73xq";  DEVICE="A73";;
        a52sxq) VARIANT="a52sxq"; DEVICE="A52S";;
        m52xq)  VARIANT="m52xq";  DEVICE="M52";;
        *) log_err "Unknown variant: $1"; exit 1;;
    esac
    export VARIANT DEVICE ARCH=arm64

    # Kernel environment variables
    export BRANCH="$KERNEL_BRANCH"
    export KMI_GENERATION DEPMOD=depmod
    export KCFLAGS="${KCFLAGS:-} -D__ANDROID_COMMON_KERNEL__"
    export STOP_SHIP_TRACEPRINTK=1 IN_KERNEL_MODULES=1
    export DO_NOT_STRIP_MODULES=1 INSTALL_MOD_STRIP=1
    export ABI_DEFINITION=android/abi_gki_aarch64.xml
    export KMI_SYMBOL_LIST=android/abi_gki_aarch64
    export ADDITIONAL_KMI_SYMBOL_LISTS="$(IFS=$'\n'; echo "${KMI_EXTRA_LISTS[*]}")"
    export TRIM_NONLISTED_KMI=0 KMI_SYMBOL_LIST_ADD_ONLY=1
    export KMI_SYMBOL_LIST_STRICT_MODE=0 KMI_ENFORCED=0

    local comrev; comrev=$(git rev-parse --short HEAD)
    export LOCALVERSION="-JonasKernel-${BRANCH}-${KMI_GENERATION}-${comrev}-${VARIANT}"

    local defconfig="vendor/lineage-${VARIANT}_defconfig"

    # Print build summary
    log_sep
    log_kv "Device:"     "$DEVICE ($VARIANT)"
    log_kv "Defconfig:"  "$defconfig"
    log_kv "Type:"       "$BUILD_TYPE"
    [[ "$BUILD_TYPE" == "KSU" ]] && {
        log_kv "KSU Branch:" "${KSU_BRANCH:-legacy}"
        log_kv "Hook:"       "${HOOK_TYPE:-kprobes}"
    }
    log_kv "Version:"    "5.4.x$LOCALVERSION"
    log_kv "Compiler:"   "$("$BUILD_CC" --version | head -n1)"
    log_kv "GNU:"        "$("${BUILD_CROSS_COMPILE}gcc" --version | head -n1)"
    log_kv "Jobs:"       "$JOBS"
    log_sep

    local T0=$(date +%s)

    log_step "make clean..."
    [[ -d "$OUT_DIR" ]] && make "${MAKE_OPTS[@]}" clean 2>&1 | sed 's/^/       /'

    log_step "make $defconfig..."
    make "${MAKE_OPTS[@]}" "$defconfig" 2>&1 | sed 's/^/       /'

    # KernelSU requires CONFIG_KSU=y — the defconfig may not have it,
    # so we force-enable it via scripts/config then run olddefconfig
    # to let Kconfig resolve any dependencies automatically.
    if [[ "$BUILD_TYPE" == "KSU" ]]; then
        log_step "Enabling CONFIG_KSU in .config..."
        "$SRC_DIR/scripts/config" --file "$OUT_DIR/.config" -e CONFIG_KSU
        make "${MAKE_OPTS[@]}" olddefconfig 2>&1 | sed 's/^/       /'
        log_ok "CONFIG_KSU=y — confirmed"
    fi

    log_step "make Image..."
    make "${MAKE_OPTS[@]}" 2>&1 | sed 's/^/       /'

    log_ok "Kernel compiled in $(elapsed $T0)"
    log_end
}

# Installs modules and collects .ko files + metadata into the staging dir
build_modules() {
    log_phase "📦" "Modules  [$(now)]"
    local T0=$(date +%s)

    # DO_NOT_STRIP_MODULES must be re-exported when called standalone
    export DO_NOT_STRIP_MODULES=1

    make "${MAKE_OPTS[@]}" \
        INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 \
        modules_install 2>&1 | sed 's/^/       /'

    local modout="$TC_DIR/JonasKernel/$DEVICE/$BUILD_TYPE/modules"
    mkdir -p "$modout"
    find "$OUT_DIR/modules" -name '*.ko' -exec cp '{}' "$modout/" \;

    local krel; krel=$(cat "$OUT_DIR/include/config/kernel.release")
    local modlib="$OUT_DIR/modules/lib/modules/$krel"

    cp "$modlib/modules.alias"   "$modout/"
    cp "$modlib/modules.dep"     "$modout/"
    cp "$modlib/modules.softdep" "$modout/"
    cp "$modlib/modules.order"   "$modout/modules.load"

    # Fix module paths to match /lib/modules/ on device
    sed -i 's|\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)|/lib/modules/\2|g' "$modout/modules.dep"
    sed -i 's|.*\/||g' "$modout/modules.load"

    local count; count=$(find "$modout" -name '*.ko' | wc -l)
    log_ok "Modules done — ${count} .ko files  ($(elapsed $T0))"
    log_end
}


# ══════════════════════════════════════════════════════════════════
#  § 9  PACKAGE
# ══════════════════════════════════════════════════════════════════

# Creates the output directory structure and writes the TWRP flash script
stage_artifacts() {
    log_phase "🗂️" "Staging Artifacts"

    local out="$TC_DIR/JonasKernel/$DEVICE"
    mkdir -p \
        "$out/$BUILD_TYPE/modules" \
        "$out/ZIP/META-INF/com/google/android" \
        "$out/ZIP/images"

    cp "$OUT_DIR/arch/arm64/boot/Image"                      "$out/kernel"
    cp "$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/yupik.dtb" "$out/dtb"
    log_ok "Copied → kernel, dtb"

    echo "# Dummy file; update-binary is a shell script." \
        > "$out/ZIP/META-INF/com/google/android/updater-script"

    cat > "$out/ZIP/META-INF/com/google/android/update-binary" << 'FLASH_EOF'
#!/sbin/sh

OUTFD=/proc/self/fd/$2
ZIPFILE="$3"
TMPDIR="/cache/nova"

package_extract_dir() {
    local entry outfile
    for entry in $(unzip -l "$ZIPFILE" 2>/dev/null | tail -n+4 | grep -v '/$' \
                   | grep -o " $1.*$" | cut -c2-); do
        outfile="$(echo "$entry" | sed "s|${1}|${2}|")"
        mkdir -p "$(dirname "$outfile")"
        unzip -o "$ZIPFILE" "$entry" -p > "$outfile"
    done
}
ui_print()     { while [ "$1" ]; do echo "ui_print $1" >> "$OUTFD"; echo "ui_print" >> "$OUTFD"; shift; done; }
ui_printfile() { unzip -p "$ZIPFILE" "$1" 2>/dev/null | while IFS= read -r l; do ui_print "$l"; done; }
write_image()  { dd if="$1" of="$2"; }
set_progress() { echo "set_progress $1" >> "$OUTFD"; }

set_progress 0.0
ui_printfile "banner"
ui_print " "

getprop ro.boot.bootloader | grep -qE "A736|A528|M526" || {
    ui_print "✖ Unsupported device — aborting."
    exit 1
}

mount -o rw,remount -t auto /cache
mkdir -p "$TMPDIR"

ui_print "→ Extracting images..."
package_extract_dir "images" "$TMPDIR/"
set_progress 0.2

ui_print "→ Flashing boot.img..."
write_image "$TMPDIR/boot.img" "/dev/block/bootdevice/by-name/boot"
set_progress 0.4

ui_print "→ Flashing vendor_boot.img..."
write_image "$TMPDIR/vendor_boot.img" "/dev/block/bootdevice/by-name/vendor_boot"
set_progress 0.8

rm -rf "$TMPDIR"
set_progress 1.0
ui_print " "
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print "  JonasKernel installed successfully!"
ui_print "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ui_print " "
FLASH_EOF

    chmod +x "$out/ZIP/META-INF/com/google/android/update-binary"
    log_ok "Flash script written → update-binary"
    log_end
}

# Repacks boot.img and vendor_boot.img with the new kernel and modules
gki_repack() {
    log_phase "🖼️" "Image Repack  [$(now)]"
    local T0=$(date +%s)
    local dest="$TC_DIR/JonasKernel/$DEVICE/$BUILD_TYPE"
    mkdir -p "$dest"

    # ── boot.img ──────────────────────────────────────────────────
    log_step "Repacking boot.img..."
    cp "$TC_DIR/images/$DEVICE/boot.img" "$dest/boot.img"
    avbtool erase_footer --image "$dest/boot.img"
    (
        mkdir -p "$dest/tmp" && cd "$dest/tmp"
        magiskboot unpack ../boot.img
        cp "$OUT_DIR/arch/arm64/boot/Image" kernel
        magiskboot repack ../boot.img boot.img
        mv boot.img ../boot.img
        cd .. && rm -rf tmp
    )
    log_ok "boot.img repacked"

    # ── vendor_boot.img ───────────────────────────────────────────
    log_step "Repacking vendor_boot.img..."
    cp "$TC_DIR/images/$DEVICE/vendor_boot.img" "$dest/vendor_boot.img"
    avbtool erase_footer --image "$dest/vendor_boot.img"
    (
        mkdir -p "$dest/tmp" && cd "$dest/tmp"
        magiskboot unpack -h ../vendor_boot.img || true

        # Fix SRP suffix and optional SELinux debug flag
        sed -Ei 's/(name=SRP[[:alnum:]]*)[0-9]{3}/\1001/' header
        [[ "${DEBUG:-false}" == "true" ]] && \
            sed -i '2 s/$/ androidboot.selinux=permissive/' header

        # Replace DTB
        rm dtb && cp "$TC_DIR/JonasKernel/$DEVICE/dtb" dtb

        # Patch fstab: add erofs / ext4 / f2fs entries alongside existing ones
        magiskboot cpio ramdisk.cpio "extract first_stage_ramdisk/fstab.qcom fstab.qcom"
        awk 'BEGIN{OFS="\t"}
            /^(system|vendor|product|odm)\s/ && !seen[$1]++ {
                rest=$4; for(i=5;i<=NF;i++) rest=rest"\t"$i
                for(i=1;i<=3;i++) print $1,$2,(i==1?"erofs":i==2?"ext4":"f2fs"),rest
                next
            }1' fstab.qcom > fstab.qcom.new

        # Build cpio operations list
        declare -a ops=(
            "rm first_stage_ramdisk/fstab.qcom"
            "add 0644 first_stage_ramdisk/fstab.qcom fstab.qcom.new"
            "mkdir 0755 lib/firmware"
        )

        # Device-specific firmware blobs
        case "$DEVICE" in
            A73)
                local fw="lib/firmware/tsp_synaptics" src="$SRC_DIR/firmware/tsp_synaptics"
                ops+=("mkdir 0755 $fw")
                for f in s3908_a73xq_boe.bin s3908_a73xq_csot.bin \
                         s3908_a73xq_sdc.bin s3908_a73xq_sdc_4th.bin; do
                    ops+=("add 0644 $fw/$f $src/$f")
                done ;;
            A52S)
                local fw="lib/firmware/tsp_stm" src="$SRC_DIR/firmware/tsp_stm"
                ops+=("mkdir 0755 $fw"
                      "add 0644 $fw/fts5cu56a_a52sxq.bin $src/fts5cu56a_a52sxq.bin") ;;
            M52)
                local fw="lib/firmware/abov" src="$SRC_DIR/firmware/abov"
                ops+=("mkdir 0755 $fw")
                for f in a96t356_m52xq.bin a96t356_m52xq_sub.bin; do
                    ops+=("add 0644 $fw/$f $src/$f")
                done
                local fw2="lib/firmware/tsp_synaptics" src2="$SRC_DIR/firmware/tsp_synaptics"
                ops+=("mkdir 0755 $fw2")
                for f in s3908_m52xq.bin s3908_m52xq_boe.bin s3908_m52xq_sdc.bin; do
                    ops+=("add 0644 $fw2/$f $src2/$f")
                done ;;
        esac

        # Inject kernel modules
        ops+=("rm -r lib/modules" "mkdir 0755 lib/modules")
        for f in "$dest/modules/"*; do
            ops+=("add 0644 lib/modules/$(basename "$f") $f")
        done

        magiskboot cpio ramdisk.cpio "${ops[@]}"
        magiskboot repack ../vendor_boot.img vendor_boot.img
        mv vendor_boot.img ../vendor_boot.img
        cd .. && rm -rf tmp
    )
    log_ok "vendor_boot.img repacked"

    log_ok "All images repacked in $(elapsed $T0)"
    log_end
}

# Creates the final flashable ZIP and prints an artifact summary
gen_zip() {
    log_phase "🤐" "Package ZIP  [$(now)]"
    local T0=$(date +%s)
    local src="$TC_DIR/JonasKernel/$DEVICE/$BUILD_TYPE"
    local zip_dir="$TC_DIR/JonasKernel/$DEVICE/ZIP"

    wget -q "https://raw.githubusercontent.com/OmarAlsmehan/AnyKernel3/refs/heads/master/banner" \
        -O "$zip_dir/banner"
    cp -a "$src/boot.img" "$src/vendor_boot.img" "$zip_dir/images/"

    local ksu_ver=""
    [[ "$BUILD_TYPE" == "KSU" ]] && \
        ksu_ver=$(grep -oP -- "-DKSU_VERSION=\K[0-9]+" \
            "$OUT_DIR/drivers/kernelsu/.ksu.o.cmd" 2>/dev/null | sed 's/^/-/' || true)

    local zipname="JonasKernel_$(date +%Y%m%d)_${BUILD_TYPE}${ksu_ver}_${VARIANT}.zip"
    local zipout="$src/$zipname"

    log_step "Creating $zipname..."
    ( cd "$zip_dir" && zip -r -9 "$zipout" images META-INF banner )
    rm -rf "$zip_dir/images/"* "$zip_dir/META-INF" "$zip_dir/banner"

    local size sha
    size=$(du -sh "$zipout" | cut -f1)
    sha=$(sha256sum "$zipout" | awk '{print $1}')

    log_sep
    log_kv "Output:"  "$zipname"
    log_kv "Size:"    "$size"
    log_kv "SHA256:"  "${sha:0:16}…${sha: -8}"
    log_kv "Time:"    "$(elapsed $T0)"
    log_sep

    log_notice "ZIP ready → $zipname  ($size)"
    log_end
}


# ══════════════════════════════════════════════════════════════════
#  § 10  ENTRY
# ══════════════════════════════════════════════════════════════════

_print_plan() {
    echo ""
    echo -e "${_CY}${_B}  ╭──────────────────────────────────────────╮"
    echo -e "  │      🚀  NovaKernel  Build Plan          │"
    echo -e "  ├──────────────────────────────────────────┤"
    printf  "  │  ${_R}%-14s${_CY}${_B}%-28s│\n" "Device:"  "$VARIANT"
    printf  "  │  ${_R}%-14s${_CY}${_B}%-28s│\n" "Type:"    "$BUILD_TYPE"
    [[ "$KERNELSU" == "true" ]] && {
        printf "  │  ${_R}%-14s${_CY}${_B}%-28s│\n" "KSU Branch:" "${KSU_BRANCH:-legacy}"
        printf "  │  ${_R}%-14s${_CY}${_B}%-28s│\n" "Hook:"       "${HOOK_TYPE:-kprobes}"
        printf "  │  ${_R}%-14s${_CY}${_B}%-28s│\n" "Backport:"   "${BACKPORT:-false}"
    }
    printf  "  │  ${_R}%-14s${_D}%-28s${_CY}${_B}│\n" "Started:" "$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "  ╰──────────────────────────────────────────╯${_R}"
    echo ""
}

_print_done() {
    local total="$1"
    echo ""
    echo -e "${_GR}${_B}  ╭──────────────────────────────────────────╮"
    echo -e "  │    ✅  Build Completed Successfully      │"
    echo -e "  ├──────────────────────────────────────────┤"
    printf  "  │  ${_R}%-14s${_GR}${_B}%-28s│\n" "Device:"   "$VARIANT"
    printf  "  │  ${_R}%-14s${_GR}${_B}%-28s│\n" "Type:"     "$BUILD_TYPE"
    [[ "${KERNELSU:-false}" == "true" ]] && {
        printf "  │  ${_R}%-14s${_GR}${_B}%-28s│\n" "Hook:"    "${HOOK_TYPE:-kprobes}"
        printf "  │  ${_R}%-14s${_GR}${_B}%-28s│\n" "Backport:" "${BACKPORT:-false}"
    }
    printf  "  │  ${_R}%-14s${_GR}${_B}%-28s│\n" "Duration:"  "$total"
    echo -e "  ╰──────────────────────────────────────────╯${_R}"
    echo ""
}

ENTRY() {

    # ── Parse arguments (must happen before anything else) ────────
    #   --phase compiler  →  fetch_compiler only
    #   --phase images    →  fetch_stock_images only
    #   --phase ksu       →  KernelSU + hook + [backport]
    #   --phase build     →  boot tools + compile + package
    #   clean             →  wipe out/ and artifacts
    #   (no args)         →  full local build (all phases)
    local PHASE="all"
    if [[ "${1:-}" == "--phase" ]]; then
        PHASE="${2:?'--phase requires: compiler | images | ksu | build | all'}"
        shift 2
    fi

    # ── Special: clean ────────────────────────────────────────────
    if [[ "${1:-}" == "clean" ]]; then
        init_vars
        log_phase "🧹" "Clean"
        rm -rf "$OUT_DIR" "$TC_DIR/NovaKernel"
        log_ok "Cleaned out/ and NovaKernel artifacts"
        log_end; exit 0
    fi

    # ── Single-purpose phases — resolved BEFORE any prompt ────────
    #    Explicit if statements (more reliable than case with set -euo)
    if [[ "$PHASE" == "compiler" ]]; then
        install_deps; check_deps; init_vars; fetch_compiler; exit 0
    fi
    if [[ "$PHASE" == "images" ]]; then
        install_deps; check_deps; init_vars; fetch_stock_images; exit 0
    fi

    # ── Full initialization for ksu / build / all phases ─────────
    local BUILD_START=$(date +%s)
    install_deps
    check_deps
    init_vars

    # ── Resolve variant ──────────────────────────────────────────
    if   [[ -n "${1:-}"          ]]; then VARIANT="$1"
    elif [[ -n "${NK_VARIANT:-}" ]]; then VARIANT="$NK_VARIANT"
    else prompt_variant
    fi

    [[ ! "$VARIANT" =~ ^(a73xq|a52sxq|m52xq)$ ]] && {
        log_err "Invalid variant: $VARIANT  (valid: a73xq | a52sxq | m52xq)"; exit 1
    }

    # ── Resolve KernelSU options ─────────────────────────────────
    if [[ -n "${NK_KSU:-}" ]]; then KERNELSU="$NK_KSU"; else prompt_ksu; fi

    if [[ "$KERNELSU" == "true" ]]; then
        BUILD_TYPE="KSU"

        if [[ -n "${NK_KSU_BRANCH:-}" ]]; then KSU_BRANCH="$NK_KSU_BRANCH"; else prompt_ksu_branch; fi
        KSU_BRANCH="${KSU_BRANCH:-$KSU_DEFAULT_BRANCH}"

        if [[ -n "${NK_HOOK_TYPE:-}" ]]; then HOOK_TYPE="$NK_HOOK_TYPE"; else prompt_hook_type; fi
        HOOK_TYPE="${HOOK_TYPE:-kprobes}"
        [[ ! "$HOOK_TYPE" =~ ^(kprobes|scope-min-1\.6|rksu|syscall|inline)$ ]] && {
            log_err "Invalid hook type: $HOOK_TYPE"; exit 1
        }

        if [[ -n "${NK_BACKPORT:-}" ]]; then BACKPORT="$NK_BACKPORT"; else prompt_backport; fi
        BACKPORT="${BACKPORT:-false}"
    else
        BUILD_TYPE="GKI"
        HOOK_TYPE="kprobes"
        BACKPORT=false
    fi

    export BUILD_TYPE KSU_BRANCH HOOK_TYPE BACKPORT KERNELSU

    # ── Print build plan (local only) ────────────────────────────
    _print_plan

    # ── Run phases ───────────────────────────────────────────────
    if [[ "$PHASE" == "all" ]]; then
        fetch_compiler
        fetch_stock_images
    fi

    if [[ "$PHASE" == "all" || "$PHASE" == "ksu" ]]; then
        [[ "$KERNELSU" == "true" ]] && {
            setup_kernelsu
            apply_hook
            [[ "$BACKPORT" == "true" ]] && apply_backport
        }
    fi

    if [[ "$PHASE" == "all" || "$PHASE" == "build" ]]; then
        fetch_boot_tools
        build_kernel "$VARIANT"
        build_modules
        stage_artifacts
        gki_repack
        gen_zip
    fi

    # ── Done ─────────────────────────────────────────────────────
    local total; total=$(elapsed $BUILD_START)
    _print_done "$total"
    log_notice "✅ Build complete — $VARIANT [$BUILD_TYPE] hook=$HOOK_TYPE backport=$BACKPORT in $total"
}

ENTRY "$@"
