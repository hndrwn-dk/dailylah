# Release shrinking (R8) keeps these: plugins reach them by reflection or from native code.
# flutter_local_notifications stores schedules with Gson.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
# WorkManager plugin and home screen widget.
-keep class dev.fluttercommunity.workmanager.** { *; }
-keep class es.antonborri.home_widget.** { *; }
-keep class androidx.work.** { *; }
# Our own Kotlin (widget provider, app launcher channel).
-keep class com.tursinalabs.dailylah.** { *; }
-dontwarn com.google.errorprone.annotations.**
