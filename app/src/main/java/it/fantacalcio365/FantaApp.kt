package it.fantacalcio365

import android.app.Application
import it.fantacalcio365.data.SupabaseProvider

class FantaApp : Application() {
    override fun onCreate() {
        super.onCreate()
        SupabaseProvider.init(this)
    }
}
