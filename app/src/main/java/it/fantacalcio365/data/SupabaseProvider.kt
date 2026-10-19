package it.fantacalcio365.data

import io.github.jan.supabase.gotrue.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.realtime.Realtime
import it.fantacalcio365.BuildConfig

// Client Supabase: solo URL e chiave ANONIMA (pubblica, protetta da RLS).
// Nessuna chiave del provider calcistico nell'app (§12).
object SupabaseProvider {
    val client = createSupabaseClient(
        supabaseUrl = BuildConfig.SUPABASE_URL,
        supabaseKey = BuildConfig.SUPABASE_ANON_KEY,
    ) {
        install(Auth)
        install(Postgrest)
        install(Realtime)
    }
}
