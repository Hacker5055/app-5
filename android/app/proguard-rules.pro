# Flutter / plugin keep rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# androidx.exifinterface is reached through the MethodChannel bridge only.
-keep class androidx.exifinterface.** { *; }

# PointyCastle: keep the cipher registries that are resolved reflectively.
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# The app ships no reflection-based serialisation; strip debug metadata.
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable
