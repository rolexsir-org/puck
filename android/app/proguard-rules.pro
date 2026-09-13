# Puck -- ProGuard / R8 rules (Android release builds)
#
# Puck uses no reflection and no dynamic serialisation: the Groq and
# Open-Meteo payloads are hand-built maps and hand-parsed. That means R8 can
# shrink aggressively without special cases.

# ---- Keep the Flutter bridge ------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# ---- Keep platform-channel entry points -------------------------------------
# Plugins call into Dart by name; their native registration classes must
# survive shrinking.
-keepclassmembers class io.flutter.plugin.common.PluginRegistry$** { *; }
-keep class * extends io.flutter.embedding.engine.plugins.FlutterPlugin { *; }

# ---- Kotlin metadata ---------------------------------------------------------
-keep class kotlin.Metadata { *; }
-dontwarn kotlinx.**

# ---- Warnings we accept ------------------------------------------------------
# speech_to_text and geolocator reference optional Google Play / ML Kit
# classes that are not present in every build variant.
-dontwarn com.google.android.gms.**
-dontwarn com.google.mlkit.**

# ---- Debuggability -----------------------------------------------------------
# Keep source file + line numbers so Play Console stack traces are readable.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
