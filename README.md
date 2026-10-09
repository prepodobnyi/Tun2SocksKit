# Tun2SocksKit

Fork of [EbrahimTahernejad/Tun2SocksKit](https://github.com/EbrahimTahernejad/Tun2SocksKit)
(originally by [arror](https://github.com/arror/)) — a Swift wrapper and build
workflow for [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel).

The Swift API, product names (`Tun2SocksKit`, `Tun2SocksKitC`), the binary
target (`HevSocks5Tunnel`), the C header and the xcframework layout are kept
identical to upstream, so it is a drop-in replacement. Differences:

- built from newer hev-socks5-tunnel releases (versions follow upstream's
  scheme: `5.x.y` ↔ hev `2.x.y`);
- `ENABLE_STACK_OVERFLOW_DETECTOR=0`: since 2.17 hev installs process-wide
  SIGSEGV/SIGBUS handlers, which conflict with a Go runtime (e.g. Xray) living
  in the same process;
- the iOS simulator stub is vendored in `stub/` instead of a separate repo;
- no CocoaPods.

## Release

Actions → Release → Run workflow with `version` (e.g. `5.18.0`) and `tag`
(hev-socks5-tunnel tag, e.g. `2.18.0`). The workflow builds the xcframework,
commits `Package.swift` with the new URL/checksum, tags it and publishes the
release.

Local build: `scripts/build.sh 2.18.0`.

## Usage

```swift
import Tun2SocksKit

let code = Socks5Tunnel.run(withConfig: .file(path: localConfigFileURL))
let code = Socks5Tunnel.run(withConfig: .string(content: stringConfigContent))
Socks5Tunnel.run(withConfig: .string(content: stringConfigContent)) { code in }

let stats = Socks5Tunnel.stats   // stats.up/down.packets/bytes
Socks5Tunnel.quit()
```
