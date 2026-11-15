---
quick_id: 261025-rkj
status: complete
commit: 7962c3f
---

# 261025-rkj: stream bridge answers every claimed request; bounded open

- Commits 4435054 (tests) + 7962c3f (fix). URI decoded after begin with
  allowMalformed; _handleOpen try/finally (incl. throwing size); open bounded by
  @visibleForTesting StreamBridge.openTimeout (30 s), late sources closed.
  SEEK unchanged (review).
- Local RED was compile-level only: bt/libmpv-2.dll lacks patch 0006, so the two
  bridge integration tests skip locally; behaviour RED/GREEN needs CI.
- Residual risks: hung READ still blocks stop; slow openers > 30 s fail.
