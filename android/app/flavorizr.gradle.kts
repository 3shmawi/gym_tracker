import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("staging") {
            dimension = "flavor-type"
            applicationId = "com.mohager.azm.stg"
            resValue(type = "string", name = "app_name", value = "Azm Stg")
        }
        create("prod") {
            dimension = "flavor-type"
            applicationId = "com.mohager.azm"
            resValue(type = "string", name = "app_name", value = "Azm")
        }
    }

    buildFeatures.resValues = true
}