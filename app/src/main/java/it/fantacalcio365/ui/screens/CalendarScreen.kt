package it.fantacalcio365.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import it.fantacalcio365.ui.formatKickoff
import it.fantacalcio365.ui.AppViewModel

// Schermata 2 — Calendario della Serie A, raggruppato per giornata
@Composable
fun CalendarScreen(vm: AppViewModel, onOpenMatch: (String) -> Unit) {
    LaunchedEffect(Unit) { vm.refresh() }
    val matches by vm.matches.collectAsState()
    val teams by vm.teams.collectAsState()

    val byMatchday = matches.groupBy { it.matchday }.toSortedMap()

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        byMatchday.forEach { (matchday, ms) ->
            item(key = "g$matchday") {
                Text(
                    "Giornata $matchday",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            items(ms, key = { it.id }) { m ->
                val confirmed = m.status == "CONFIRMED"
                Card(modifier = Modifier.fillMaxWidth(), onClick = { onOpenMatch(m.id) }) {
                    Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column {
                            Text(
                                "${teams[m.homeTeamId]?.shortName ?: "?"} - ${teams[m.awayTeamId]?.shortName ?: "?"}",
                                style = MaterialTheme.typography.bodyLarge,
                            )
                            Text(
                                formatKickoff(m.kickoffAt),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Column(horizontalAlignment = androidx.compose.ui.Alignment.End) {
                            if (m.ftHome != null && m.ftAway != null) {
                                Text("${m.ftHome} - ${m.ftAway}", style = MaterialTheme.typography.titleMedium)
                                Text(
                                    if (confirmed) "Ufficiale" else "Provvisorio",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = if (confirmed) MaterialTheme.colorScheme.secondary
                                    else MaterialTheme.colorScheme.tertiary,
                                )
                            } else {
                                Text(
                                    when (m.status) {
                                        "POSTPONED" -> "Rinviata"
                                        "LIVE" -> "In corso"
                                        else -> "—"
                                    },
                                    style = MaterialTheme.typography.bodySmall,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
