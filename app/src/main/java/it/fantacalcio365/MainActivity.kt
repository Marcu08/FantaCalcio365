package it.fantacalcio365

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.*
import it.fantacalcio365.ui.*
import it.fantacalcio365.ui.screens.*
import it.fantacalcio365.ui.theme.FantaCalcio365Theme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            FantaCalcio365Theme { AppRoot() }
        }
    }
}

sealed class Dest(val route: String, val label: String, val icon: androidx.compose.ui.graphics.vector.ImageVector) {
    object Home : Dest("home", "Home", Icons.Default.Schedule)
    object Calendar : Dest("calendar", "Calendario", Icons.Default.EmojiEvents)
    object Leaderboard : Dest("leaderboard", "Classifica", Icons.Default.EmojiEvents)
    object Groups : Dest("groups", "Gruppi", Icons.Default.Groups)
    object Profile : Dest("profile", "Profilo", Icons.Default.Person)
}

@Composable
fun AppRoot(vm: AppViewModel = viewModel()) {
    val navController = rememberNavController()
    val profile by vm.profile.collectAsState()
    val backStack by navController.currentBackStackEntryAsState()
    val current = backStack?.destination?.route

    Scaffold(
        bottomBar = {
            if (profile != null) {
                NavigationBar {
                    listOf(Dest.Home, Dest.Leaderboard, Dest.Groups, Dest.Profile).forEach { d ->
                        NavigationBarItem(
                            selected = current == d.route,
                            onClick = { navController.navigate(d.route) { popUpTo(Dest.Home.route); launchSingleTop = true } },
                            icon = { Icon(d.icon, null) },
                            label = { Text(d.label) },
                        )
                    }
                }
            }
        }
    ) { pad ->
        NavHost(
            navController = navController,
            startDestination = if (profile == null) "auth" else "home",
            modifier = Modifier.padding(pad),
        ) {
            composable("auth") {
                AuthScreen(onSuccess = { vm.refresh(); navController.navigate("home") { popUpTo(0) } })
            }
            composable(Dest.Home.route) {
                HomeScreen(
                    vm = vm,
                    onOpenMatch = { navController.navigate("match/$it") },
                    onOpenCalendar = { navController.navigate(Dest.Calendar.route) },
                )
            }
            composable("match/{matchId}") { entry ->
                MatchDetailScreen(
                    vm = vm,
                    matchId = entry.arguments?.getString("matchId") ?: "",
                    onBack = { navController.popBackStack() },
                    onOpenSchedina = { navController.navigate("schedina/$it") },
                )
            }
            composable("schedina/{matchId}") { entry ->
                SchedinaScreen(
                    vm = vm,
                    matchId = entry.arguments?.getString("matchId") ?: "",
                    onBack = { navController.popBackStack() },
                )
            }
            composable(Dest.Calendar.route) {
                CalendarScreen(vm = vm, onOpenMatch = { navController.navigate("match/$it") })
            }
            composable(Dest.Leaderboard.route) { LeaderboardScreen(vm = vm) }
            composable(Dest.Groups.route) { GroupsScreen(vm = vm) }
            composable(Dest.Profile.route) { ProfileScreen(vm = vm) }
            composable("admin") { AdminScreen(vm = vm) }
        }
    }
}
