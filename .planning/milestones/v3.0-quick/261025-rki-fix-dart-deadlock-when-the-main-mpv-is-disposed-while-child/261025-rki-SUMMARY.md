---
quick_id: 261025-rki
status: complete
commit: 609c6e9
---

# 261025-rki: Mpv.dispose disposes child clients before terminating the core

- Private _children/_parent; dispose() disposes children (and grandchildren)
  first; doc comment notes the behaviour change.
- Test runs the scenario in a child process (fixture dispose_with_children.dart)
  with a 60 s kill timeout (15 s was too close to `dart run` start-up).
- RED: child process hung and was killed; GREEN: ~4 s. mpv/api_freeze/
  api_surface tests pass; dart analyze clean.
