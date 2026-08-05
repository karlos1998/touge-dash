package it.letscode.tougedash.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import it.letscode.tougedash.BuildConfig
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougeMuted
import it.letscode.tougedash.ui.theme.TougePanel
import it.letscode.tougedash.ui.theme.TougeRed
import kotlinx.coroutines.launch

@Composable
fun CloudAccountCard(container: AppContainer) {
    val account by container.authRepository.session.collectAsState()
    val working by container.authRepository.working.collectAsState()
    val error by container.authRepository.error.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    Card(Modifier.fillMaxWidth().padding(top = 14.dp), colors = CardDefaults.cardColors(containerColor = TougePanel)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Text("TOUGE DASH CLOUD", color = TougeCyan, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            if (account != null) {
                Text(account!!.account.displayName, fontSize = 22.sp, fontWeight = FontWeight.Black)
                Text(account!!.account.email, color = TougeMuted)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { container.cloudSyncRepository.schedule() }) { Icon(Icons.Default.CloudSync, null); Text(appText(" Sync now", " Synchronizuj")) }
                    OutlinedButton(onClick = { scope.launch { container.authRepository.logout() } }) { Icon(Icons.Default.Logout, null); Text(appText(" Sign out", " Wyloguj")) }
                }
                OutlinedButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(BuildConfig.WEB_BASE_URL + "/profile"))) }, modifier = Modifier.fillMaxWidth()) { Icon(Icons.Default.Language, null); Text(appText(" Profile, vehicles and sharing", " Profil, auta i udostępnianie")) }
            } else {
                var register by remember { mutableStateOf(false) }
                var email by remember { mutableStateOf("") }
                var password by remember { mutableStateOf("") }
                var name by remember { mutableStateOf("") }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { FilterChip(selected = !register, onClick = { register = false }, label = { Text(appText("Sign in", "Logowanie")) }); FilterChip(selected = register, onClick = { register = true }, label = { Text(appText("Create account", "Nowe konto")) }) }
                if (register) OutlinedTextField(name, { name = it }, label = { Text(appText("Name", "Nazwa")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(email, { email = it }, label = { Text("Email") }, singleLine = true, modifier = Modifier.fillMaxWidth(), isError = email.isNotEmpty() && !email.contains('@'))
                OutlinedTextField(password, { password = it }, label = { Text(appText("Password", "Hasło")) }, singleLine = true, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth(), isError = password.isNotEmpty() && password.length < 10, supportingText = { if (password.isNotEmpty() && password.length < 10) Text(appText("Use at least 10 characters. Add a number or symbol for a stronger password.", "Użyj co najmniej 10 znaków. Cyfra lub symbol wzmocni hasło.")) })
                if (register) {
                    val strength = passwordStrength(password)
                    LinearProgressIndicator(progress = { strength }, modifier = Modifier.fillMaxWidth(), color = if (strength < .5f) TougeRed else TougeMint)
                    Text(if (strength < .35f) appText("Weak password", "Słabe hasło") else if (strength < .7f) appText("Good password", "Dobre hasło") else appText("Strong password", "Silne hasło"), color = TougeMuted, fontSize = 10.sp)
                }
                Button(
                    enabled = !working && email.contains('@') && password.length >= 10 && (!register || name.isNotBlank()),
                    onClick = { scope.launch { val success = if (register) container.authRepository.register(email, password, name) else container.authRepository.login(email, password); if (success) container.cloudSyncRepository.schedule() } },
                    modifier = Modifier.fillMaxWidth()
                ) { Text(if (working) appText("Please wait…", "Chwila…") else if (register) appText("Create account", "Utwórz konto") else appText("Sign in", "Zaloguj się")) }
                OutlinedButton(onClick = {
                    val auth = Uri.parse(BuildConfig.WEB_BASE_URL + "/auth").buildUpon().appendQueryParameter("mobileReturn", "tougedash://auth").build()
                    context.startActivity(Intent(Intent.ACTION_VIEW, auth))
                }, modifier = Modifier.fillMaxWidth()) { Text(appText("Continue with Apple, Google or Facebook", "Kontynuuj przez Apple, Google lub Facebook")) }
                Text(appText("When offline, drives stay on this phone and synchronize after connectivity returns.", "Bez internetu przejazdy zostają w telefonie i zsynchronizują się po odzyskaniu połączenia."), color = TougeMuted, fontSize = 11.sp)
            }
            error?.let { Text(it, color = TougeRed, fontSize = 12.sp) }
        }
    }
}

private fun passwordStrength(value: String): Float {
    var score = (value.length / 14f).coerceAtMost(.45f)
    if (value.any(Char::isUpperCase) && value.any(Char::isLowerCase)) score += .18f
    if (value.any(Char::isDigit)) score += .18f
    if (value.any { !it.isLetterOrDigit() }) score += .19f
    return score.coerceIn(0f, 1f)
}
