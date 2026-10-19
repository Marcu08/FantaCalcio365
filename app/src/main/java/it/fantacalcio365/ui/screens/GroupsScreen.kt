package it.fantacalcio365.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
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

    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Gruppi privati", style = MaterialTheme.typography.titleLarge)

        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }

        OutlinedTextField(
            joinCode, { joinCode = it },
            label = { Text("Codice invito") },
            modifier = Modifier.fillMaxWidth(),
        )
        Button(onClick = { vm.joinGroup(joinCode) { e -> error = e?.message; if (e == null) joinCode = "" } }) {
            Text("Unisciti con codice")
        }

        OutlinedTextField(
            newGroupName, { newGroupName = it },
            label = { Text("Nome nuovo gruppo") },
            modifier = Modifier.fillMaxWidth(),
        )
        Button(
            enabled = newGroupName.isNotBlank(),
            onClick = { vm.createGroup(newGroupName) { e -> error = e?.message; if (e == null) newGroupName = "" } },
        ) { Text("Crea gruppo") }

        Spacer(Modifier.height(8.dp))
        Text("I tuoi gruppi", style = MaterialTheme.typography.titleMedium)

        LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(groups, key = { it.id }) { g ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(12.dp)) {
                        Text(g.name, style = MaterialTheme.typography.titleSmall)
                        Text(
                            "Codice invito: ${g.inviteCode}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}
