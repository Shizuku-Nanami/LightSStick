# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }

# Google Play Core (Flutter deferred components)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# flutter_reactive_ble
-keep class com.signify.hue.** { *; }

# Protobuf (flutter_reactive_ble 依赖)
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# OkHttp / HTTP
-dontwarn okhttp3.**
-dontwarn okio.**

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }
