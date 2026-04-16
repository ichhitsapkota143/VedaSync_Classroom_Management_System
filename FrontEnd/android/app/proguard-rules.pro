# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# VLC player (native lib handling)
-keep class org.videolan.libvlc.** { *; }
-keep class org.videolan.vlc.** { *; }
-dontwarn org.videolan.libvlc.**
-dontwarn org.videolan.vlc.**

# Firebase (optional, if you use it)
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Prevent stripping of main activity and flutter engine
-keep class com.example.vedasync.MainActivity { *; }
-keep class io.flutter.embedding.engine.FlutterEngine { *; }

# Other common rules
-keep class androidx.lifecycle.** { *; }
-dontwarn androidx.lifecycle.**
