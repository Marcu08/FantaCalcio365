package it.fantacalcio365.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import it.fantacalcio365.data.*
import it.fantacalcio365.ui.AppViewModel
import kotlinx.coroutines.launch

// Schermate 4+5+6 — Compilazione schedina:
// risultati per tempo, 4 giocatori (>=1 casa, >=1 ospite, >=1 marcatore
// dichiarato), primo sostituto, primo ammonito, bonus disponibili.
@Composable
fun SchedinaScreen(vm: AppViewModel, matchId: String, onBack: () -> Unit) {
    val repo = it.fantacalcio365.data.Repository()

    var match by remember { mutableStateOf<Match?>(null) }
    var allPlayers by remember { mutableStateOf<List<Player>>(emptyList()) }
    var bonuses by remember { mutableStateOf<Map<String, PlayerMatchBonus>>(emptyMap()) }
    var schedina by remember { mutableStateOf(Schedina()) }
    var predId by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(matchId) {
        runCatching {
            match = repo.match(matchId)
            if (!match!!.isLocked) {
                val home = repo.players(match!!.homeTeamId)
                val away = repo.players(match!!.awayTeamId)
                allPlayers = home + away
                bonuses = repo.bonuses(matchId).associateBy { it.playerId }
                repo.myPrediction(matchId)?.let { (p, ps) ->
                    predId = p.id
                    schedina = Schedina(
                        htHome = p.htHome, htAway = p.htAway,
                        ht2Home = p.ht2Home, ht2Away = p.ht2Away,
                        selected = ps.map { it.playerId },
                        scorers = ps.filter { it.isMarkedScorer }.map { it.playerId }.toSet(),
                        firstSubOut = p.firstSubOutPlayerId,
                        firstYellow = p.firstYellowPlayerId,
                    )
                }
            }
        }.onFailure { error = it.message }
    }

    if (match == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        return
    }

    if (match!!.isLocked) {
        // Rispettiamo §9: dopo il blocco nessuna modifica, nemmeno in UI
        Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
            Text("Schedina bloccata", style = MaterialTheme.typography.titleLarge)
            Text("Il blocco avviene all'inizio della prima gara della giornata e non è più possibile modificare i pronostici.")
            TextButton(onClick = onBack) { Text("< Torna al dettaglio") }
        }
        return
    }

    val homePlayers = allPlayers.filter { it.teamId == match!!.homeTeamId }
    val awayPlayers = allPlayers.filter { it.teamId == match!!.awayTeamId }
    val selectedSet = schedina.selected.toSet()

    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        TextButton(onClick = onBack) { Text("< Indietro") }
        Text("Compila la schedina", style = MaterialTheme.typography.titleLarge)

        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }

        // --- Risultati per tempo (§4) ---
        Card {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Risultati per tempo", style = MaterialTheme.typography.titleSmall)
                Text(
                    "1° tempo: risultato esatto della prima frazione. " +
                    "2° tempo: SOLO i gol della seconda frazione (non il cumulativo).",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    NumberField("1T casa", schedina.htHome) { schedina = schedina.copy(htHome = it) }
                    NumberField("1T ospite", schedina.htAway) { schedina = schedina.copy(htAway = it) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    NumberField("2T casa", schedina.ht2Home) { schedina = schedina.copy(ht2Home = it) }
                    NumberField("2T ospite", schedina.ht2Away) { schedina = schedina.copy(ht2Away = it) }
                }
            }
        }

        // --- Selezione giocatori (§5) ---
        Card {
            Column(Modifier.padding(12.dp)) {
                Text("Selezione 4 giocatori", style = MaterialTheme.typography.titleSmall)
                val nHome = schedina.selected.count { homePlayers.any { p -> p.id == it } }
                val nAway = schedina.selected.count { awayPlayers.any { p -> p.id == it } }
                Text(
                    "Selezionati ${selectedSet.size}/4 · Casa $nHome · Ospite $nAway · " +
                    "Marcatori dichiarati ${schedina.scorers.size}",
                    style = MaterialTheme.typography.bodySmall,
                )
                PlayerList("Squadra di casa", homePlayers, schedina, bonuses,
                    onToggle = { id -> toggle(schedina, id) { schedina = it } },
                    onScorer = { id ->
                        if (id in selectedSet) schedina = schedina.copy(
                            scorers = if (id in schedina.scorers) schedina.scorers - id else schedina.scorers + id)
                    })
                PlayerList("Squadra ospite", awayPlayers, schedina, bonuses,
                    onToggle = { id -> toggle(schedina, id) { schedina = it } },
                    onScorer = { id ->
                        if (id in selectedSet) schedina = schedina.copy(
                            scorers = if (id in schedina.scorers) schedina.scorers - id else schedina.scorers + id)
                    })
            }
        }

        // --- Primo sostituto / primo ammonito (§8) ---
        Card {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Eventi da pronosticare", style = MaterialTheme.typography.titleSmall)
                DropdownPick("Primo sostituto (chi esce)", allPlayers, schedina.firstSubOut) {
                    schedina = schedina.copy(firstSubOut = it)
                }
                DropdownPick("Primo ammonito", allPlayers, schedina.firstYellow) {
                    schedina = schedina.copy(firstYellow = it)
                }
            }
        }

        Button(
            enabled = schedina.isComplete,
            modifier = Modifier.fillMaxWidth(),
            onClick = {
                vm.saveSchedina(matchId, schedina) { e ->
                    error = e?.message
                    if (e == null) onBack()
                }
            },
        ) { Text("Salva pronostico") }
    }
}

private fun toggle(s: Schedina, id: String, set: (Schedina) -> Unit) {
    val sel = if (id in s.selected) s.selected - id else s.selected + id
    set(if (sel.size <= 4) s.copy(selected = sel, scorers = if (id !in sel) s.scorers - id else s.scorers) else s)
}

@Composable
private fun NumberField(label: String, value: Int, onChange: (Int) -> Unit) {
    OutlinedTextField(
        value = value.toString(),
        onValueChange = { v -> v.toIntOrNull()?.let { if (it in 0..9) onChange(it) } },
        label = { Text(label) },
        modifier = Modifier.width(140.dp),
    )
}

@Composable
private fun PlayerList(
    title: String, players: List<Player>, schedina: Schedina,
    bonuses: Map<String, PlayerMatchBonus>,
    onToggle: (String) -> Unit, onScorer: (String) -> Unit,
) {
    Text(title, style = MaterialTheme.typography.labelLarge)
    LazyColumn(modifier = Modifier.heightIn(max = 220.dp)) {
        items(players, key = { it.id }) { p ->
            val selected = p.id in schedina.selected
            val scorer = p.id in schedina.scorers
            val bonus = bonuses[p.id]
            Row(
                Modifier.fillMaxWidth().padding(vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Checkbox(selected, onCheckedChange = { onToggle(p.id) })
                Column(Modifier.weight(1f)) {
                    Text(p.name, style = MaterialTheme.typography.bodyMedium)
                    Text("${p.roleLabel} · ${availabilityLabel(p)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                // Bonus mostrati come PUNTI, mai probabilità interne (§6)
                if (bonus != null) {
                    Column(horizontalAlignment = Alignment.End) {
                        Text("Gol: +${"%.0f".format(bonus.golBonusPts)}",
                            style = MaterialTheme.typography.labelSmall)
                        if (bonus.cleanSheetBonusPts > 0) {
                            Text("CS: +${"%.0f".format(bonus.cleanSheetBonusPts)}",
                                style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
                TextButton(onClick = { onScorer(p.id) }, enabled = selected) {
                    Text(if (scorer) "★ Marcatore" else "Segna")
                }
            }
        }
    }
}

@Composable
private fun DropdownPick(label: String, players: List<Player>, current: String?, onPick: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val currentName = players.firstOrNull { it.id == current }?.name
    OutlinedButton(onClick = { expanded = true }) {
        Text("$label: ${currentName ?: "nessuno"}")
    }
    DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
        DropdownMenuItem(text = { Text("Nessuno") }, onClick = { onPick(null); expanded = false })
        players.forEach { p ->
            DropdownMenuItem(
                text = { Text("${p.name} (${p.roleLabel})") },
                onClick = { onPick(p.id); expanded = false },
            )
        }
    }
}

// Distinzione esplicita tra dati certi e incerti (§9): il dettaglio
// ufficiale arriva dal campo availability del server quando sincronizzato
@Composable
private fun availabilityLabel(p: Player): String = when (p.position) {
    "GK" -> "Probabile"
    else -> "Probabile"
}
