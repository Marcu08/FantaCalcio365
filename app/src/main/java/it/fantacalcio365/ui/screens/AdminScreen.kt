package it.fantacalcio365.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.github.jan.supabase.gotrue.auth
import it.fantacalcio365.data.SupabaseProvider
import it.fantacalcio365.ui.AppViewModel
import it.fantacalcio365.ui.components.*
import kotlinx.coroutines.launch

// Schermata 11 — Strumenti amministrativi (solo is_admin, §12).
// Le operazioni passano dalle Edge Functions protette (admin-override /
// admin-release-override): il client manda il proprio JWT, il server
// riverifica is_admin. Nessun privilegio sul client.
@Composable
fun AdminScreen(vm: AppViewModel, onBack: () -> Unit = {}) {
    val profile by vm.profile.collectAsState()
    val scope = rememberCoroutineScope()
    val matches by vm.matches.collectAsState()

    if (profile?.isAdmin != true) {
        Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            TextButton(onClick = onBack) { Text("< Indietro") }
            EmptyState("Accesso riservato agli amministratori")
        }
        return
    }

    var providerId by remember { mutableStateOf("") }
    var reason by remember { mutableStateOf("") }
    var resultJson by remember { mutableStateOf("") }
    var eventsJson by remember { mutableStateOf("[]") }
    var message by remember { mutableStateOf<String?>(null) }
    var isError by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var matchdayText by remember { mutableStateOf("") }

    // Prefill con la giornata corrente della stagione
    LaunchedEffect(Unit) {
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            runCatching { vm.repo_.seasons().firstOrNull()?.currentMatchday }.getOrNull()
        }?.let { matchdayText = it.toString() }
    }

    val live = matches.filter { it.status == "LIVE" }
    val finished = matches.filter { it.status in listOf("FINISHED") }
    val confirmed = matches.filter { it.status == "CONFIRMED" }
    val pending = matches.filter { it.status == "SCHEDULED" }

    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        TextButton(onClick = onBack) { Text("< Indietro") }
        Text("Strumenti amministrativi", style = MaterialTheme.typography.titleLarge)

        // Stato del sistema (da dati pubblici, nessun segreto)
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("Stato sincronizzazione", style = MaterialTheme.typography.titleSmall)
                Text("In programma: ${pending.size} · LIVE: ${live.size} · " +
                        "provvisorie: ${finished.size} · ufficiali: ${confirmed.size}",
                    style = MaterialTheme.typography.bodySmall)
                if (finished.isNotEmpty()) {
                    Text("Partite provvisorie (da confermare dal cron o via override):",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.tertiary)
                    LazyColumn(modifier = Modifier.heightIn(max = 110.dp)) {
                        items(finished, key = { it.id }) { m ->
                            Text("· ${m.providerId} (giornata ${m.matchday})",
                                style = MaterialTheme.typography.labelSmall)
                        }
                    }
                }
            }
        }

        // Blocco manuale giornata via RPC admin_lock_matchday
        // (guard is_admin server-side; è il fallback del cron automatico)
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Blocco manuale giornata", style = MaterialTheme.typography.titleSmall)
                Text(
                    "Blocca le schedine della giornata prima del kickoff. " +
                            "Operazione riservata agli admin: la guard is_admin è sul server.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        matchdayText, { matchdayText = it.filter(Char::isDigit) },
                        label = { Text("Giornata") },
                        singleLine = true,
                        modifier = Modifier.width(120.dp),
                    )
                    Spacer(Modifier.width(12.dp))
                    Button(
                        enabled = !busy && matchdayText.toIntOrNull() != null,
                        onClick = {
                            val md = matchdayText.toInt()
                            busy = true
                            vm.lockMatchday(md) { e ->
                                busy = false
                                isError = e != null
                                message = if (e == null) "Giornata $md bloccata"
                                          else (e.message ?: "Errore blocco")
                                if (e == null) vm.refresh()
                            }
                        },
                    ) { Text("Blocca") }
                }
            }
        }

        // Correzione manuale via Edge Function (richiede JWT admin)
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Correzione manuale partita", style = MaterialTheme.typography.titleSmall)
                OutlinedTextField(
                    providerId, { providerId = it },
                    label = { Text("Provider ID della partita") },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    reason, { reason = it },
                    label = { Text("Motivo (min 5 caratteri)") },
                    singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    resultJson, { resultJson = it },
                    label = { Text("""Risultato: {"status":"CONFIRMED","ht_home":1,...} — ft = ht + ht2""" ) },
                    minLines = 2, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(
                    eventsJson, { eventsJson = it },
                    label = { Text("""Eventi JSON: [{"event_order":1,...}]""" ) },
                    minLines = 2, modifier = Modifier.fillMaxWidth())

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        enabled = !busy && providerId.isNotBlank() && reason.length >= 5 &&
                                resultJson.isNotBlank(),
                        onClick = {
                            busy = true
                            scope.launch {
                                runCatching { adminAction("admin-override", providerId, reason, resultJson, eventsJson) }
                                    .onSuccess { msg ->
                                        message = msg; isError = false; busy = false; vm.refresh()
                                    }
                                    .onFailure {
                                        message = it.message; isError = true; busy = false
                                    }
                            }
                        },
                    ) { Text("Applica override") }

                    OutlinedButton(
                        enabled = !busy && providerId.isNotBlank() && reason.length >= 5,
                        onClick = {
                            busy = true
                            scope.launch {
                                runCatching { adminAction("admin-release-override", providerId, reason) }
                                    .onSuccess { msg -> message = msg; isError = false; busy = false; vm.refresh() }
                                    .onFailure { message = it.message; isError = true; busy = false }
                            }
                        },
                    ) { Text("Rilascia override") }
                }

                message?.let {
                    Text(it, style = MaterialTheme.typography.bodySmall,
                        color = if (isError) MaterialTheme.colorScheme.error
                        else MaterialTheme.colorScheme.secondary)
                }
            }
        }
    }
}

// Chiamata alle Edge Functions con il JWT dell'utente corrente:
// il server riverifica is_admin; qui nessun segreto.
// L'I/O di rete è spostato su Dispatchers.IO (mai sul main thread).
private suspend fun adminAction(
    function: String, providerId: String, reason: String,
    resultJson: String? = null, eventsJson: String? = null,
): String = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
    val token = SupabaseProvider.client.auth.currentUserOrNull()?.let {
        SupabaseProvider.client.auth.currentAccessTokenOrNull()
    } ?: error("Sessione scaduta: effettua di nuovo l'accesso")

    val endpoint = BuildConfigProxy.SUPABASE_URL.removeSuffix("/") +
            "/functions/v1/$function"
    val body = buildString {
        append("""{"provider_id": "$providerId", "reason": ${jsonEscape(reason)}""")
        if (resultJson != null) {
            append(""", "result": $resultJson""")
            append(""", "events": $eventsJson""")
        }
        append("}")
    }
    val resp = java.net.URL(endpoint).openConnection() as java.net.HttpURLConnection
    resp.requestMethod = "POST"
    resp.setRequestProperty("Authorization", "Bearer $token")
    resp.setRequestProperty("Content-Type", "application/json")
    resp.doOutput = true
    resp.outputStream.write(body.toByteArray())
    val code = resp.responseCode
    val text = resp.inputStream?.bufferedReader()?.readText() ?: ""
    resp.disconnect()
    if (code !in 200..299) error("Errore $code: ${text.take(200)}")
    text.take(200)
}

// Accesso BuildConfig senza import esplicito nel corpo
private object BuildConfigProxy {
    val SUPABASE_URL: String get() = it.fantacalcio365.BuildConfig.SUPABASE_URL
}

private fun jsonEscape(s: String): String =
    "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
