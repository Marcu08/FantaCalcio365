package it.fantacalcio365.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant

@Serializable
data class Match(
    val id: String,
    val matchday: Int,
    @SerialName("provider_id") val providerId: String? = null,
    @SerialName("kickoff_at") val kickoffAt: String,
    val status: String,
    @SerialName("locked_at") val lockedAt: String? = null,
    @SerialName("ht_home_goals") val htHome: Int? = null,
    @SerialName("ht_away_goals") val htAway: Int? = null,
    @SerialName("ht2_home_goals") val ht2Home: Int? = null,
    @SerialName("ht2_away_goals") val ht2Away: Int? = null,
    @SerialName("ft_home_goals") val ftHome: Int? = null,
    @SerialName("ft_away_goals") val ftAway: Int? = null,
    @SerialName("home_team_id") val homeTeamId: String? = null,
    @SerialName("away_team_id") val awayTeamId: String? = null,
) {
    val isFinished: Boolean get() = status in listOf("LIVE", "FINISHED", "CONFIRMED")
    val isLocked: Boolean
        get() = lockedAt != null || isFinished || status == "CANCELLED"
}

fun List<Match>.isMatchdayLocked(matchday: Int): Boolean {
    val md = filter { it.matchday == matchday && it.status != "CANCELLED" }
    if (md.any { it.lockedAt != null || it.isFinished }) return true
    val first = md.minByOrNull { it.kickoffAt } ?: return false
    return runCatching { Instant.parse(first.kickoffAt).isBefore(Instant.now()) }.getOrDefault(false)
}

fun List<Match>.matchdayFirstKickoff(matchday: Int): String? =
    filter { it.matchday == matchday && it.status != "CANCELLED" }
        .minByOrNull { it.kickoffAt }?.kickoffAt

@Serializable
data class Season(
    val id: String,
    val name: String,
    @SerialName("current_matchday") val currentMatchday: Int = 1,
)

@Serializable
data class Team(
    val id: String,
    val name: String,
    @SerialName("short_name") val shortName: String,
    @SerialName("logo_url") val logoUrl: String? = null,
)

@Serializable
data class Player(
    val id: String,
    @SerialName("team_id") val teamId: String,
    val name: String,
    val position: String,
) {
    val roleLabel: String get() = when (position) {
        "GK" -> "Portiere"; "DF" -> "Difensore"; "MF" -> "Centrocampista"; else -> "Attaccante"
    }
}

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

@Serializable
data class MatchEvent(
    val id: String? = null,
    @SerialName("match_id") val matchId: String? = null,
    @SerialName("event_order") val eventOrder: Int = 0,
    val minute: Int? = null,
    val type: String,
    @SerialName("player_id") val playerId: String? = null,
)

data class Schedina(
    val htHome: Int = 0, val htAway: Int = 0,
    val ht2Home: Int = 0, val ht2Away: Int = 0,
    val selected: List<String> = emptyList(),
    val scorers: Set<String> = emptySet(),
    val firstSubOut: String? = null,
    val firstYellow: String? = null,
) {
    fun isComplete(
        homeTeamId: String?,
        awayTeamId: String?,
        playersById: Map<String, Player>,
    ): Boolean {
        if (selected.size != 4 || scorers.isEmpty()) return false
        if (scorers.any { it !in selected }) return false
        val teams = selected.mapNotNull { playersById[it]?.teamId }
        if (teams.size != 4) return false
        val homeOk = homeTeamId != null && teams.any { it == homeTeamId }
        val awayOk = awayTeamId != null && teams.any { it == awayTeamId }
        return homeOk && awayOk
    }
}

@Serializable
data class Score(
    val total: Double,
    @SerialName("match_id") val matchId: String? = null,
    val matchday: Int = 0,
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
