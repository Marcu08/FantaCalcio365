package it.fantacalcio365.data

import io.github.jan.supabase.gotrue.auth
import io.github.jan.supabase.gotrue.providers.builtin.Email
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

// Repository: tutte le chiamate al database. Le regole di gioco (scadenze,
// punteggi, validazioni) restano responsabilità del server (§12): qui
// si legge e si scrive soltanto.
class Repository {

    private val client get() = SupabaseProvider.client

    // ---- Autenticazione -------------------------------------------------
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

    suspend fun myProfile(): Profile? {
        val uid = currentUserId() ?: return null
        return client.postgrest.from("profiles").select()
            .decodeList<Profile>()
            .firstOrNull { it.id == uid }
    }

    suspend fun seasons(): List<Season> =
        client.postgrest.from("seasons").select().decodeList()

    // ---- Calendario e partite -------------------------------------------
    suspend fun matches(seasonId: String): List<Match> =
        client.postgrest.from("matches").select {
            filter { eq("season_id", seasonId) }
            order("kickoff_at", Order.ASCENDING)
        }.decodeList()

    suspend fun match(id: String): Match =
        client.postgrest.from("matches").select {
            filter { eq("id", id) }
        }.decodeSingle()

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

    // Bonus congelati per i giocatori di una partita (solo punti, §6)
    suspend fun bonuses(matchId: String): List<PlayerMatchBonus> =
        client.postgrest.from("player_match_stats").select {
            filter { eq("match_id", matchId) }
        }.decodeList<PlayerMatchBonus>().filter { it.frozenAt != null }

    // ---- Schedine --------------------------------------------------------
    suspend fun myPrediction(matchId: String): Pair<Prediction, List<PredictionPlayer>>? {
        val p = client.postgrest.from("predictions").select {
            filter { eq("match_id", matchId) }
        }.decodeList<Prediction>().firstOrNull() ?: return null
        val players = client.postgrest.from("prediction_players").select {
            filter { eq("prediction_id", p.id!!) }
        }.decodeList<PredictionPlayer>()
        return p to players
    }

    suspend fun savePrediction(p: Prediction, players: List<PredictionPlayer>) {
        val saved = if (p.id != null) {
            client.postgrest.from("predictions").update(p) {
                filter { eq("id", p.id) }
                select()
            }.decodeSingle<Prediction>()
        } else {
            client.postgrest.from("predictions").insert(p) {
                select()
            }.decodeSingle<Prediction>()
        }
        client.postgrest.from("prediction_players").delete {
            filter { eq("prediction_id", saved.id!!) }
        }
        client.postgrest.from("prediction_players").insert(
            players.map { it.copy(predictionId = saved.id) }
        )
    }

    // ---- Punteggi e classifica -------------------------------------------
    suspend fun myScores(): List<Score> =
        client.postgrest.from("scores").select {
            order("matchday", Order.ASCENDING)
        }.decodeList()

    suspend fun leaderboard(seasonId: String): List<LeaderboardEntry> =
        client.postgrest.from("leaderboard").select {
            filter { eq("season_id", seasonId) }
        }.decodeList()

    // ---- Gruppi ------------------------------------------------------------
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

    suspend fun joinByCode(code: String, userId: String) {
        val group = client.postgrest.from("groups").select {
            filter { eq("invite_code", code.trim()) }
        }.decodeSingle<Group>()
        client.postgrest.from("group_members").insert(
            mapOf("group_id" to group.id, "user_id" to userId)
        )
    }
}
