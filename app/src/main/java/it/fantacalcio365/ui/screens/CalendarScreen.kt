package it.fantacalcio365.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import it.fantacalcio365.ui.formatKickoff
import it.fantacalcio365.ui.AppViewModel

// Schermata 2 — Calendario raggruppato per giornata
@Composable
fun CalendarScreen(vm: AppViewModel, onOpenMatch: (String) -> Unit) {
    LaunchedEffect(Unit) { vm.refresh() }
    val matches by vm.matches.collectAsState()
    val teams by vm.teams.collectAsState()

    val byMatchday = matches.groupBy { it.matchday }.toSortedMap()

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        byMatchday.forEach { (matchday, ms) ->
            val hasResult = ms.any { it.ftHome != null }
            item(key = "g$matchday") {
                Row(
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .clip(RoundedCornerShape(999.dp))
                        .background(
                            if (hasResult) MaterialTheme.colorScheme.secondaryContainer
                            else MaterialTheme.colorScheme.primaryContainer
                        )
                        .padding(horizontal = 14.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "Giornata $matchday",
                        style = MaterialTheme.typography.labelLarge,
                        color = if (hasResult) MaterialTheme.colorScheme.secondary
                        else MaterialTheme.colorScheme.primary,
                    )
                }
            }
            items(ms, key = { it.id }) { m ->
                val confirmed = m.status == "CONFIRMED"
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { onOpenMatch(m.id) },
                    elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                ) {
                    Row(
                        Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                teams[m.homeTeamId]?.shortName ?: "?",
                                style = MaterialTheme.typography.bodyLarge,
                                fontWeight = FontWeight.Medium,
                            )
                            Text(
                                teams[m.awayTeamId]?.shortName ?: "?",
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (m.ftHome != null && m.ftAway != null) {
                            Text(
                                "${m.ftHome}  -  ${m.ftAway}",
                                style = MaterialTheme.typography.titleMedium,
                                color = if (confirmed) MaterialTheme.colorScheme.onSurface
                                else MaterialTheme.colorScheme.tertiary,
                            )
                        } else {
                            Column(horizontalAlignment = Alignment.End) {
                                Text(
                                    when (m.status) {
                                        "POSTPONED" -> "Rinviata"
                                        "LIVE" -> " ● LIVE"
                                        else -> formatKickoff(m.kickoffAt)
                                    },
                                    style = MaterialTheme.typography.bodySmall,
                                    color = if (m.status == "LIVE") MaterialTheme.colorScheme.error
                                    else MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
