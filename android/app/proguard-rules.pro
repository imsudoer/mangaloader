# flutter_local_notifications persists scheduled notifications as Gson JSON and
# restores them from BOOT_COMPLETED / MY_PACKAGE_REPLACED receivers. Without the
# generic signature the anonymous TypeToken loses its type parameter and Gson
# throws "Missing type parameter", crashing the process on every app update and
# device boot.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}