package it.fantacalcio365.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import it.fantacalcio365.data.Repository
import it.fantacalcio365.ui.AppViewModel
import kotlinx.coroutines.launch

// Schermata 10 — Profilo e autenticazione
@Composable
fun AuthScreen(onSuccess: () -> Unit, vm: AppViewModel = viewModel()) {
    var isRegister by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    val repo = Repository()

    Column(
        modifier = Modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("FantaCalcio365", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Pronostici Serie A — gratuiti, senza vincite in denaro",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        Spacer(Modifier.height(32.dp))

        if (isRegister) {
            OutlinedTextField(
                username, { username },
                label = { Text("Nome utente") },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(8.dp))
        }
        OutlinedTextField(
            email, { email },
            label = { Text("Email") },
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(8.dp))
        OutlinedTextField(
            password, { password },
            label = { Text("Password") },
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth(),
        )

        error?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }

        Spacer(Modifier.height(16.dp))
        Button(
            enabled = !busy && email.isNotBlank() && password.length >= 6 &&
                    (!isRegister || username.isNotBlank()),
            onClick = {
                busy = true
                scope.launch {
                    runCatching {
                        if (isRegister) repo.signUp(email, password, username)
                        else repo.signIn(email, password)
                    }.onSuccess { onDone -> busy = false; onSuccess() }
                        .onFailure { busy = false; error = it.message ?: "Errore di rete" }
                }
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            else Text(if (isRegister) "Registrati" else "Accedi")
        }

        TextButton(onClick = { isRegister = !isRegister; error = null }) {
            Text(if (isRegister) "Hai già un account? Accedi" else "Nuovo utente? Registrati")
        }
    }
}
