# ADR 0007 — GPL-3.0+ full bundle for optical discs

Status: accepted
Accepted: 2026-11-07 by the user (conversation decision)
Date: 2026-11-07
Related: ADR 0002 (historical LGPL self-built binaries), `NOTICE`, `README.md`,
`native/build/{build,package}.sh`, `packages/mpv_kit_libs/README.md`

## Context

The player must support CD-DA, DVD-Video menus, DVD-Audio, Blu-ray/UHD HDMV,
and VCD (DAT files only; mpv has no `vcd://` module).

* mpv gates CD-DA (`cdda`), DVD-Video (`dvdnav`) and DVD-Audio (`dvda`)
  behind `-Dgpl=true` (`native/mpv/meson.build`).
* The implementations are GPL: libcdio (GPL-3.0+),
  libdvdnav/libdvdread/libdvdcss (GPL-2.0+). There is no maintained
  permissive-licensed DVD navigation library; libbluray is LGPL but only
  handles Blu-ray.
* Blu-ray/UHD needs libbluray + libudfread (LGPL-2.1+); AACS/BD+ decryption
  uses libaacs/libbdplus (LGPL-2.1+) and a user-supplied key database.
* The application built on mpv_kit is open source and distributed.

## Decision

* The released native bundle is the **GPL-3.0-or-later full flavor**:
  mpv is built with `-Dgpl=true` and links libcdio, libdvdnav, libdvdread,
  libdvdcss, libbluray, libudfread, libaacs, libbdplus. FFmpeg stays LGPL;
  the combined binary is GPLv3 because libcdio is GPLv3.
* The Dart packages remain MIT. Applications that ship the bundle must be
  GPL-compatible and provide their corresponding source.
* BD-J (needs a JVM), `vcd://`, and HTTP/3 are out of scope. VCD content is
  played from `MPEGAV/*.DAT`.
* libcurl + nghttp2 + mbedTLS are built for HTTP/2, but `Player` keeps
  `curl-enabled=no` by default so the pre-0.42 network behavior is unchanged.
* `native/build/build.sh` and `package.sh` keep `MPV_KIT_FLAVOR=lgpl` for
  self-builders (the old `-Dgpl=false` contract). The release pipeline only
  publishes the GPL full flavor.
* Every bundle carries `LICENSE.GPL`, `LICENSE.LGPL`, third-party licenses,
  `SOURCE.txt` and the patches; releases also carry
  `sources-<tag>.tar.gz`.

## Consequences

* Closed-source applications can no longer use the published bundle; they
  must build the LGPL flavor themselves or point `MPV_KIT_LIBMPV_PATH` at
  an LGPL libmpv.
* The bundle grows by the disc stack (roughly 6–12 MB per target, to be
  measured) and the release matrix builds more dependencies.
* libdvdcss and AACS/BD+ helpers may be restricted in some jurisdictions;
  distributors are responsible for compliance.
* BD-J and `vcd://` remain unavailable.

## Alternatives considered

* **Keep the LGPL bundle** — rejects the CD/DVD requirement; no GPL
  component can enter.
* **Publish both LGPL and GPL flavors** — doubles CI, release assets and
  verification. The flavor switch is kept in the scripts so this can be
  enabled later without a rewrite.
* **Clean-room DVD navigation implementation** — the DVD-Video VM is large,
  specification- and patent-sensitive, and has no maintained permissive
  implementation. Rejected.
