package it.fantacalcio365.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import it.fantacalcio365.ui.formatKickoff
import it.fantacalcio365.ui.AppViewModel

// Schermata 1 — Home: prossime partite + riepilogo punti
@Composable
fun HomeScreen(vm: AppViewModel, onOpenMatch: (String) -> Unit, onOpenCalendar: () -> Unit) {
    LaunchedEffect(Unit) { vm.refresh() }
    val matches by vm.matches.collectAsState()
    val teams by vm.teams.collectAsState()
    val scores by vm.scores.collectAsState()
    val profile by vm.profile.collectAsState()

    val upcoming = matches.filter { it.status == "SCHEDULED" }.take(5)
    val myTotal = scores.sumOf { it.total }

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text(
                        "Ciao ${profile?.username ?: ""}",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        "Punti stagionali: ${"%.1f".format(myTotal)}",
                        style = MaterialTheme.typography.headlineSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Text(
                        "La classifica è cumulativa: i punti di tutte le giornate si sommano.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        item { Text("Prossime partite", style = MaterialTheme.typography.titleMedium) }

        if (upcoming.isEmpty()) {
            item {
                TextButton(onClick = onOpenCalendar) { Text("Vai al calendario") }
            }
        }

        items(upcoming, key = { it.id }) { m ->
            Card(modifier = Modifier.fillMaxWidth(), onClick = { onOpenMatch(m.id) }) {
                Column(Modifier.padding(16.dp)) {
                    Text(
                        "${teams[m.homeTeamId]?.shortName ?: "?"} - ${teams[m.awayTeamId]?.shortName ?: "?"}",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text("Giornata ${m.matchday} · ${formatKickoff(m.kickoffAt)}")
                    Text(
                        if (m.isLocked) "Pronostici bloccati" else "Pronostici modificabili",
                        style = MaterialTheme.typography.bodySmall,
                        color = if (m.isLocked) MaterialTheme.colorScheme.error
                        else MaterialTheme.colorScheme.secondary,
                    )
                }
            }
        }
    }
}
