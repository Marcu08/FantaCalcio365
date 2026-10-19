package it.fantacalcio365.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import it.fantacalcio365.ui.formatKickoff
import it.fantacalcio365.ui.AppViewModel
import java.time.Instant
import java.time.ZoneId

// Schermata 1 — Home: hero punti, countdown blocco, prossime partite
@Composable
fun HomeScreen(vm: AppViewModel, onOpenMatch: (String) -> Unit, onOpenCalendar: () -> Unit) {
    LaunchedEffect(Unit) { vm.refresh() }
    val matches by vm.matches.collectAsState()
    val teams by vm.teams.collectAsState()
    val scores by vm.scores.collectAsState()
    val profile by vm.profile.collectAsState()

    val upcoming = matches.filter { it.status == "SCHEDULED" }
        .sortedBy { it.kickoffAt }
    val nextMatch = upcoming.firstOrNull()
    val myTotal = scores.sumOf { it.total }

    // Countdown al blocco della giornata della prossima partita
    var countdown by remember { mutableStateOf("—") }
    LaunchedEffect(nextMatch?.id) {
        val target = nextMatch?.lockedAt?.let { Instant.parse(it) }
            ?: nextMatch?.kickoffAt?.let { Instant.parse(it) } ?: return@LaunchedEffect
        while (true) {
            val d = java.time.Duration.between(Instant.now(), target)
            countdown = if (d.isNegative) "In corso" else {
                val days = d.toDays()
                val h = d.toHours() % 24
                val m = d.toMinutes() % 60
                if (days > 0) "$days g $h h $m m" else "$h h $m m"
            }
            kotlinx.coroutines.delay(30_000)
        }
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            // Hero: punti stagionali su gradiente notte
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(24.dp))
                    .background(
                        Brush.linearGradient(listOf(Color(0xFF0B1F3A), Color(0xFF1565C0)))
                    )
                    .padding(20.dp),
            ) {
                Column {
                    Text(
                        "Ciao ${profile?.username ?: ""} 👋",
                        style = MaterialTheme.typography.titleMedium,
                        color = Color.White.copy(alpha = 0.85f),
                    )
                    Text(
                        "%.0f".format(myTotal),
                        style = MaterialTheme.typography.headlineMedium,
                        color = Color(0xFFF9A825),
                    )
                    Text(
                        "punti stagionali",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.7f),
                    )
                }
                Column(
                    modifier = Modifier.align(Alignment.BottomEnd),
                    horizontalAlignment = Alignment.End,
                ) {
                    Text("Cumulativa", style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.6f))
                }
            }
        }

        if (nextMatch != null) {
            item {
                // Countdown chiusura pronostici
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    ),
                ) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(38.dp)
                                .clip(CircleShape)
                                .background(MaterialTheme.colorScheme.primary),
                            contentAlignment = Alignment.Center,
                        ) { Text("⏱", color = Color.White) }
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text("Chiudono i pronostici tra", style = MaterialTheme.typography.labelSmall)
                            Text(countdown, style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
        }

        item {
            Text(
                "Prossime partite",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(top = 4.dp),
            )
        }

        if (upcoming.isEmpty()) {
            item {
                Card(Modifier.fillMaxWidth()) {
                    Column(
                        Modifier.padding(24.dp).fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text("🙌", style = MaterialTheme.typography.headlineMedium)
                        Text("Nessuna partita in programma", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "Torna quando viene pubblicato il nuovo calendario",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
        }

        items(upcoming.take(5), key = { it.id }) { m ->
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = MaterialTheme.shapes.medium,
                elevation = CardDefaults.cardElevation(defaultElevation = 1.dp),
                onClick = { onOpenMatch(m.id) },
            ) {
                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1.2f)) {
                        Text(
                            teams[m.homeTeamId]?.name ?: "?",
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Text(
                            teams[m.awayTeamId]?.name ?: "?",
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.weight(1f)) {
                        Text(
                            formatKickoff(m.kickoffAt).substringBefore(" "),
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text(
                            formatKickoff(m.kickoffAt).substringAfter(" "),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        AssistChip(
                            onClick = {},
                            enabled = false,
                            label = {
                                Text(
                                    if (m.isLocked) "BLOCCATA" else "GIORNATA ${m.matchday}",
                                    style = MaterialTheme.typography.labelSmall,
                                    fontWeight = FontWeight.Bold,
                                )
                            },
                            colors = AssistChipDefaults.assistChipColors(
                                disabledLabelColor = if (m.isLocked) MaterialTheme.colorScheme.error
                                else MaterialTheme.colorScheme.secondary,
                            ),
                            border = null,
                        )
                    }
                }
            }
        }

        item {
            TextButton(onClick = onOpenCalendar, modifier = Modifier.fillMaxWidth()) {
                Text("Vedi tutto il calendario →")
            }
        }
    }
}
