package it.fantacalcio365.data

import io.github.jan.supabase.gotrue.auth
import io.github.jan.supabase.gotrue.providers.builtin.Email
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

class Repository {

    private val client get() = SupabaseProvider.client

    suspend fun signUp(email: String, password: String, username: String) {
        client.auth.signUpWith(Email) {
            this.email = email
            this.password = password
            data = buildJsonObject { put("username", username) }
        }
    }

    suspend fun signIn(email: String, password: String) {
        client.auth.signInWith(Email) {
            this.email = email
            this.password = password
        }
    }

    suspend fun signOut() = client.auth.signOut()

    suspend fun currentUserId(): String? = client.auth.currentUserOrNull()?.id

    suspend fun hasSession(): Boolean = client.auth.currentSessionOrNull() != null

    suspend fun myProfile(): Profile? {
        val uid = currentUserId() ?: return null
        return client.postgrest.from("profiles").select {
            filter { eq("id", uid) }
        }.decodeList<Profile>().firstOrNull()
    }

    suspend fun seasons(): List<Season> =
        client.postgrest.from("seasons").select {
            order("created_at", Order.DESCENDING)
        }.decodeList()

    suspend fun matches(seasonId: String): List<Match> =
        client.postgrest.from("matches").select {
            filter { eq("season_id", seasonId) }
            order("kickoff_at", Order.ASCENDING)
        }.decodeList()

    suspend fun match(id: String): Match =
        client.postgrest.from("matches").select {
            filter { eq("id", id) }
        }.decodeSingle()

    suspend fun matchEvents(matchId: String): List<MatchEvent> =
        client.postgrest.from("match_events").select {
            filter { eq("match_id", matchId) }
            order("event_order", Order.ASCENDING)
        }.decodeList()

    suspend fun teams(): List<Team> =
        client.postgrest.from("teams").select().decodeList()

    suspend fun players(teamId: String? = null): List<Player> =
        if (teamId != null) {
            client.postgrest.from("players").select {
                filter { eq("is_active", true) }
                filter { eq("team_id", teamId) }
            }.decodeList()
        } else {
            client.postgrest.from("players").select {
                filter { eq("is_active", true) }
            }.decodeList()
        }

    suspend fun bonuses(matchId: String): List<PlayerMatchBonus> =
        client.postgrest.from("player_match_stats").select {
            filter { eq("match_id", matchId) }
        }.decodeList<PlayerMatchBonus>().filter { it.frozenAt != null }

    suspend fun myPrediction(matchId: String): Pair<Prediction, List<PredictionPlayer>>? {
        val p = client.postgrest.from("predictions").select {
            filter { eq("match_id", matchId) }
        }.decodeList<Prediction>().firstOrNull() ?: return null
        val players = client.postgrest.from("prediction_players").select {
            filter { eq("prediction_id", p.id!!) }
        }.decodeList<PredictionPlayer>()
        return p to players
    }

    suspend fun savePrediction(matchId: String, s: Schedina, players: List<PredictionPlayer>) {
        val payload = buildJsonObject {
            put("p_match_id", matchId)
            put("p_ht_home", s.htHome)
            put("p_ht_away", s.htAway)
            put("p_ht2_home", s.ht2Home)
            put("p_ht2_away", s.ht2Away)
            if (s.firstSubOut != null) put("p_first_sub_out", s.firstSubOut) else put("p_first_sub_out", JsonNull)
            if (s.firstYellow != null) put("p_first_yellow", s.firstYellow) else put("p_first_yellow", JsonNull)
            put("p_players", buildJsonArray {
                players.forEach { pl ->
                    add(buildJsonObject {
                        put("player_id", pl.playerId)
                        put("is_marked_scorer", pl.isMarkedScorer)
                    })
                }
            })
        }
        client.postgrest.rpc("save_prediction", payload)
    }

    suspend fun myScores(): List<Score> =
        client.postgrest.from("scores").select {
            order("matchday", Order.ASCENDING)
        }.decodeList()

    suspend fun leaderboard(seasonId: String): List<LeaderboardEntry> =
        client.postgrest.from("leaderboard").select {
            filter { eq("season_id", seasonId) }
        }.decodeList()

    suspend fun myGroups(): List<Group> =
        client.postgrest.from("groups").select().decodeList()

    suspend fun createGroup(name: String): Group {
        val uid = currentUserId() ?: error("Non autenticato")
        return client.postgrest.from("groups").insert(
            mapOf("name" to name, "owner_id" to uid)
        ) {
            select()
        }.decodeSingle()
    }

    suspend fun joinByCode(code: String): Group =
        client.postgrest.rpc("join_group_by_code", buildJsonObject {
            put("p_code", code.trim())
        }).decodeSingle()

    suspend fun lockMatchday(seasonId: String, matchday: Int) {
        client.postgrest.rpc("admin_lock_matchday", buildJsonObject {
            put("p_season_id", seasonId)
            put("p_matchday", matchday)
        })
    }
}
