package it.letscode.tougedash.ui

import android.content.Intent
import android.net.Uri
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.CredentialManager
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.CloudSync
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import it.letscode.tougedash.BuildConfig
import it.letscode.tougedash.data.local.SyncState
import it.letscode.tougedash.di.AppContainer
import it.letscode.tougedash.ui.theme.TougeCyan
import it.letscode.tougedash.ui.theme.TougeMint
import it.letscode.tougedash.ui.theme.TougeMuted
import it.letscode.tougedash.ui.theme.TougeOrange
import it.letscode.tougedash.ui.theme.TougePanelLight
import it.letscode.tougedash.ui.theme.TougeRed
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import kotlinx.coroutines.launch

@Composable
fun CloudAccountCard(container: AppContainer) {
    val account by container.authRepository.session.collectAsState()
    val working by container.authRepository.working.collectAsState()
    val error by container.authRepository.error.collectAsState()
    val sessions by container.dao.sessions().collectAsState(initial = emptyList())
    val incidents by container.dao.incidents().collectAsState(initial = emptyList())
    val pendingAnnotations by container.dao.pendingAnnotationCount().collectAsState(initial = 0)
    val pendingSamples by container.dao.pendingSampleCount().collectAsState(initial = 0)
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var confirmDelete by remember { mutableStateOf(false) }

    TougePanelSurface(TougeCyan, Modifier.fillMaxWidth().padding(top = 14.dp)) {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            AccountHeading(signedIn = account != null)

            if (account != null) {
                val current = requireNotNull(account)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        Modifier.size(46.dp).background(TougeCyan.copy(alpha = .12f), CutCornerShape(10.dp)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(Icons.Default.AccountCircle, null, tint = TougeCyan, modifier = Modifier.size(27.dp))
                    }
                    Spacer(Modifier.width(12.dp))
                    Column {
                        Text(current.account.displayName, fontSize = 21.sp, fontWeight = FontWeight.Black)
                        Text(current.account.email, color = TougeMuted, fontSize = 12.sp)
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { container.cloudSyncRepository.schedule() },
                        modifier = Modifier.weight(1f),
                        shape = CutCornerShape(9.dp)
                    ) {
                        Icon(Icons.Default.CloudSync, null, modifier = Modifier.size(18.dp))
                        Text(appText(" Sync now", " Synchronizuj"), fontWeight = FontWeight.Black)
                    }
                    OutlinedButton(
                        onClick = { scope.launch { container.authRepository.logout() } },
                        modifier = Modifier.weight(1f),
                        shape = CutCornerShape(9.dp)
                    ) {
                        Icon(Icons.AutoMirrored.Filled.Logout, null, modifier = Modifier.size(18.dp))
                        Text(appText(" Sign out", " Wyloguj"), fontWeight = FontWeight.Bold)
                    }
                }
                val pendingSessions = sessions.count { it.syncState != SyncState.SYNCED }
                val pendingIncidents = incidents.count { it.syncState != SyncState.SYNCED }
                val uploading = sessions.filter { it.syncState == SyncState.UPLOADING }
                val sentBytes = uploading.sumOf { it.syncBytesSent }
                val totalBytes = uploading.sumOf { it.syncBytesTotal }
                Column(
                    Modifier.fillMaxWidth().background(Color.White.copy(alpha = .035f), CutCornerShape(8.dp)).padding(11.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    if (totalBytes > 0) {
                        LinearProgressIndicator(progress = { (sentBytes.toFloat() / totalBytes).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth())
                        Text("${cloudBytes(sentBytes)} / ${cloudBytes(totalBytes)} · $pendingSamples ${appText("samples", "próbek")}", color = TougeMuted, fontSize = 10.sp)
                    } else if (pendingSessions + pendingIncidents + pendingAnnotations > 0) {
                        Text(
                            "$pendingSessions ${appText("drives", "przejazdów")} · $pendingIncidents ${appText("incidents", "incydentów")} · $pendingAnnotations ${appText("notes", "notatek")} · $pendingSamples ${appText("samples", "próbek")}",
                            color = TougeOrange,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Black
                        )
                        Text(appText("Waiting for upload. Synchronization resumes automatically when the network returns.", "Czekają na wysłanie. Synchronizacja wznowi się automatycznie po powrocie sieci."), color = TougeMuted, fontSize = 10.sp)
                    } else {
                        Text(appText("Cloud data is up to date", "Dane w chmurze są aktualne"), color = TougeMint, fontSize = 10.sp, fontWeight = FontWeight.Black)
                    }
                }
                OutlinedButton(
                    onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(BuildConfig.WEB_BASE_URL + "/profile"))) },
                    modifier = Modifier.fillMaxWidth(),
                    shape = CutCornerShape(9.dp)
                ) {
                    Icon(Icons.Default.Language, null, modifier = Modifier.size(18.dp))
                    Text(appText(" Profile, vehicles and sharing", " Profil, auta i udostępnianie"), fontWeight = FontWeight.Bold)
                }
                TextButton(onClick = { confirmDelete = true }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.DeleteForever, null, tint = TougeRed)
                    Text(appText(" Delete cloud account", " Usuń konto w chmurze"), color = TougeRed)
                }
            } else {
                SignedOutForm(container, working)
            }

            error?.let {
                Text(
                    it,
                    color = TougeRed,
                    fontSize = 12.sp,
                    modifier = Modifier.fillMaxWidth().background(TougeRed.copy(alpha = .07f), CutCornerShape(7.dp)).padding(11.dp)
                )
            }
            TextButton(
                onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(BuildConfig.WEB_BASE_URL + "/privacy"))) },
                modifier = Modifier.fillMaxWidth()
            ) { Text(appText("Privacy policy", "Polityka prywatności"), color = TougeCyan) }
        }
    }

    if (confirmDelete) AlertDialog(
        onDismissRequest = { confirmDelete = false },
        title = { Text(appText("Delete account and cloud data?", "Usunąć konto i dane z chmury?")) },
        text = { Text(appText(
            "This permanently removes your account, vehicles, synchronized drives, locations, sharing links and active server sessions. Local history on this Android device stays available.",
            "To bezpowrotnie usunie konto, auta, zsynchronizowane przejazdy, lokalizacje, linki udostępnień i aktywne sesje serwera. Lokalna historia na tym urządzeniu z Androidem pozostanie dostępna."
        )) },
        confirmButton = {
            Button(onClick = { scope.launch { if (container.authRepository.deleteAccount()) confirmDelete = false } }) {
                Text(if (working) appText("Deleting…", "Usuwanie…") else appText("Delete permanently", "Usuń bezpowrotnie"))
            }
        },
        dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(appText("Cancel", "Anuluj")) } }
    )
}

@Composable
private fun AccountHeading(signedIn: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(
            appText("ONLINE GARAGE", "GARAŻ ONLINE"),
            color = TougeCyan,
            fontSize = 10.sp,
            fontWeight = FontWeight.Black,
            letterSpacing = 1.8.sp
        )
        Text(
            appText(if (signedIn) "Your Touge Dash account" else "Sign in to Touge Dash", if (signedIn) "Twoje konto Touge Dash" else "Zaloguj się do Touge Dash"),
            fontSize = 22.sp,
            fontWeight = FontWeight.Black
        )
        Text(
            appText(
                if (signedIn) "Drive synchronization is active." else "Keep drives, vehicles and dashboards synchronized.",
                if (signedIn) "Synchronizacja przejazdów jest aktywna." else "Synchronizuj przejazdy, auta i dashboardy."
            ),
            color = TougeMuted,
            fontSize = 12.sp
        )
    }
}

@Composable
private fun SignedOutForm(container: AppContainer, working: Boolean) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var register by remember { mutableStateOf(false) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var showPassword by remember { mutableStateOf(false) }
    var googleWorking by remember { mutableStateOf(false) }
    val validEmail = email.contains('@') && email.substringAfter('@').contains('.')
    val validPassword = if (register) password.length in 10..72 && password.any(Char::isLetter) && password.any(Char::isDigit) else password.isNotEmpty()
    val canSubmit = !working && validEmail && validPassword && (!register || name.isNotBlank())
    val invalidGoogleResponse = appText(
        "Google returned an invalid sign-in response. Please try again.",
        "Google zwróciło nieprawidłową odpowiedź logowania. Spróbuj ponownie."
    )

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            Modifier.fillMaxWidth().background(Color.White.copy(alpha = .035f), CutCornerShape(10.dp)).border(1.dp, Color.White.copy(alpha = .07f), CutCornerShape(10.dp)).padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            ModeButton(appText("Sign in", "Logowanie"), selected = !register, Modifier.weight(1f)) { register = false }
            ModeButton(appText("Create account", "Nowe konto"), selected = register, Modifier.weight(1f)) { register = true }
        }

        if (register) {
            CloudField(
                value = name,
                onValueChange = { name = it },
                label = appText("DISPLAY NAME", "NAZWA"),
                icon = { Icon(Icons.Default.Person, null) }
            )
        }
        CloudField(
            value = email,
            onValueChange = { email = it },
            label = "E-MAIL",
            isError = email.isNotEmpty() && !validEmail,
            keyboardType = KeyboardType.Email,
            icon = { Icon(Icons.Default.Email, null) }
        )
        CloudField(
            value = password,
            onValueChange = { if (it.length <= 72) password = it },
            label = appText("PASSWORD", "HASŁO"),
            isError = password.isNotEmpty() && !validPassword,
            keyboardType = KeyboardType.Password,
            visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
            icon = { Icon(Icons.Default.Lock, null) },
            trailing = {
                IconButton(onClick = { showPassword = !showPassword }) {
                    Icon(if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility, appText("Toggle password visibility", "Pokaż lub ukryj hasło"))
                }
            }
        )

        if (register && password.isNotEmpty()) PasswordStrength(password)

        Button(
            enabled = canSubmit,
            onClick = {
                scope.launch {
                    val success = if (register) container.authRepository.register(email, password, name) else container.authRepository.login(email, password)
                    if (success) container.cloudSyncRepository.schedule()
                }
            },
            modifier = Modifier.fillMaxWidth().height(50.dp),
            shape = CutCornerShape(9.dp),
            colors = ButtonDefaults.buttonColors(containerColor = TougeCyan, contentColor = Color.Black)
        ) {
            Text(
                if (working) appText("PLEASE WAIT…", "CHWILA…") else if (register) appText("CREATE ACCOUNT", "UTWÓRZ KONTO") else appText("SIGN IN", "ZALOGUJ SIĘ"),
                fontWeight = FontWeight.Black,
                letterSpacing = 1.sp
            )
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            HorizontalDivider(Modifier.weight(1f), color = Color.White.copy(alpha = .08f))
            Text(appText("  OR  ", "  LUB  "), color = TougeMuted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            HorizontalDivider(Modifier.weight(1f), color = Color.White.copy(alpha = .08f))
        }

        Button(
            onClick = {
                scope.launch {
                    googleWorking = true
                    try {
                        val option = GetSignInWithGoogleOption.Builder(BuildConfig.GOOGLE_WEB_CLIENT_ID).build()
                        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
                        val credential = CredentialManager.create(context).getCredential(context, request).credential
                        if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                            error("Unsupported Google credential")
                        }
                        val idToken = GoogleIdTokenCredential.createFrom(credential.data).idToken
                        if (container.authRepository.social("GOOGLE", idToken)) {
                            container.cloudSyncRepository.schedule()
                        }
                    } catch (_: GetCredentialCancellationException) {
                        // Closing the Google account chooser is an intentional cancellation.
                    } catch (_: GoogleIdTokenParsingException) {
                        container.authRepository.reportError(invalidGoogleResponse)
                    } catch (_: Exception) {
                        // Devices without a usable Credential Manager can finish the same
                        // secure flow in the browser and return through the app deep link.
                        openGoogleWebFallback(context)
                    } finally {
                        googleWorking = false
                    }
                }
            },
            enabled = !working && !googleWorking,
            modifier = Modifier.fillMaxWidth().height(48.dp),
            shape = CutCornerShape(9.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF4F7F8), contentColor = Color(0xFF142027))
        ) {
            Text("G", color = Color(0xFF4285F4), fontSize = 18.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.width(11.dp))
            Text(
                if (googleWorking) appText("OPENING GOOGLE…", "OTWIERANIE GOOGLE…") else appText("Continue with Google", "Kontynuuj przez Google"),
                fontWeight = FontWeight.Bold
            )
        }

        Text(
            appText(
                "When offline, drives stay on this phone and synchronize after connectivity returns.",
                "Bez internetu przejazdy zostają w telefonie i zsynchronizują się po odzyskaniu połączenia."
            ),
            color = TougeMuted,
            fontSize = 11.sp
        )
    }
}

private fun openGoogleWebFallback(context: android.content.Context) {
    val auth = Uri.parse(BuildConfig.WEB_BASE_URL + "/auth").buildUpon()
        .appendQueryParameter("provider", "google")
        .appendQueryParameter("mobileReturn", "tougedash://auth")
        .build()
    context.startActivity(Intent(Intent.ACTION_VIEW, auth))
}

@Composable
private fun ModeButton(title: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Box(
        modifier
            .background(if (selected) Color.White.copy(alpha = .09f) else Color.Transparent, CutCornerShape(7.dp))
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(title, color = if (selected) Color.White else TougeMuted, fontSize = 12.sp, fontWeight = FontWeight.Black)
    }
}

@Composable
private fun CloudField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    isError: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    icon: @Composable () -> Unit,
    trailing: (@Composable () -> Unit)? = null
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label, fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp) },
        leadingIcon = icon,
        trailingIcon = trailing,
        singleLine = true,
        isError = isError,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        visualTransformation = visualTransformation,
        modifier = Modifier.fillMaxWidth(),
        shape = CutCornerShape(9.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = TougeCyan,
            unfocusedBorderColor = Color.White.copy(alpha = .09f),
            focusedContainerColor = TougePanelLight.copy(alpha = .58f),
            unfocusedContainerColor = TougePanelLight.copy(alpha = .38f),
            focusedLeadingIconColor = TougeCyan,
            unfocusedLeadingIconColor = TougeMuted
        )
    )
}

@Composable
private fun PasswordStrength(password: String) {
    val strength = passwordStrength(password)
    val valid = password.length in 10..72 && password.any(Char::isLetter) && password.any(Char::isDigit)
    Column(
        Modifier.fillMaxWidth().background(Color.White.copy(alpha = .03f), CutCornerShape(8.dp)).padding(11.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(appText("PASSWORD STRENGTH", "SIŁA HASŁA"), color = TougeMuted, fontSize = 9.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp)
            Text(
                if (strength < .35f) appText("WEAK", "SŁABE") else if (strength < .7f) appText("GOOD", "DOBRE") else appText("STRONG", "SILNE"),
                color = if (valid) TougeMint else TougeMuted,
                fontSize = 9.sp,
                fontWeight = FontWeight.Black
            )
        }
        LinearProgressIndicator(
            progress = { strength },
            modifier = Modifier.fillMaxWidth().height(4.dp),
            color = if (valid) TougeMint else TougeRed,
            trackColor = Color.White.copy(alpha = .07f)
        )
        Text(
            appText("10–72 characters · at least one letter · at least one number", "10–72 znaki · minimum jedna litera · minimum jedna cyfra"),
            color = if (valid) TougeMint else TougeMuted,
            fontSize = 10.sp
        )
    }
}

private fun passwordStrength(value: String): Float {
    var score = (value.length / 14f).coerceAtMost(.45f)
    if (value.any(Char::isUpperCase) && value.any(Char::isLowerCase)) score += .18f
    if (value.any(Char::isDigit)) score += .18f
    if (value.any { !it.isLetterOrDigit() }) score += .19f
    return score.coerceIn(0f, 1f)
}

private fun cloudBytes(value: Long): String = when {
    value >= 1_073_741_824 -> "%.1f GB".format(value / 1_073_741_824.0)
    value >= 1_048_576 -> "%.1f MB".format(value / 1_048_576.0)
    value >= 1_024 -> "%.0f kB".format(value / 1_024.0)
    else -> "$value B"
}
