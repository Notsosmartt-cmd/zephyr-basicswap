# zephyr-basicswap

Reproducible, hash-pinned build of the Zephyr (ZEPH) command-line wallet, packaged for
BasicSwap atomic-swap integration.

This is an **unofficial research build** produced for the REU26 atomic-swap project. It is
not an official Zephyr Protocol release. It exists for two reasons:

1. BasicSwap's `basicswap-prepare` downloads each coin's wallet and verifies it against a
   published hashes file. The official Zephyr v2.3.0 release ships **no `SHA256SUMS` and no
   signature**, so there is nothing for `basicswap-prepare` to verify against. This repo
   publishes a hash it can use.
2. ZEPH atomic swaps are exercised on a short regtest chain, which the stock wallet cannot do
   (see "The one change" below).

## What is in the release

Release `v2.3.0-reu26` contains `zephyr-cli-linux-v2.3.0-reu26.zip`:

| binary | provenance |
|---|---|
| `zephyrd` | stock Zephyr v2.3.0 daemon, unmodified |
| `zephyr-wallet-rpc` | Zephyr v2.3.0 wallet RPC plus a 7-line RingCT-on-short-chains clamp (below) |

BasicSwap drives the wallet over RPC, so these are the only two binaries it consumes. The
interactive `zephyr-wallet-cli` is intentionally omitted (BasicSwap does not use it, and the
stock CLI wallet does not carry the clamp).

## The one change: RingCT on short chains

Stock `zephyr-wallet-rpc` floors its RingCT output-distribution query at the mainnet fork
height (`AUDIT_FORK_HEIGHT = 481500`). On a chain shorter than that floor (a regtest /
fakechain), the query exceeds the chain tip, the daemon returns "failed to get output
distribution", and no RingCT transaction can be built. The clamp, in
`src/wallet/wallet2.cpp` `get_rct_distribution`:

```cpp
if (req.from_height >= get_blockchain_current_height())
  req.from_height = 0;
```

is a strict no-op on mainnet (the height is far past the floor) and counts the distribution
from genesis on a short chain, which already has enough coinbase-derived amount=0 RingCT
outputs to satisfy the ring size. The full diff is in
`patches/zephyr-rct-distribution-fakechain.patch`.

The same change is proposed upstream as
[ZephyrProtocol/zephyr#67](https://github.com/ZephyrProtocol/zephyr/pull/67). If it merges
and Zephyr cuts a release that includes it, this repo is no longer needed: BasicSwap can
point at the stock Zephyr release instead.

## Verify the download

From a directory containing the downloaded zip and `SHA256SUMS`:

```
sha256sum -c SHA256SUMS
```

Expected:

```
179b4e896c314babb4f900fcd0469cc01d218b32a0f1fed690e9f10edec3162c  zephyr-cli-linux-v2.3.0-reu26.zip
```

The binaries are built in an Ubuntu 20.04 toolchain (glibc 2.29 floor), so they run on any
mainstream Linux from 2019 onward.

## Reproduce the build

`scripts/build-and-hash-zeph-cli.sh` checks out the public `v2.3.0` tag, applies
`patches/zephyr-rct-distribution-fakechain.patch`, builds the CLI in Docker (the 2023-era
source needs the older toolchain), and re-emits the zip plus `SHA256SUMS`:

```
ZVER=2.3.0 bash scripts/build-and-hash-zeph-cli.sh
```

The source tag is public and the patch is in this repo, so the build is reproducible from
first principles; the hash above pins this specific artifact.

## How BasicSwap consumes it

This is the self-hosted ("Path B") rung of a trust ladder. BasicSwap downloads the wallet
from here and verifies it against the hash here. As the upstream asks land (the clamp PR
above, and Zephyr publishing a signed `SHA256SUMS`), the integration climbs to downloading
the stock, signed Zephyr release instead - a one-line change in BasicSwap's `prepare.py`.

The load-bearing values for this rung's `prepare.py` download/verify block:

```
release_url = https://github.com/Notsosmartt-cmd/zephyr-basicswap/releases/download/v2.3.0-reu26/zephyr-cli-linux-v2.3.0-reu26.zip
assert_url  = https://raw.githubusercontent.com/Notsosmartt-cmd/zephyr-basicswap/main/2.3.0/SHA256SUMS
verify      = sha256 against assert_url; hash-only (no GPG) -> SKIP_GPG_VALIDATION for ZEPH
```

## License

Built from Zephyr Protocol source, a Monero fork distributed under the BSD-3-Clause license.
Provided for research use, without warranty.
