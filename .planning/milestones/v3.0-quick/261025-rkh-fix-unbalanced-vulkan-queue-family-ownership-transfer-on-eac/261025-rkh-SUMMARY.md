---
quick_id: 261025-rkh
status: complete
commit: 12b5009
---

# 261025-rkh: always use VK_QUEUE_FAMILY_EXTERNAL for shared images

- Plugin passes EXTERNAL from the first frame; smoke renders twice into one
  image with EXTERNAL and acquires from EXTERNAL before read-back.
- No automated RED (lavapipe single family; pinned validation layers accept
  IGNORED). Assumptions verified against libplacebo source and the Vulkan spec
  (see PLAN review revisions).
