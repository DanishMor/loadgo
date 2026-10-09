# Keep rules for the release build (minify + shrink are on). Flutter and the
# Firebase plugins ship their own consumer rules; add a line here only when a
# release build crashes with ClassNotFound, and say why.
-keep class io.flutter.** { *; }
-keep class org.webrtc.** { *; }
