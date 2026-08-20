# High-Clock CPU Speed Fix Audit

## Source examined

- `IWar2_HighClock_CPU_Fix.zip`, supplied locally on 2026-08-20
- SHA-256: `a27fe041baf283815edef704fe031181c09a6b88bbb60f7d31a9cdd0d73e80b2`
- Documentation revision: 2026-08-18

## Verified repair contract

- Target: `bin/release/flux.dll`
- Original size: `1,392,640` bytes
- Original SHA-256: `f5ceddfbebd4c23fe510d033918ccc1306eb02306157c3acf5d06151a5fcd39b`
- Offset: `0x18EF1`
- Required surrounding original bytes: `89 75 F0 C7 45 F4 00 00 00 00 DF 6D F0`
- One-byte replacement: `00` → `01`
- Verified patched SHA-256: `60cf69c2cc7ff4e35e5479eca77b95acadf9bbedf57b673f26c5082f0b61e33b`

The documentation explains that the game retains a startup timing-counter
measurement in 32 bits. A rate above `2^32 - 1` ticks per second wraps; the
one-byte repair restores one lost `2^32` range. It is valid only from that
threshold to below twice that threshold and is therefore guarded by the exact
file hashes and byte context above.

## Native detection

`tools/iwar2-tsc-check.cpp` measures the x86 TSC against
`CLOCK_MONOTONIC_RAW`. It pins its own short measurement to one CPU where the
platform allows that, takes three one-second samples and uses the median. This
tests the timing counter itself, not a dynamic per-core frequency report.
