# Regole ProGuard/R8 per Supabase/Ktor/kotlinx-serialization
-keepattributes *Annotation*, InnerClasses
-dontnote io.ktor.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class it.fantacalcio365.** {
    kotlinx.serialization.KSerializer serializer(...);
}
