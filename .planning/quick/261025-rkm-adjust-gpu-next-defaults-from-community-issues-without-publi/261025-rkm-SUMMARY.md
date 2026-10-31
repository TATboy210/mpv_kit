---
quick_id: 261025-rkm
status: complete
commit: c126862
---

# 261025-rkm: hwdec-codecs default excludes ffv1 (mpv #18255)

- Player factory default 'hwdec-codecs' = vd_lavc.c default minus ffv1;
  hdr-compute-peak=no comment cites #17626. User-visible default change.
- Local runtime default (v0.41.0-689) equals vd_lavc.c:176, so Test 1 compares
  against the runtime default. RED: Test 1 failed on ffv1; mutation check on
  Test 3. 30 tests pass; analyze clean.
