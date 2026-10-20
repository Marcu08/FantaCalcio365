package it.fantacalcio365

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.EventNote
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.*
import it.fantacalcio365.ui.*
import it.fantacalcio365.ui.components.LoadingBox
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
    data object Home : Dest("home", "Home", Icons.Default.Home)
    data object Calendar : Dest("calendar", "Calendario", Icons.Default.EventNote)
    data object Leaderboard : Dest("leaderboard", "Classifica", Icons.Default.EmojiEvents)
    data object Groups : Dest("groups", "Gruppi", Icons.Default.Groups)
    data object Profile : Dest("profile", "Profilo", Icons.Default.Person)
}

@Composable
fun AppRoot(vm: AppViewModel = viewModel()) {
    val navController = rememberNavController()
    val profile by vm.profile.collectAsState()
    val bootstrapped by vm.bootstrapped.collectAsState()
    val backStack by navController.currentBackStackEntryAsState()
    val current = backStack?.destination?.route

    if (!bootstrapped) {
        LoadingBox("Sessione…")
        return
    }

    LaunchedEffect(profile) {
        if (profile == null && current != null && current != "auth") {
            navController.navigate("auth") { popUpTo(0) { inclusive = true } }
        }
    }

    Scaffold(
        bottomBar = {
            if (profile != null) {
                NavigationBar {
                    listOf(Dest.Home, Dest.Calendar, Dest.Leaderboard, Dest.Groups, Dest.Profile).forEach { d ->
                        NavigationBarItem(
                            selected = current == d.route,
                            onClick = {
                                navController.navigate(d.route) {
                                    popUpTo(Dest.Home.route) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(d.icon, contentDescription = d.label) },
                            label = { Text(d.label) },
                        )
                    }
                }
            }
        }
    ) { pad ->
        NavHost(
            navController = navController,
            startDestination = if (profile == null) "auth" else Dest.Home.route,
            modifier = Modifier.padding(pad),
        ) {
            composable("auth") {
                AuthScreen(
                    vm = vm,
                    onSuccess = { navController.navigate(Dest.Home.route) { popUpTo(0) { inclusive = true } } },
                )
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
            composable(Dest.Profile.route) {
                ProfileScreen(
                    vm = vm,
                    onLogout = { navController.navigate("auth") { popUpTo(0) } },
                    onOpenAdmin = { navController.navigate("admin") },
                )
            }
            composable("admin") { AdminScreen(vm = vm, onBack = { navController.popBackStack() }) }
        }
    }
}
