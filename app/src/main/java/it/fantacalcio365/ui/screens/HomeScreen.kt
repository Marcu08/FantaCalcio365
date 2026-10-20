package it.fantacalcio365.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LockClock
import androidx.compose.material.icons.filled.Timer
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
import it.fantacalcio365.ui.components.*
import it.fantacalcio365.ui.theme.*
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

    // Countdown al blocco: mostrato solo se calcolabile in modo affidabile (§7 UX)
    var countdown by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(nextMatch?.id) {
        val target = nextMatch?.lockedAt?.let { Instant.parse(it) }
            ?: nextMatch?.kickoffAt?.let { Instant.parse(it) } ?: return@LaunchedEffect
        while (true) {
            val d = java.time.Duration.between(Instant.now(), target)
            countdown = if (d.isNegative) null else {
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
            // Hero: punti stagionali su superficie notte
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(24.dp))
                    .background(
                        Brush.linearGradient(listOf(Color(0xFF0B1F3A), Color(0xFF134E8B)))
                    )
                    .padding(20.dp),
            ) {
                Column {
                    Text(
                        "Ciao ${profile?.username ?: ""}",
                        style = MaterialTheme.typography.titleMedium,
                        color = Color.White.copy(alpha = 0.85f),
                    )
                    Text(
                        "%.0f".format(myTotal),
                        style = MaterialTheme.typography.headlineMedium,
                        color = Accento,
                    )
                    Text(
                        "punti stagionali · classifica cumulativa",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.7f),
                    )
                }
                Icon(
                    Icons.Default.LockClock,
                    contentDescription = "Classifica stagionale",
                    tint = Color.White.copy(alpha = 0.25f),
                    modifier = Modifier.align(Alignment.TopEnd).size(34.dp),
                )
            }
        }

        if (nextMatch != null && countdown != null) {
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.primaryContainer
                    ),
                ) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.Timer,
                            contentDescription = "Tempo rimasto",
                            tint = MaterialTheme.colorScheme.primary,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text("I pronostici della giornata ${nextMatch.matchday} chiudono tra",
                                style = MaterialTheme.typography.labelSmall)
                            Text(countdown!!, style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.primary,
                                fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }

        item { SectionHeader("Prossime partite") }

        if (upcoming.isEmpty()) {
            item { EmptyState("Nessuna partita in programma",
                "Torna quando viene pubblicato il nuovo calendario") }
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
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            TeamCrest(teams[m.homeTeamId], Modifier.size(20.dp))
                            Spacer(Modifier.width(6.dp))
                            Text(teams[m.homeTeamId]?.name ?: "?",
                                style = MaterialTheme.typography.titleSmall)
                        }
                        Spacer(Modifier.height(4.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            TeamCrest(teams[m.awayTeamId], Modifier.size(20.dp))
                            Spacer(Modifier.width(6.dp))
                            Text(teams[m.awayTeamId]?.name ?: "?",
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
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
                        Spacer(Modifier.height(4.dp))
                        if (m.isLocked) {
                            StatusChip("BLOCCATA", MaterialTheme.colorScheme.error)
                        } else {
                            StatusChip("GIORNATA ${m.matchday}", MaterialTheme.colorScheme.secondary)
                        }
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
