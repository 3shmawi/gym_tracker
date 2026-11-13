# ML Kit's accurate pose model is left out of the app (build.gradle.kts):
# the plugin's code still names its classes, on a path the app never takes
# (it always asks for the base model).
-dontwarn com.google.mlkit.vision.pose.accurate.**
