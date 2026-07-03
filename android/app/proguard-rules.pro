# ── Bhromon R8 / ProGuard rules ─────────────────────────────────────────────
# Flutter engine & embedding (reflection-based plugin registration)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase (Crashlytics, Firestore, Messaging, Remote Config rely on reflection)
-keep class com.google.firebase.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes EnclosingMethod,InnerClasses

# App classes (method-channel callbacks referenced by name)
-keep class com.bhromon.app.** { *; }

# flutter_local_notifications — scheduled notifications are serialized with Gson
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# workmanager — background isolate callbacks
-keep class be.tramckrijte.workmanager.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }

# MapLibre GL native bindings (JNI callbacks referenced from native code)
-keep class org.maplibre.** { *; }
-keep class com.mapbox.** { *; }
-dontwarn org.maplibre.**
-dontwarn com.mapbox.**

# flutter_secure_storage / androidx.security (Tink keyset reflection)
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# Ignore Play Core deferred-components missing class warnings
-dontwarn com.google.android.play.core.**

# Misc warnings from legacy transitive deps
-dontwarn sun.misc.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
