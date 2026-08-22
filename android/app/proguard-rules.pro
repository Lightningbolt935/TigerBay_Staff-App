# TigerBay Staff — R8/ProGuard rules
#
# mobile_scanner 5.x ships consumer rules that only keep com.google.mlkit.*
# (single level). That misses every subpackage, so under R8 full mode MLKit's
# barcode component classes get renamed (BarcodeScannerImpl -> i5.a etc.),
# which breaks Google's string/reflection-based component registration.
# Result on device: "Attempt to invoke virtual method 'i5.a i5.e.a(e5.b)'
# on a null object reference" whenever the scanner starts.
#
# Release builds currently run with minification disabled (see
# build.gradle.kts); these rules are the safety net if it is ever re-enabled.

-keep class com.google.mlkit.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }

# GMS-internal MLKit plumbing (registry, executors, bundled model variant).
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode_bundled.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }

# CameraX wiring used by mobile_scanner.
-keep class androidx.camera.core.** { *; }
-keep class androidx.camera.camera2.** { *; }
-keep class androidx.camera.lifecycle.** { *; }

-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.libraries.barhopper.**
