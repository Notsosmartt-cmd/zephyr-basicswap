#!/usr/bin/env bash
# build-and-hash-zeph-cli.sh - produce the Path B (Tier 3) self-hosted ZEPH wallet artifacts.
#
# WHAT: checks out a Zephyr release tag, applies the AUDIT_FORK_HEIGHT fakechain clamp, builds the CLI
# (zephyrd + zephyr-wallet-rpc + zephyr-wallet-cli) as a static bare-metal binary via Docker, packages
# it as zephyr-cli-linux-v{VER}-reu26.zip, and writes a SHA256SUMS. These are the two files you upload
# to YOUR GitHub release that basicswap-prepare downloads from at Tier 3 of the fallback ladder
# (zeph-basicswap-fallback-ladder).
#
# WHY a script / why Docker: the 2026 toolchain cannot build the 2023-era Zephyr source natively
# (gcc 16 / Boost 1.91); the Docker (Ubuntu 20.04) path yields a static binary that runs on bare metal.
# See zephyr-testnet/BUILD-NOTES.md. Run this on the production box (it needs docker + the docker group).
#
# USAGE: ZVER=2.3.0 bash zephyr-testnet/scripts/build-and-hash-zeph-cli.sh
#   ZVER  - the Zephyr release tag to build from (default 2.3.0)
#   OUT   - output dir (default ./zeph-pathb-out)
#   SIGN  - if "1", also GPG-detach-sign SHA256SUMS with your default key (optional; hash-only is fine)
set -euo pipefail

ZVER="${ZVER:-2.3.0}"
OUT="${OUT:-$PWD/zeph-pathb-out}"
SIGN="${SIGN:-0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCH="${PATCH:-$HERE/../patches/zephyr-rct-distribution-fakechain.patch}"
BUILD_PATCHED="$HERE/build-zephyr-patched.sh"   # the existing Docker build wrapper

echo "== build-and-hash-zeph-cli :: Zephyr v$ZVER -> $OUT =="
[ -f "$PATCH" ] || { echo "ERROR: clamp patch not found at $PATCH"; exit 1; }
mkdir -p "$OUT"

# 1. Fresh checkout of the release tag (kept OUT of repos/ per the read-only policy; a build workspace).
SRC="$OUT/zephyr-src"
if [ ! -d "$SRC/.git" ]; then
  git clone --depth 1 --branch "v$ZVER" --recurse-submodules \
    https://github.com/ZephyrProtocol/zephyr "$SRC"
fi

# 2. Apply the clamp (idempotent: skip if already applied).
if ! git -C "$SRC" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
  git -C "$SRC" apply "$PATCH"
  echo "applied clamp patch"
else
  echo "clamp already applied - skipping"
fi
grep -q 'req.from_height >= get_blockchain_current_height' "$SRC/src/wallet/wallet2.cpp" \
  || { echo "ERROR: clamp not present after apply"; exit 1; }

# 3. Build via Docker. Prefer the existing wrapper if present; else a direct Ubuntu-20.04 depends build.
if [ -x "$BUILD_PATCHED" ]; then
  SRC_DIR="$SRC" OUT_DIR="$OUT/bin" "$BUILD_PATCHED"
else
  echo "NOTE: $BUILD_PATCHED not found - run your BUILD-NOTES.md Docker recipe against $SRC,"
  echo "      placing zephyrd/zephyr-wallet-rpc/zephyr-wallet-cli into $OUT/bin/. Then re-run with"
  echo "      OUT=$OUT to package + hash (steps 4-5 below)."
  [ -d "$OUT/bin" ] || exit 0
fi

# 4. Package the CLI suite.
PKG="zephyr-cli-linux-v${ZVER}-reu26.zip"
( cd "$OUT/bin" && zip -j "$OUT/$PKG" zephyrd zephyr-wallet-rpc zephyr-wallet-cli )
echo "packaged $OUT/$PKG"

# 5. Hash (+ optional sign).
( cd "$OUT" && sha256sum "$PKG" > SHA256SUMS )
echo "----- SHA256SUMS -----"; cat "$OUT/SHA256SUMS"
if [ "$SIGN" = "1" ]; then
  ( cd "$OUT" && gpg --batch --yes --detach-sign --armor SHA256SUMS )
  echo "signed -> $OUT/SHA256SUMS.asc"
fi

echo
echo "DONE. Upload these to your GitHub release (Tier 3 source for basicswap-prepare):"
echo "  $OUT/$PKG"
echo "  $OUT/SHA256SUMS${SIGN:+ (+ SHA256SUMS.asc)}"
echo "Then set the coin-add prepare.py release_url/assert_url to that release (see the fallback ladder)."
