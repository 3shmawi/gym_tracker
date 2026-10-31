import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("staging") {
            dimension = "flavor-type"
            applicationId = "com.mohager.gymtracker.stg"
            resValue(type = "string", name = "app_name", value = "Gym Tracker Stg")
        }
        create("prod") {
            dimension = "flavor-type"
            applicationId = "com.mohager.gymtracker"
            resValue(type = "string", name = "app_name", value = "Gym Tracker")
        }
    }

    buildFeatures.resValues = true
}