// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package dev.vitruvian.remote.update

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import javax.net.ssl.HttpsURLConnection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The phone side of updating, as a port so `RemoteState` keeps no `Context` (the same shape as its
 * other ports). Null in previews and tests.
 */
public interface AppUpdates {
  public val installedVersionCode: Long

  public suspend fun check(): UpdateCheck

  /** Whether Android lets this app install packages: the "Install unknown apps" switch. */
  public fun canInstall(): Boolean

  /** Opens that switch's page in Settings, for this app only. */
  public fun openInstallPermission()

  /**
   * Downloads [release]'s APK, checks it, and hands it to Android's installer. Null once the
   * installer has it (the outcome arrives as an [InstallEvent]); otherwise why it stopped.
   */
  public suspend fun downloadAndInstall(
      release: UpdateFeed.Release,
      progress: (Float) -> Unit,
  ): String?

  /** Brings up Android's own confirmation screen, if one is waiting. */
  public fun confirmPendingInstall(): Boolean
}

/** Hands installer results from [UpdateInstallReceiver] to whoever is listening. */
public object UpdateInstallHub {
  @Volatile public var listener: ((InstallEvent) -> Unit)? = null

  /** Android's confirmation screen, kept so the About screen can bring it back up. */
  @Volatile public var pendingConfirmation: Intent? = null

  internal fun post(event: InstallEvent) {
    listener?.invoke(event)
  }
}

/**
 * Updates the app from the signed feed: fetch the feed and its signature, decide, then download the
 * APK, check its size, SHA-256, package, version and signer, and install it with `PackageInstaller`
 * as an update in place. An update keeps the app's data -- its Macs, pairing codes and settings --
 * because Android installs it over the same package signed by the same key, and [ApkCheck] refuses
 * anything Android would not install that way before a byte reaches the installer.
 *
 * On Android 12+ the session asks for `USER_ACTION_NOT_REQUIRED`: an app updating itself may
 * install without a confirmation screen once the person has allowed it to install apps. Android
 * still decides; when it wants a confirmation, the receiver shows Android's own screen.
 *
 * Not used: `setRequestUpdateOwnership` (Android 14). It would make every other installer -- an
 * Obtainium user's, or `adb install` during development -- ask first. Android already refuses an
 * update signed with another key, so ownership adds friction without adding protection here.
 */
public class AppUpdater(private val context: Context) : AppUpdates {
  private val pm: PackageManager = context.packageManager

  override val installedVersionCode: Long
    get() = versionCode(pm.getPackageInfo(context.packageName, 0))

  override suspend fun check(): UpdateCheck =
      withContext(Dispatchers.IO) {
        try {
          val feed = fetch(UpdateFeed.FEED_URL, UpdateFeed.MAX_FEED_BYTES)
          val signature = fetch(UpdateFeed.SIGNATURE_URL, UpdateFeed.MAX_SIGNATURE_BYTES)
          when (val result = UpdateFeed.verify(feed, String(signature, Charsets.US_ASCII))) {
            is UpdateFeed.Result.Refused -> UpdateCheck.Failed(result.reason)
            is UpdateFeed.Result.Ok ->
                UpdateCheck.Decided(
                    UpdatePolicy.decide(
                        installedVersionCode, Build.VERSION.SDK_INT, result.release),
                )
          }
        } catch (e: IOException) {
          UpdateCheck.Failed(OFFLINE)
        }
      }

  override fun canInstall(): Boolean = pm.canRequestPackageInstalls()

  override fun openInstallPermission() {
    val intent =
        Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}"),
            )
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(intent) }
  }

  override suspend fun downloadAndInstall(
      release: UpdateFeed.Release,
      progress: (Float) -> Unit,
  ): String? =
      withContext(Dispatchers.IO) {
        val dir = File(context.cacheDir, "updates")
        dir.deleteRecursively()
        dir.mkdirs()
        val apk = File(dir, "VitruvianRemote-${release.version}.apk")
        try {
          val sha = download(release, apk, progress)
          val refusal = ApkCheck.refusal(facts(apk, sha), release, installedSigning())
          if (refusal != null) {
            apk.delete()
            return@withContext refusal
          }
          install(apk, release)
        } catch (e: IOException) {
          apk.delete()
          OFFLINE_DOWNLOAD
        } catch (e: SecurityException) {
          apk.delete()
          "Android didn't let the app install updates. Allow it under Install unknown apps."
        }
      }

  override fun confirmPendingInstall(): Boolean {
    val intent = UpdateInstallHub.pendingConfirmation ?: return false
    return runCatching {
          context.startActivity(Intent(intent).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        .isSuccess
  }

  private fun open(url: String): HttpsURLConnection {
    val connection = URL(url).openConnection()
    // The app allows cleartext for the Mac agent on the tailnet (network_security_config.xml);
    // nothing the update reads may ever travel that way.
    if (connection !is HttpsURLConnection) throw IOException("not https")
    connection.connectTimeout = TIMEOUT_MS
    connection.readTimeout = TIMEOUT_MS
    connection.instanceFollowRedirects = true
    connection.setRequestProperty("User-Agent", "VitruvianRemote")
    if (connection.responseCode != HttpURLConnection.HTTP_OK) {
      connection.disconnect()
      throw IOException("HTTP ${connection.responseCode}")
    }
    // HttpURLConnection only follows https to https, but say so rather than rely on it.
    if (connection.url.protocol != "https") throw IOException("redirected off https")
    return connection
  }

  private fun fetch(url: String, limit: Int): ByteArray {
    val connection = open(url)
    try {
      connection.inputStream.use { input ->
        val bytes = readAtMost(input, limit + 1L)
        if (bytes.size > limit) throw IOException("too large")
        return bytes
      }
    } finally {
      connection.disconnect()
    }
  }

  /** Writes the APK to [into] and returns its SHA-256; never writes more than the feed's size. */
  private fun download(release: UpdateFeed.Release, into: File, progress: (Float) -> Unit): String {
    val connection = open(release.apkUrl)
    try {
      val digest = MessageDigest.getInstance("SHA-256")
      var total = 0L
      connection.inputStream.use { input ->
        into.outputStream().use { output ->
          val buffer = ByteArray(64 * 1024)
          while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            total += n
            if (total > release.apkSize) break
            digest.update(buffer, 0, n)
            output.write(buffer, 0, n)
            progress((total.toFloat() / release.apkSize).coerceIn(0f, 1f))
          }
        }
      }
      return Checksums.hex(digest.digest())
    } finally {
      connection.disconnect()
    }
  }

  private fun readAtMost(input: InputStream, limit: Long): ByteArray {
    val out = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(8 * 1024)
    while (out.size() < limit) {
      val n = input.read(buffer, 0, minOf(buffer.size.toLong(), limit - out.size()).toInt())
      if (n < 0) break
      out.write(buffer, 0, n)
    }
    return out.toByteArray()
  }

  private fun facts(apk: File, sha: String): ApkFacts {
    val info = archiveInfo(apk)
    val (signers, history) = info?.let(::certificates) ?: (emptySet<String>() to emptySet())
    return ApkFacts(
        size = apk.length(),
        sha256 = sha,
        packageName = info?.packageName,
        versionCode = info?.let(::versionCode),
        signers = signers,
        signingHistory = history,
    )
  }

  @Suppress("DEPRECATION")
  private fun archiveInfo(apk: File): PackageInfo? =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        pm.getPackageArchiveInfo(apk.path, PackageManager.GET_SIGNING_CERTIFICATES)
      } else {
        pm.getPackageArchiveInfo(apk.path, PackageManager.GET_SIGNATURES)
      }

  @SuppressLint("PackageManagerGetSignatures")
  @Suppress("DEPRECATION")
  private fun installedSigning(): InstalledSigning {
    val info =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
          pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        } else {
          pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)
        }
    val (signers, _) = certificates(info)
    val multiple =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
          info.signingInfo?.hasMultipleSigners() == true
        } else {
          (info.signatures?.size ?: 0) > 1
        }
    return InstalledSigning(signers, multiple)
  }

  /** The certificates a package is signed with now, and its whole rotation history. */
  @Suppress("DEPRECATION")
  private fun certificates(info: PackageInfo): Pair<Set<String>, Set<String>> {
    fun digest(bytes: ByteArray) = Checksums.sha256Hex(bytes)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      val signing = info.signingInfo ?: return emptySet<String>() to emptySet()
      val now = signing.apkContentsSigners.orEmpty().map { digest(it.toByteArray()) }.toSet()
      val history =
          if (signing.hasMultipleSigners()) now
          else signing.signingCertificateHistory.orEmpty().map { digest(it.toByteArray()) }.toSet()
      return now to (history + now)
    }
    val now = info.signatures.orEmpty().map { digest(it.toByteArray()) }.toSet()
    return now to now
  }

  @Suppress("DEPRECATION")
  private fun versionCode(info: PackageInfo): Long =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
      else info.versionCode.toLong()

  /**
   * Streams the checked file into a session, hashing it again on the way so the bytes Android
   * installs are the bytes that were checked, and commits it.
   */
  private fun install(apk: File, release: UpdateFeed.Release): String? {
    val installer = pm.packageInstaller
    val params =
        PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
          setAppPackageName(context.packageName)
          setSize(apk.length())
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
          }
        }
    val id = installer.createSession(params)
    val session = installer.openSession(id)
    try {
      val digest = MessageDigest.getInstance("SHA-256")
      session.openWrite("base.apk", 0, apk.length()).use { out ->
        apk.inputStream().use { input ->
          val buffer = ByteArray(64 * 1024)
          while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            digest.update(buffer, 0, n)
            out.write(buffer, 0, n)
          }
        }
        session.fsync(out)
      }
      if (Checksums.hex(digest.digest()) != release.apkSha256) {
        session.abandon()
        return "The download changed while it was being installed, so it wasn't installed."
      }
      UpdateInstallHub.pendingConfirmation = null
      val intent =
          Intent(context, UpdateInstallReceiver::class.java)
              .setAction(UpdateInstallReceiver.ACTION)
              .setPackage(context.packageName)
      // Mutable: the installer adds the status and, if it wants one, the confirmation screen.
      val flags =
          PendingIntent.FLAG_UPDATE_CURRENT or
              (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE
              else 0)
      val pending = PendingIntent.getBroadcast(context, id, intent, flags)
      session.commit(pending.intentSender)
      return null
    } catch (e: Exception) {
      runCatching { session.abandon() }
      throw e
    } finally {
      session.close()
    }
  }

  private companion object {
    const val TIMEOUT_MS = 15_000
    const val OFFLINE = "Couldn't reach vitruviansoftware.dev to check for updates."
    const val OFFLINE_DOWNLOAD = "The download didn't finish. Check the connection and try again."
  }
}

/** Receives the installer's verdict for a session [AppUpdater] committed. Not exported. */
public class UpdateInstallReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != ACTION) return
    when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, Int.MIN_VALUE)) {
      PackageInstaller.STATUS_PENDING_USER_ACTION -> {
        val confirm =
            confirmation(intent) ?: return UpdateInstallHub.post(InstallEvent.Failed(GENERIC))
        UpdateInstallHub.pendingConfirmation = confirm
        UpdateInstallHub.post(InstallEvent.NeedsConfirmation)
        // Allowed while the app is on screen, which it is when the person tapped Update. If
        // Android blocks it (the app went to the background), About keeps a button for it.
        runCatching {
          context.startActivity(Intent(confirm).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
      }
      PackageInstaller.STATUS_SUCCESS -> {
        UpdateInstallHub.pendingConfirmation = null
        UpdateInstallHub.post(InstallEvent.Installed)
      }
      else -> {
        UpdateInstallHub.pendingConfirmation = null
        UpdateInstallHub.post(InstallEvent.Failed(reason(status)))
      }
    }
  }

  @Suppress("DEPRECATION")
  private fun confirmation(intent: Intent): Intent? =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
      } else {
        intent.getParcelableExtra(Intent.EXTRA_INTENT)
      }

  private fun reason(status: Int): String =
      when (status) {
        PackageInstaller.STATUS_FAILURE_ABORTED -> "The update was cancelled. Nothing changed."
        PackageInstaller.STATUS_FAILURE_STORAGE ->
            "There isn't enough space on the phone for the update."
        PackageInstaller.STATUS_FAILURE_CONFLICT,
        PackageInstaller.STATUS_FAILURE_INCOMPATIBLE ->
            "Android refused the update because it doesn't match the installed app. Nothing changed."
        PackageInstaller.STATUS_FAILURE_BLOCKED -> "Android blocked the update."
        else -> GENERIC
      }

  public companion object {
    public const val ACTION: String = "dev.vitruvian.remote.update.INSTALL_STATUS"
    private const val GENERIC = "The update didn't install. Nothing changed; try again later."
  }
}
