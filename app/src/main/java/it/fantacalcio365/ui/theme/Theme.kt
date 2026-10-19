package it.fantacalcio365.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Palette "Serie A": azzurro notte + verde campo + accento caldo
val BluNotte = Color(0xFF0B1F3A)
val AzzurroCampo = Color(0xFF1E88E5)
val VerdeCampo = Color(0xFF2E7D32)
val Accento = Color(0xFFF9A825)
val RossoVivo = Color(0xFFD32F2F)
val SuperficieChiara = Color(0xFFF5F7FA)
val CardChiara = Color.White
val GrigioTesto = Color(0xFF5A6472)
val Oro = Color(0xFFFFB300)
val Argento = Color(0xFF9E9E9E)
val Bronzo = Color(0xFFBF7B3F)

private val LightScheme = lightColorScheme(
    primary = AzzurroCampo,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD6E9FF),
    onPrimaryContainer = Color(0xFF0B3A66),
    secondary = VerdeCampo,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFD9F0DB),
    tertiary = Accento,
    background = SuperficieChiara,
    onBackground = Color(0xFF16202C),
    surface = CardChiara,
    onSurface = Color(0xFF16202C),
    surfaceVariant = Color(0xFFEDF1F6),
    onSurfaceVariant = GrigioTesto,
    error = RossoVivo,
    outline = Color(0xFFD8DEE6),
)

private val DarkScheme = darkColorScheme(
    primary = Color(0xFF64B5F6),
    secondary = Color(0xFF81C784),
    tertiary = Accento,
    background = Color(0xFF0A1626),
    surface = Color(0xFF11223A),
    error = Color(0xFFEF5350),
)

private val AppTypography = Typography(
    headlineMedium = androidx.compose.ui.text.TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    titleLarge = androidx.compose.ui.text.TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold),
    titleMedium = androidx.compose.ui.text.TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    titleSmall = androidx.compose.ui.text.TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = androidx.compose.ui.text.TextStyle(fontSize = 16.sp),
    bodyMedium = androidx.compose.ui.text.TextStyle(fontSize = 14.sp),
    bodySmall = androidx.compose.ui.text.TextStyle(fontSize = 12.sp, lineHeight = 16.sp),
    labelLarge = androidx.compose.ui.text.TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium),
    labelSmall = androidx.compose.ui.text.TextStyle(fontSize = 11.sp, letterSpacing = 0.3.sp),
)

private val AppShapes = Shapes(
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(24.dp),
)

@Composable
fun FantaCalcio365Theme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkScheme else LightScheme,
        typography = AppTypography,
        shapes = AppShapes,
        content = content,
    )
}
