# ML Kit's accurate pose model is left out of the app (build.gradle.kts):
# the plugin's code still names its classes, on a path the app never takes
# (it always asks for the base model).
-dontwarn com.google.mlkit.vision.pose.accurate.**

# ML Kit brings WorkManager 2.7.0, which starts at app launch (androidx.startup)
# and opens its Room 2.2.5 database. Room creates the generated
# WorkDatabase_Impl with Class.newInstance(), so it needs the no-argument
# constructor. Room's own rule (-keep class * extends RoomDatabase) keeps the
# class but, in R8 full mode (AGP 8's default), not its constructor: release
# builds crashed at launch with "Failed to create an instance of
# androidx.work.impl.WorkDatabase" (versions 0.48.0-0.51.x).
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
