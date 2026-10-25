---
quick_id: 261025-rkd
status: complete
commit: 5b58792
---

# 261025-rkd: stream bridge cancel-after-close UAF, open leak, seek desync (0006)

- s_close detaches the cancel callback before close_fn; bridge_open sends CLOSE
  and returns LOADING_FAILED when calloc fails; bridge_seek fails when the host
  lands on another offset (behaviour change, in UPSTREAM.md).
- Tests: opens == closes after playback, rejected OPEN, 10x loadfile/stop loop
  (waits for START_FILE first so stop always yields END_FILE; ids budgeted).
- Deviation: the review's cond_signal concern was moot (the helper already
  broadcasts). The UAF race is a stress test for ASan, not a guaranteed RED;
  the calloc path has no test.
- Verification: PATCH-DRIFT OK locally; native build/tests pending on CI.
