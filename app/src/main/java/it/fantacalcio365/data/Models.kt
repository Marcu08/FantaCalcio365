package it.fantacalcio365.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Modelli di dominio. I punteggi e le scadenze NON vengono mai calcolati
// o validati qui: arrivano già pronti dal server (§12).

@Serializable
data class Match(
    val id: String,
    val matchday: Int,
    @SerialName("provider_id") val providerId: String? = null,
    @SerialName("kickoff_at") val kickoffAt: String,
    val status: String, // SCHEDULED | LIVE | FINISHED | CONFIRMED | POSTPONED | CANCELLED
    @SerialName("locked_at") val lockedAt: String? = null,
    @SerialName("ht_home_goals") val htHome: Int? = null,
    @SerialName("ht_away_goals") val htAway: Int? = null,
    @SerialName("ft_home_goals") val ftHome: Int? = null,
    @SerialName("ft_away_goals") val ftAway: Int? = null,
    @SerialName("home_team_id") val homeTeamId: String? = null,
    @SerialName("away_team_id") val awayTeamId: String? = null,
) {
    val isLocked: Boolean get() = lockedAt != null
}

@Serializable
data class Team(
    val id: String,
    val name: String,
    @SerialName("short_name") val shortName: String,
    @SerialName("logo_url") val logoUrl: String? = null,
)

enum class Availability { PROBABLE, CONFIRMED, RESERVE, UNAVAILABLE }

@Serializable
data class Player(
    val id: String,
    @SerialName("team_id") val teamId: String,
    val name: String,
    val position: String, // GK | DF | MF | FW
) {
    val roleLabel: String get() = when (position) {
        "GK" -> "Portiere"; "DF" -> "Difensore"; "MF" -> "Centrocampista"; else -> "Attaccante"
    }
}

// Bonus congelato mostrato all'utente: SOLO punti, mai probabilità interne (§6)
@Serializable
data class PlayerMatchBonus(
    @SerialName("player_id") val playerId: String,
    @SerialName("gol_bonus_pts") val golBonusPts: Double,
    @SerialName("clean_sheet_bonus_pts") val cleanSheetBonusPts: Double,
    @SerialName("frozen_at") val frozenAt: String? = null,
)

@Serializable
data class Prediction(
    val id: String? = null,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("ht_home") val htHome: Int = 0,
    @SerialName("ht_away") val htAway: Int = 0,
    @SerialName("ht2_home") val ht2Home: Int = 0,
    @SerialName("ht2_away") val ht2Away: Int = 0,
    @SerialName("first_sub_out_player_id") val firstSubOutPlayerId: String? = null,
    @SerialName("first_yellow_player_id") val firstYellowPlayerId: String? = null,
)

@Serializable
data class PredictionPlayer(
    @SerialName("prediction_id") val predictionId: String? = null,
    @SerialName("player_id") val playerId: String,
    @SerialName("is_marked_scorer") val isMarkedScorer: Boolean = false,
)

// Schedina in compilazione (stato locale, validata dal server al salvataggio)
data class Schedina(
    val htHome: Int = 0, val htAway: Int = 0,
    val ht2Home: Int = 0, val ht2Away: Int = 0,
    val selected: List<String> = emptyList(),
    val scorers: Set<String> = emptySet(),
    val firstSubOut: String? = null,
    val firstYellow: String? = null,
) {
    val isComplete: Boolean
        get() = selected.size == 4 &&
                selected.count { it.startsWith("H") } >= 1 &&
                selected.count { it.startsWith("A") } >= 1 &&
                scorers.isNotEmpty()
}

@Serializable
data class Score(
    val total: Double,
    @SerialName("pts_ht") val ptsHt: Int,
    @SerialName("pts_ht2") val ptsHt2: Int,
    @SerialName("pts_scorers") val ptsScorers: Double,
    @SerialName("pts_clean_sheet") val ptsCleanSheet: Double,
    @SerialName("pts_sub") val ptsSub: Int,
    @SerialName("pts_yellow") val ptsYellow: Int,
    @SerialName("is_official") val isOfficial: Boolean,
)

@Serializable
data class LeaderboardEntry(
    @SerialName("user_id") val userId: String,
    val username: String,
    val total: Double,
    @SerialName("exact_results") val exactResults: Long,
    @SerialName("exact_scorers") val exactScorers: Long,
)

@Serializable
data class Group(
    val id: String,
    val name: String,
    @SerialName("invite_code") val inviteCode: String,
    @SerialName("owner_id") val ownerId: String,
)

@Serializable
data class Profile(
    val id: String,
    val username: String,
    @SerialName("is_admin") val isAdmin: Boolean = false,
)
