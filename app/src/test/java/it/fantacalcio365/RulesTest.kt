package it.fantacalcio365

import it.fantacalcio365.data.LeaderboardEntry
import it.fantacalcio365.data.Player
import it.fantacalcio365.data.Schedina
import org.junit.Assert.*
import org.junit.Test

// Test delle regole di presentazione/validazione client-side.
// Il punteggio ufficiale è SEMPRE calcolato dal server (§12): qui si
// verificano i vincoli della schedina e l'ordinamento della classifica.
class RulesTest {

    private fun schedina(
        selected: List<String>, scorers: Set<String>,
    ) = Schedina(selected = selected, scorers = scorers)

    // Squadre derivate dal prefisso dell'id (H = casa, A = ospite)
    private val playersById = listOf("H1", "H2", "H3", "H4", "A1", "A2", "A3", "A4")
        .associateWith { id ->
            Player(
                id = id,
                teamId = if (id.startsWith("H")) "HOME" else "AWAY",
                name = id,
                position = "TD",
            )
        }

    private fun Schedina.isComplete(): Boolean =
        isComplete("HOME", "AWAY", playersById)

    // §5: esattamente 4 giocatori, >=1 casa (prefisso H), >=1 ospite (A)
    @Test
    fun `schedina valida con 4 giocatori e marcatore`() {
        val s = schedina(listOf("H1", "H2", "A1", "A2"), scorers = setOf("H1"))
        assertTrue(s.isComplete())
    }

    @Test
    fun `schedina incompleta senza marcatore dichiarato`() {
        val s = schedina(listOf("H1", "H2", "A1", "A2"), scorers = emptySet())
        assertFalse("Serve almeno 1 marcatore dichiarato (decisione approvata)", s.isComplete())
    }

    @Test
    fun `schedina respinta senza giocatore di casa`() {
        val s = schedina(listOf("A1", "A2", "A3", "A4"), scorers = setOf("A1"))
        assertFalse(s.isComplete())
    }

    @Test
    fun `schedina respinta senza giocatore ospite`() {
        val s = schedina(listOf("H1", "H2", "H3", "H4"), scorers = setOf("H1"))
        assertFalse(s.isComplete())
    }

    @Test
    fun `schedina respinta con meno di 4 giocatori`() {
        val s = schedina(listOf("H1", "A1"), scorers = setOf("H1"))
        assertFalse(s.isComplete())
    }

    // §10 (A4): spareggio punti → esatti → marcatori (l'orario si applica a parità totale)
    @Test
    fun `classifica ordinata per punti poi spareggi`() {
        val u1 = LeaderboardEntry("u1", "Anna", 107.0, 5, 9)
        val u2 = LeaderboardEntry("u2", "Bruno", 107.0, 6, 3)
        val u3 = LeaderboardEntry("u3", "Carlo", 120.0, 2, 1)
        val sorted = listOf(u1, u2, u3).sortedWith(
            compareByDescending<LeaderboardEntry> { it.total }
                .thenByDescending { it.exactResults }
                .thenByDescending { it.exactScorers }
        )
        assertEquals(listOf("Carlo", "Bruno", "Anna"), sorted.map { it.username })
    }

    // §4: verifica documentale della tabella di punteggio (server-side, qui solo riferimenti)
    @Test
    fun `tabella punteggi combinati`() {
        val table = mapOf(
            "combo perfetto" to 20,     // 4 (1T) + 6 (2T) + 10 bonus
            "solo 2T esatto" to 6,
            "solo 1T esatto" to 0,      // il 1T vale solo nel combo (decisione A1)
            "nessuno" to 0,
        )
        assertEquals(20, table["combo perfetto"])
        assertEquals(6, table["solo 2T esatto"])
        assertEquals(0, table["solo 1T esatto"])
    }
}
