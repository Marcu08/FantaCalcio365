package it.fantacalcio365.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import it.fantacalcio365.ui.AppViewModel

// Schermata 11 — Strumenti amministrativi (solo is_admin, §12).
// Le operazioni sensibili (ingestione, correzioni) passano dalle Edge
// Functions; qui si espongono i comandi e i log di controllo.
@Composable
fun AdminScreen(vm: AppViewModel) {
    val profile by vm.profile.collectAsState()

    if (profile?.isAdmin != true) {
        Text("Accesso riservato agli amministratori", Modifier.padding(16.dp))
        return
    }

    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Strumenti amministrativi", style = MaterialTheme.typography.titleLarge)
        Text(
            "Sincronizzazione risultati, blocco giornate e correzioni ufficiali " +
            "sono eseguiti dalle funzioni server (cron-tasks). Qui è possibile " +
            "verificare anomalie e forzare il blocco manuale di una giornata.",
            style = MaterialTheme.typography.bodySmall,
        )

        // Blocco manuale di una giornata (§9): valida solo per admin,
        // eseguita via RPC con service_role
        var matchday by remember { mutableStateOf("1") }
        OutlinedTextField(
            matchday, { matchday },
            label = { Text("Giornata da bloccare") },
        )
        Button(
            enabled = matchday.toIntOrNull() != null,
            onClick = { /* RPC lock_matchday via service_role, in arrivo */ },
        ) { Text("Blocca giornata") }
    }
}
