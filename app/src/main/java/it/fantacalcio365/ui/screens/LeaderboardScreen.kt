package it.fantacalcio365.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.background
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import it.fantacalcio365.ui.AppViewModel
import it.fantacalcio365.ui.theme.*

// Schermata 7 — Classifica generale cumulativa con podio colorato
@Composable
fun LeaderboardScreen(vm: AppViewModel) {
    LaunchedEffect(Unit) { vm.refresh() }
    val lb by vm.leaderboard.collectAsState()

    Column(Modifier.fillMaxSize()) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
            Text("Classifica generale", style = MaterialTheme.typography.titleLarge)
            Text(
                "Somma cumulativa di tutte le giornate · spareggi: risultati esatti → marcatori",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        LazyColumn(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(lb.withIndex().toList(), key = { it.value.userId }) { (i, e) ->
                val medal = when (i) {
                    0 -> Oro; 1 -> Argento; 2 -> Bronzo; else -> null
                }
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = if (medal != null) CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    ) else CardDefaults.cardColors(),
                    elevation = CardDefaults.cardElevation(
                        defaultElevation = if (medal != null) 3.dp else 1.dp
                    ),
                ) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(38.dp)
                                .clip(CircleShape)
                                .background(medal ?: MaterialTheme.colorScheme.surfaceVariant),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                "${i + 1}",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = if (medal != null) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(e.username, style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Esatti: ${e.exactResults} · Marcatori: ${e.exactScorers}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text(
                                "%.0f".format(e.total),
                                style = MaterialTheme.typography.titleLarge,
                                color = MaterialTheme.colorScheme.primary,
                            )
                            Text("punti", style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}
