package it.fantacalcio365.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Palette "Serie A": azzurro notte + verde campo + accento caldo
val BluNotte = Color(0xFF0B1F3A)
val AzzurroCampo = Color(0xFF1E88E5)
val VerdeCampo = Color(0xFF2E7D32)
val Accento = Color(0xFFF9A825)
val RossoVivo = Color(0xFFD32F2F)
val SuperficieChiara = Color(0xFFF7F9FC)

private val LightScheme = lightColorScheme(
    primary = AzzurroCampo,
    onPrimary = Color.White,
    secondary = VerdeCampo,
    tertiary = Accento,
    background = SuperficieChiara,
    error = RossoVivo,
)

private val DarkScheme = darkColorScheme(
    primary = AzzurroCampo,
    secondary = VerdeCampo,
    tertiary = Accento,
    background = BluNotte,
)

@Composable
fun FantaCalcio365Theme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkScheme else LightScheme,
        content = content
    )
}
