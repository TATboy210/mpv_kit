# Phase 17 deferred items

## From 17-01

1. **Phase 12 `constants_audit.sh` reports `CONSTANT DRIFT` since quick 261029-rcc (0e792c8).**
   `bash .planning/phases/12-renderbackend-seam/tools/constants_audit.sh` prints
   `kPresentTimeout{50} base=1 head=0`, `int ring_size_ = 5; base=1 head=0` and
   `ring_size_ = quarantine_count_ + 3; base=1 head=0`. Those three constants were removed or
   changed on purpose by 0e792c8 (FIFO ready queue, swap at publish; ring is now
   `quarantine_count_ + 2 + kReadyDepth`). 17-01 changes nothing under `packages/`, so the drift is
   not caused by it (HEAD 5c22a6d prints the same). The audit's CHECKS list needs a reviewed update
   (drop `kPresentTimeout{50}`, re-pin the ring lines); that is a Phase 12 tool edit and out of scope
   here. Plan text asking for `CONSTANTS ok` cannot be met until that is done; the 1 s timeout line
   (`1'000'000'000ull`) and the backoff lines the fault test depends on still match.
   Status: resolved by quick 261030-3pc in ba9af05: the three constants moved to fixed-count REPINNED checks (kPresentTimeout{50} 0, kReadyDepth = 2, ring_size_ = 6, ring formula with kReadyDepth), citing 0e792c8, quick 261029-rcc and the user-approved golden re-freeze; the other 12 checks still compare against 3a5f450 and the audit prints CONSTANTS ok.
2. **Intermittent `integration-test (macos-15 ...)` red in native-verify.** libmpv.2.dylib from the
   macOS build job links `/opt/homebrew/opt/libplacebo/lib/libplacebo.387.dylib` (Homebrew bottle 7.387.0
   when the build job ran); the integration job's `brew install libplacebo` sometimes resolves 7.360.1
   (`libplacebo.387` absent), so `MpvLibraryNotFound`. Seen on 5c22a6d (run 40917086107) and
   a777f5c (run 40922504734, attempts 1 and 2); green on 468f509 (40918922908) and 6500cfb (40928914091).
   Unrelated to renderer code. Candidate fix: pin or `brew upgrade libplacebo` in the integration job,
   or build the libmpv bundle against the same bottle.
   Status: resolved by quick 261030-3pc in 6f6631c (fix-forward 127a348 re-signs unverifiable Intel copies): the macOS verify job stages libmpv's Homebrew closure with @loader_path names, the integration job installs no Homebrew formula, and `MACOS-DYLD summary ... homebrew=0` appeared on run 40939860843.
