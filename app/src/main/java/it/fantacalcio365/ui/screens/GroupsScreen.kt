package it.fantacalcio365.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.Key
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import it.fantacalcio365.ui.AppViewModel

// Schermata 9 — Gruppi privati e inviti tramite codice
@Composable
fun GroupsScreen(vm: AppViewModel) {
    LaunchedEffect(Unit) { vm.refresh() }
    val groups by vm.groups.collectAsState()
    var newGroupName by remember { mutableStateOf("") }
    var joinCode by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current

    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Gruppi privati", style = MaterialTheme.typography.titleLarge)

        error?.let {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                Text(it, Modifier.padding(12.dp), color = MaterialTheme.colorScheme.error)
            }
        }

        // Unisciti con codice
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Key, null, tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(8.dp))
                    Text("Hai un codice invito?", style = MaterialTheme.typography.titleSmall)
                }
                OutlinedTextField(
                    joinCode, { joinCode = it },
                    label = { Text("Codice invito") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    enabled = joinCode.isNotBlank(),
                    onClick = { vm.joinGroup(joinCode) { e -> error = e?.message; if (e == null) joinCode = "" } },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Unisciti al gruppo") }
            }
        }

        // Crea gruppo
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.GroupAdd, null, tint = MaterialTheme.colorScheme.secondary)
                    Spacer(Modifier.width(8.dp))
                    Text("Crea un nuovo gruppo", style = MaterialTheme.typography.titleSmall)
                }
                OutlinedTextField(
                    newGroupName, { newGroupName = it },
                    label = { Text("Nome del gruppo") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Button(
                    enabled = newGroupName.isNotBlank(),
                    onClick = { vm.createGroup(newGroupName) { e -> error = e?.message; if (e == null) newGroupName = "" } },
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Crea") }
            }
        }

        Text("I tuoi gruppi", style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 4.dp))

        if (groups.isEmpty()) {
            Card(Modifier.fillMaxWidth()) {
                Text(
                    "Nessun gruppo ancora. Creane uno o unisciti con un codice!",
                    Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(groups, key = { it.id }) { g ->
                Card(Modifier.fillMaxWidth(), elevation = CardDefaults.cardElevation(1.dp)) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(g.name, style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Codice: ${g.inviteCode}",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        IconButton(onClick = {
                            val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            cm.setPrimaryClip(ClipData("invite", null, ClipData.Item(g.inviteCode)))
                            Toast.makeText(context, "Codice copiato!", Toast.LENGTH_SHORT).show()
                        }) {
                            Icon(Icons.Default.ContentCopy, "Copia codice",
                                tint = MaterialTheme.colorScheme.primary)
                        }
                    }
                }
            }
        }
    }
}
