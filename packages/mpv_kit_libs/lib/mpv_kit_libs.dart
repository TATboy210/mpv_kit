/// Prebuilt libmpv for mpv_kit.
///
/// Depending on this package is all that is needed: its build hook bundles
/// libmpv and its dependencies into the application, where
/// `MpvLibrary.open()` from `package:mpv_kit` finds them by name.
library;

export 'src/bundles.dart' show bundleTag;
