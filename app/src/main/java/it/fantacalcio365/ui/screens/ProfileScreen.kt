package it.fantacalcio365.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import it.fantacalcio365.ui.AppViewModel

// Schermate 8+10 — Profilo: punteggi per giornata con spiegazione
// riga per riga del motivo dei punti (§13)
@Composable
fun ProfileScreen(vm: AppViewModel, onLogout: () -> Unit = {}, onOpenAdmin: () -> Unit = {}) {
    LaunchedEffect(Unit) { vm.refresh() }
    val profile by vm.profile.collectAsState()
    val scores by vm.scores.collectAsState()

    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Profilo", style = MaterialTheme.typography.titleLarge)
        Text(profile?.username ?: "", style = MaterialTheme.typography.titleMedium)
        Text(
            "Punti totali: ${"%.1f".format(scores.sumOf { it.total })}",
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.primary,
        )

        Text("Dettaglio per giornata", style = MaterialTheme.typography.titleMedium)

        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(scores, key = { it.toString() }) { s ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(
                            "Giornata — ${"%.1f".format(s.total)} pt" +
                                    if (s.isOfficial) " (ufficiale)" else " (provvisorio)",
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Text("1T+2T esatti: ${s.ptsHt + s.ptsHt2}", style = MaterialTheme.typography.bodySmall)
                        Text("Bonus marcatori: ${"%.1f".format(s.ptsScorers)}", style = MaterialTheme.typography.bodySmall)
                        Text("Porta inviolata: ${"%.1f".format(s.ptsCleanSheet)}", style = MaterialTheme.typography.bodySmall)
                        Text("Primo sostituto: ${s.ptsSub}", style = MaterialTheme.typography.bodySmall)
                        Text("Primo ammonito: ${s.ptsYellow}", style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        Spacer(Modifier.weight(1f))

        // Strumenti amministrativi (solo admin)
        if (profile?.isAdmin == true) {
            OutlinedButton(onClick = onOpenAdmin, modifier = Modifier.fillMaxWidth()) {
                Text("Strumenti amministrativi")
            }
            Spacer(Modifier.height(8.dp))
        }
        Button(onClick = { vm.logout { onLogout() } }, modifier = Modifier.fillMaxWidth()) {
            Text("Esci")
        }
    }
}
