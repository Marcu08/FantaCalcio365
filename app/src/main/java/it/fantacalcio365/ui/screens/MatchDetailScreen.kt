package it.fantacalcio365.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import it.fantacalcio365.ui.formatKickoff
import it.fantacalcio365.ui.AppViewModel
import it.fantacalcio365.data.Prediction
import it.fantacalcio365.data.PredictionPlayer
import it.fantacalcio365.data.Score

// Schermata 3 — Dettaglio partita: risultato, scadenza, stato schedina
@Composable
fun MatchDetailScreen(vm: AppViewModel, matchId: String, onBack: () -> Unit,
                      onOpenSchedina: (String) -> Unit = {}) {
    LaunchedEffect(Unit) { vm.refresh() }
    val matches by vm.matches.collectAsState()
    val teams by vm.teams.collectAsState()
    val m = matches.firstOrNull { it.id == matchId }

    // Schedina salvata (owner-only, leggibile anche a partita bloccata)
    var schedinaState by remember { mutableStateOf<Pair<Prediction, List<PredictionPlayer>>?>(null) }
    // Punti assegnati per questa partita (se calcolati)
    var myScore by remember { mutableStateOf<Score?>(null) }
    LaunchedEffect(matchId) {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            schedinaState = vm.repo_.myPrediction(matchId)
            myScore = vm.repo_.myScores().firstOrNull { it.matchId == matchId }
        }
    }

    if (m == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        TextButton(onClick = onBack) { Text("< Indietro") }

        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    "${teams[m.homeTeamId]?.name ?: "?"} - ${teams[m.awayTeamId]?.name ?: "?"}",
                    style = MaterialTheme.typography.titleLarge,
                )
                Text("Giornata ${m.matchday} · ${formatKickoff(m.kickoffAt)}",
                    style = MaterialTheme.typography.bodySmall)
                if (m.ftHome != null && m.ftAway != null) {
                    Spacer(Modifier.height(8.dp))
                    Text("${m.ftHome} - ${m.ftAway}", style = MaterialTheme.typography.displaySmall)
                    if (m.htHome != null && m.htAway != null) {
                        Text(
                            "1° tempo: ${m.htHome} - ${m.htAway}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // Stato schedina: chiara distinzione modificabile / bloccato (§9, §13)
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text("Schedina", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(4.dp))

                // La propria schedina (leggibile anche dopo il blocco)
                val saved = schedinaState
                if (saved != null) {
                    val (p, players) = saved
                    Text(
                        "1T ${p.htHome}-${p.htAway} · 2T ${p.ht2Home}-${p.ht2Away}",
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Text(
                        "Giocatori: ${players.count { it.isMarkedScorer } } marcatori dichiarati su ${players.size}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                } else if (!m.isLocked) {
                    Text("Nessun pronostico salvato per questa partita.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }

                if (m.isLocked) {
                    Text("Bloccata all'inizio della giornata: non più modificabile.",
                        color = MaterialTheme.colorScheme.error)
                } else {
                    Text("Modificabile fino al blocco della giornata (§9).",
                        color = MaterialTheme.colorScheme.secondary)
                    Spacer(Modifier.height(12.dp))
                    Button(onClick = { onOpenSchedina(m.id) }) {
                        Text(if (saved != null) "Modifica pronostico" else "Compila pronostico")
                    }
                }

                // Punti assegnati (quando calcolati dal server)
                val s = myScore
                if (s != null) {
                    Spacer(Modifier.height(10.dp))
                    Text("Punti ottenuti — ${"%.1f".format(s.total)}",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary)
                    Text("1T+2T: ${s.ptsHt + s.ptsHt2} · marcatori: ${"%.1f".format(s.ptsScorers)}" +
                            " · porta inviolata: ${"%.1f".format(s.ptsCleanSheet)}" +
                            " · sostituto: ${s.ptsSub} · ammonito: ${s.ptsYellow}" +
                            (if (s.isOfficial) " (ufficiale)" else " (provvisorio)"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
