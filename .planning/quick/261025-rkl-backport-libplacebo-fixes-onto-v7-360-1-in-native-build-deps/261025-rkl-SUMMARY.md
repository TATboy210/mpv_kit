---
quick_id: 261025-rkl
status: complete
commit: a7ba508
---

# 261025-rkl: 14 libplacebo backports onto v7.360.1

- native/deps/libplacebo/ (14 patches + SHA256SUMS), applied by deps.sh with GNU
  patch, --fuzz=0, exact count 14. Cache keys hash the directory; release
  installs patch/gpatch.
- Deviation: f89d3224a2 needed fuzz 1, regenerated against 7.360.1 (same
  logic). Stored diffs re-fetched and byte-compared with upstream.
- Verified locally: ordered --fuzz=0 apply on a clean unpack; deps.sh snippet.
  macOS/Windows application is only exercised by release.yml (needs a manual
  workflow_dispatch).
