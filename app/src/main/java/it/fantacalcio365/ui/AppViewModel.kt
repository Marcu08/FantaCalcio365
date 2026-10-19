package it.fantacalcio365.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import it.fantacalcio365.data.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.format.DateTimeFormatter

// ViewModel condiviso: espone stato, mai logica di punteggio (quella è del server)
class AppViewModel : ViewModel() {
    private val repo = Repository()

    val seasons = listOf("2026/27") // placeholder: verrà da tabella seasons
    private val currentSeason = "11111111-1111-1111-1111-111111111111"

    private val _profile = MutableStateFlow<Profile?>(null)
    val profile: StateFlow<Profile?> = _profile

    private val _matches = MutableStateFlow<List<Match>>(emptyList())
    val matches: StateFlow<List<Match>> = _matches

    private val _teams = MutableStateFlow<Map<String, Team>>(emptyMap())
    val teams: StateFlow<Map<String, Team>> = _teams

    private val _leaderboard = MutableStateFlow<List<LeaderboardEntry>>(emptyList())
    val leaderboard: StateFlow<List<LeaderboardEntry>> = _leaderboard

    private val _scores = MutableStateFlow<List<Score>>(emptyList())
    val scores: StateFlow<List<Score>> = _scores

    private val _groups = MutableStateFlow<List<Group>>(emptyList())
    val groups: StateFlow<List<Group>> = _groups

    val repo_ = repo

    fun refresh() {
        viewModelScope.launch {
            runCatching {
                _profile.value = repo.myProfile()
                _teams.value = repo.teams().associateBy { it.id }
                _matches.value = repo.matches(currentSeason)
                _leaderboard.value = repo.leaderboard(currentSeason)
                    .sortedWith(compareByDescending<LeaderboardEntry> { it.total }
                        .thenByDescending { it.exactResults }
                        .thenByDescending { it.exactScorers })
                _scores.value = repo.myScores()
                _groups.value = repo.myGroups()
            }
        }
    }

    fun saveSchedina(matchId: String, s: Schedina, onDone: (Throwable?) -> Unit) {
        viewModelScope.launch {
            runCatching {
                val uid = repo.currentUserId() ?: error("Non autenticato")
                val existing = repo.myPrediction(matchId)
                val pred = (existing?.first ?: Prediction(matchId = matchId)).copy(
                    htHome = s.htHome, htAway = s.htAway,
                    ht2Home = s.ht2Home, ht2Away = s.ht2Away,
                    firstSubOutPlayerId = s.firstSubOut,
                    firstYellowPlayerId = s.firstYellow,
                )
                repo.savePrediction(
                    pred.copy(id = existing?.first?.id),
                    s.selected.map { PredictionPlayer(playerId = it, isMarkedScorer = it in s.scorers) }
                )
            }.onSuccess { refresh(); onDone(null) }
                .onFailure { onDone(it) }
        }
    }

    fun createGroup(name: String, onDone: (Throwable?) -> Unit) {
        viewModelScope.launch {
            runCatching { repo.createGroup(name) }
                .onSuccess { refresh(); onDone(null) }
                .onFailure { onDone(it) }
        }
    }

    fun joinGroup(code: String, onDone: (Throwable?) -> Unit) {
        viewModelScope.launch {
            runCatching {
                val uid = repo.currentUserId() ?: error("Non autenticato")
                repo.joinByCode(code, uid)
            }.onSuccess { refresh(); onDone(null) }
                .onFailure { onDone(it) }
        }
    }

    fun logout(onDone: () -> Unit) {
        viewModelScope.launch { runCatching { repo.signOut() }; onDone() }
    }
}

// utility di formattazione per scadenze (solo visualizzazione, la verifica
// del blocco è sempre server-side §9)
fun formatKickoff(iso: String?): String = runCatching {
    DateTimeFormatter.ofPattern("dd/MM HH:mm")
        .withLocale(java.util.Locale.ITALY)
        .format(Instant.parse(iso).atZone(java.time.ZoneId.systemDefault()))
}.getOrDefault("—")
