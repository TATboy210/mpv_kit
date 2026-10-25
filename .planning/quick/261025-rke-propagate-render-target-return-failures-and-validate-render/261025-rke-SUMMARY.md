---
quick_id: 261025-rke
status: complete
commit: ddbf2a8
---

# 261025-rke: propagate render target failures; validate render_vk; roll back timeline value

- Commits 1517130 (native, 0001/0004) + ddbf2a8 (plugin rollback).
- done_frame returns bool; render fails with MPV_ERROR_GENERIC when hold_ex
  fails; render_vk rejects bad extension params and NULL signal_semaphore
  (previously a libplacebo assert); reused wrapper takes the current signal
  value; render_vk.h comment updated in both copies (layout unchanged).
- Smoke: NULL semaphore case (both variants). Native verification pending CI.
