---
quick_id: 261025-rkf
status: complete
commit: 13c130b
---

# 261025-rkf: keep host ICC across option changes in gpu-next libmpv

- priv->libmpv_icc re-applied in update_icc_opts; update_auto_profile and the
  profile_auto unload skip while a host profile is set; user --icc-profile wins.
- libmpv_reset stays immediate (review), comment fixed. #16818 not applicable.
- PATCH-DRIFT OK; native verification pending CI.
