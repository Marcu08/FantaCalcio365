package it.fantacalcio365.ui.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.background
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

// Componenti riusabili del design system FantaCalcio365

/** Stato di caricamento centrato con descrizione accessibile */
@Composable
fun LoadingBox(label: String = "Caricamento…") {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator()
            Spacer(Modifier.height(8.dp))
            Text(label, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** Stato vuoto con titolo e messaggio (nessun emoji, tipografia pulita) */
@Composable
fun EmptyState(title: String, subtitle: String? = null) {
    Card(Modifier.fillMaxWidth()) {
        Column(
            Modifier.padding(28.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium,
                textAlign = TextAlign.Center)
            if (subtitle != null) {
                Spacer(Modifier.height(6.dp))
                Text(subtitle, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center)
            }
        }
    }
}

/** Stato errore recuperabile con pulsante di retry */
@Composable
fun ErrorState(message: String, onRetry: (() -> Unit)? = null) {
    Card(colors = CardDefaults.cardColors(
        containerColor = MaterialTheme.colorScheme.errorContainer)) {
        Column(Modifier.padding(20.dp).fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Si è verificato un errore", style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(4.dp))
            Text(message, style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center)
            if (onRetry != null) {
                Spacer(Modifier.height(10.dp))
                OutlinedButton(onClick = onRetry) { Text("Riprova") }
            }
        }
    }
}

/** Chip di stato partita: aperta / bloccata / in corso / ufficiale */
@Composable
fun StatusChip(text: String, color: Color, outlined: Boolean = false) {
    Surface(
        shape = CircleShape,
        color = if (outlined) Color.Transparent else color.copy(alpha = 0.15f),
        border = if (outlined) {
            androidx.compose.foundation.BorderStroke(1.dp, color.copy(alpha = 0.5f))
        } else null,
    ) {
        Text(
            text,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelSmall,
            color = color,
        )
    }
}

/** Intestazione di sezione */
@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier) {
    Text(title, style = MaterialTheme.typography.titleLarge,
        modifier = modifier.padding(top = 8.dp, bottom = 2.dp))
}
