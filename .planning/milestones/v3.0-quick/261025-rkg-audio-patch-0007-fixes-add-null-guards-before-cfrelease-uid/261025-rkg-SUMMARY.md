---
quick_id: 261025-rkg
status: complete
commit: ebf5a6e
---

# 261025-rkg: CoreAudio NULL guards (0007); WASAPI note vs upstream 4dfee61

- ca_select_device fails cleanly on a NULL uid; ca_get_str returns an error for
  a NULL string (deviation: cfstr_get_cstr(NULL) is already safe, the real risk
  was callers treating NULL as a device name).
- No test reaches these paths; macOS CI build pending. PATCH-DRIFT OK.
