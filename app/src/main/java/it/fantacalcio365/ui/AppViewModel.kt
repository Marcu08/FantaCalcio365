package it.fantacalcio365.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import it.fantacalcio365.data.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.format.DateTimeFormatter

class AppViewModel : ViewModel() {
    private val repo = Repository()

    private val _seasonId = MutableStateFlow<String?>(null)
    val seasonIdFlow: StateFlow<String?> = _seasonId

    suspend fun seasonId(): String? {
        _seasonId.value?.let { return it }
        val s = repo.seasons().firstOrNull()
        _seasonId.value = s?.id
        return s?.id
    }

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

    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading

    private val _loadError = MutableStateFlow<String?>(null)
    val loadError: StateFlow<String?> = _loadError

    private val _bootstrapped = MutableStateFlow(false)
    val bootstrapped: StateFlow<Boolean> = _bootstrapped

    val repo_ = repo

    init {
        viewModelScope.launch {
            runCatching { repo.hasSession() }
            refresh()
            _bootstrapped.value = true
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _loading.value = true
            _loadError.value = null
            runCatching {
                _profile.value = repo.myProfile()
                if (_profile.value == null) {
                    clearData()
                    return@runCatching
                }
                val sid = seasonId() ?: return@runCatching
                _teams.value = repo.teams().associateBy { it.id }
                _matches.value = repo.matches(sid)
                _leaderboard.value = repo.leaderboard(sid)
                    .sortedWith(compareByDescending<LeaderboardEntry> { it.total }
                        .thenByDescending { it.exactResults }
                        .thenByDescending { it.exactScorers })
                _scores.value = repo.myScores()
                _groups.value = repo.myGroups()
            }.onFailure {
                _loadError.value = it.message ?: "Errore di rete"
            }
            _loading.value = false
        }
    }

    private fun clearData() {
        _matches.value = emptyList()
        _teams.value = emptyMap()
        _leaderboard.value = emptyList()
        _scores.value = emptyList()
        _groups.value = emptyList()
        _seasonId.value = null
    }

    fun signIn(email: String, password: String, onDone: (Throwable?) -> Unit) {
        viewModelScope.launch {
            runCatching { repo.signIn(email, password) }
                .onSuccess { refresh(); onDone(null) }
                .onFailure { onDone(it) }
        }
    }

    fun signUp(email: String, password: String, username: String, onDone: (Throwable?) -> Unit) {
        viewModelScope.launch {
            runCatching { repo.signUp(email, password, username) }
                .onSuccess { refresh(); onDone(null) }
                .onFailure { onDone(it) }
        }
    }

    fun saveSchedina(matchId: String, s: Schedina, onDone: (Throwable?) -> Unit) {
        viewModelScope.launch {
            runCatching {
                repo.currentUserId() ?: error("Non autenticato")
                repo.savePrediction(
                    matchId,
                    s,
                    s.selected.map { PredictionPlayer(playerId = it, isMarkedScorer = it in s.scorers) },
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
            runCatching { repo.joinByCode(code) }
                .onSuccess { refresh(); onDone(null) }
                .onFailure { onDone(it) }
        }
    }

    fun lockMatchday(matchday: Int, onDone: (Throwable?) -> Unit) {
        viewModelScope.launch {
            runCatching {
                val sid = seasonId() ?: error("Stagione assente")
                repo.lockMatchday(sid, matchday)
            }.onSuccess { refresh(); onDone(null) }
                .onFailure { onDone(it) }
        }
    }

    fun logout(onDone: () -> Unit) {
        viewModelScope.launch {
            runCatching { repo.signOut() }
            _profile.value = null
            clearData()
            onDone()
        }
    }
}

fun formatKickoff(iso: String?): String = runCatching {
    DateTimeFormatter.ofPattern("dd/MM HH:mm")
        .withLocale(java.util.Locale.ITALY)
        .format(Instant.parse(iso).atZone(java.time.ZoneId.systemDefault()))
}.getOrDefault("—")
