package it.fantacalcio365.data

import android.content.Context
import com.russhwolf.settings.SharedPreferencesSettings
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.gotrue.Auth
import io.github.jan.supabase.gotrue.SettingsSessionManager
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime
import it.fantacalcio365.BuildConfig

object SupabaseProvider {
    @Volatile
    private var initialized = false

    lateinit var client: io.github.jan.supabase.SupabaseClient
        private set

    fun init(context: Context) {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            val prefs = context.applicationContext.getSharedPreferences("fc365_auth", Context.MODE_PRIVATE)
            client = createSupabaseClient(
                supabaseUrl = BuildConfig.SUPABASE_URL,
                supabaseKey = BuildConfig.SUPABASE_ANON_KEY,
            ) {
                install(Auth) {
                    sessionManager = SettingsSessionManager(SharedPreferencesSettings(prefs))
                }
                install(Postgrest)
                install(Realtime)
            }
            initialized = true
        }
    }
}
