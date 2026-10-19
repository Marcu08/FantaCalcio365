package it.fantacalcio365.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import it.fantacalcio365.ui.AppViewModel

// Schermata 7 — Classifica generale cumulativa (§10).
// Ordinamento con spareggi approvati: punti → risultati esatti →
// marcatori esatti → prima compilazione.
@Composable
fun LeaderboardScreen(vm: AppViewModel) {
    LaunchedEffect(Unit) { vm.refresh() }
    val lb by vm.leaderboard.collectAsState()

    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Text("Classifica generale", style = MaterialTheme.typography.titleLarge)
        Text(
            "Somma cumulativa di tutte le giornate della stagione",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(12.dp))

        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(lb.withIndex().toList(), key = { it.value.userId }) { (i, e) ->
                Card(Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "${i + 1}º",
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.width(48.dp),
                        )
                        Column(Modifier.weight(1f)) {
                            Text(e.username, style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Esatti: ${e.exactResults} · Marcatori: ${e.exactScorers}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Text(
                            "${"%.1f".format(e.total)} pt",
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }
    }
}
