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

import dev.vitruvian.remote.state.JsonReader
import java.io.InputStream
import java.security.MessageDigest
import java.util.Base64

/**
 * The update feed: one small JSON file on vitruviansoftware.dev that names the newest release, its
 * APK, the APK's size and SHA-256, and what changed.
 *
 * Trust comes from the signature, not from the website. The file is signed with VitruvianSoftware's
 * Ed25519 catalogue key (the one the Mac app's tool catalogue uses; `catalog/public-key.txt`), by
 * the `catalog-publish` workflow, over the exact bytes merged to `main`. So a feed that someone
 * changed on the way, or on the web host, fails here and nothing is downloaded.
 *
 * No Android imports, so `UpdateFeedTest` runs on a plain JVM.
 */
public object UpdateFeed {
  public const val FEED_URL: String =
      "https://vitruviansoftware.dev/updates/android/vitruvian-remote.json"
  public const val SIGNATURE_URL: String = "$FEED_URL.sig"

  /** Same line as `catalog/public-key.txt`; `UpdateFeedTest` fails when they differ. */
  public const val PUBLIC_KEY: String = "ysvqcMifelrOyxEx01sOS4B5VN585nBLKkdaaT0xyWY="

  /** Says what the signed bytes are, so a signed tool catalogue can never pass for a feed. */
  public const val KIND: String = "vitruvian-android-update"
  public const val PACKAGE_NAME: String = "dev.vitruvian.remote"

  /** The only place an APK may come from: this repository's own Vitruvian Remote releases. */
  public const val DOWNLOAD_PREFIX: String =
      "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/vitruvian-remote-v"

  public const val MAX_FEED_BYTES: Int = 64 * 1024
  public const val MAX_SIGNATURE_BYTES: Int = 1024
  public const val MAX_APK_BYTES: Long = 200L * 1024 * 1024
  private const val MAX_NOTES = 40
  private const val MAX_NOTE_CHARS = 400

  /** What a feed parses to, once its signature and every field check out. */
  public data class Release(
      val version: String,
      val versionCode: Long,
      val minSdk: Int,
      val apkUrl: String,
      val apkSize: Long,
      val apkSha256: String,
      val notes: List<String>,
      val published: String,
  )

  public sealed interface Result {
    public data class Ok(val release: Release) : Result

    /** [reason] is a sentence for the About screen; it never contains the feed's own text. */
    public data class Refused(val reason: String) : Result
  }

  /**
   * Checks [signatureText] (base64, as `catalog-publish` writes it) over [feedBytes], then reads
   * the feed. Refuses anything it does not fully understand.
   */
  public fun verify(
      feedBytes: ByteArray,
      signatureText: String,
      publicKey: String = PUBLIC_KEY,
  ): Result {
    if (feedBytes.size > MAX_FEED_BYTES) return refused("The update list is too large.")
    val signature = decode(signatureText.trim()) ?: return refused(UNSIGNED)
    val key = decode(publicKey.trim()) ?: return refused(UNSIGNED)
    if (!Ed25519.verify(feedBytes, signature, key)) return refused(UNSIGNED)
    return parse(String(feedBytes, Charsets.UTF_8))
  }

  /** Reads an already-verified feed. Public for the test that reads the committed feed. */
  public fun parse(json: String): Result {
    val o =
        runCatching { JsonReader(json).readValue() as? Map<*, *> }.getOrNull()
            ?: return refused(MALFORMED)
    if (o["kind"] != KIND) return refused(MALFORMED)
    if ((o["schema"] as? Number)?.toDouble() != 1.0) {
      return refused("This update list is a newer format. Update from the website instead.")
    }
    if (o["packageName"] != PACKAGE_NAME) return refused(MALFORMED)
    val version = o["version"] as? String ?: return refused(MALFORMED)
    val code = Versions.code(version) ?: return refused(MALFORMED)
    if (whole(o["versionCode"]) != code) return refused(MALFORMED)
    val minSdk = whole(o["minSdk"])?.toInt() ?: return refused(MALFORMED)
    val apk = o["apk"] as? Map<*, *> ?: return refused(MALFORMED)
    val url = apk["url"] as? String ?: return refused(MALFORMED)
    if (url != "$DOWNLOAD_PREFIX$version/VitruvianRemote-$version.apk") {
      return refused("The update points somewhere other than Vitruvian's own releases.")
    }
    val size = whole(apk["size"]) ?: return refused(MALFORMED)
    if (size <= 0 || size > MAX_APK_BYTES) return refused(MALFORMED)
    val sha = apk["sha256"] as? String ?: return refused(MALFORMED)
    if (!SHA256_HEX.matches(sha)) return refused(MALFORMED)
    val notes =
        (o["notes"] as? List<*> ?: emptyList<Any>())
            .mapNotNull { (it as? String)?.trim()?.takeIf(String::isNotEmpty) }
            .map { it.take(MAX_NOTE_CHARS) }
            .take(MAX_NOTES)
    val published = (o["published"] as? String).orEmpty()
    return Result.Ok(Release(version, code, minSdk, url, size, sha, notes, published))
  }

  private fun whole(value: Any?): Long? {
    val d = (value as? Number)?.toDouble() ?: return null
    if (d != Math.floor(d) || d < 0 || d > 9.0e15) return null
    return d.toLong()
  }

  private fun decode(text: String): ByteArray? =
      runCatching { Base64.getDecoder().decode(text) }.getOrNull()

  private fun refused(reason: String) = Result.Refused(reason)

  private const val UNSIGNED =
      "The update list isn't signed by Vitruvian Software, so nothing was downloaded."
  private const val MALFORMED = "The update list couldn't be read, so nothing was downloaded."
  private val SHA256_HEX = Regex("[0-9a-f]{64}")
}

/** Release versions are `major.minor.patch`, and the Android versionCode is derived from them. */
public object Versions {
  private val CORE = Regex("(\\d{1,3})\\.(\\d{1,2})\\.(\\d{1,2})")

  /**
   * The versionCode `BUILD` stamps for [version]: `major*10000 + minor*100 + patch`. Null for
   * anything that is not plain `X.Y.Z` with minor and patch under 100, where that formula collides.
   */
  public fun code(version: String): Long? {
    val m = CORE.matchEntire(version.trim()) ?: return null
    val (major, minor, patch) = m.destructured
    return major.toLong() * 10000 + minor.toLong() * 100 + patch.toLong()
  }
}

/** What the app does with a verified feed, given what is installed. */
public sealed interface UpdateDecision {
  public data object UpToDate : UpdateDecision

  public data class Available(val release: UpdateFeed.Release) : UpdateDecision

  /** Newer, but not for this phone's Android version. */
  public data class NeedsNewerAndroid(val release: UpdateFeed.Release) : UpdateDecision
}

public object UpdatePolicy {
  /**
   * Compares by versionCode, as Android does: an update must have a higher one, and installing a
   * lower one would be refused (and would be a downgrade even if it were not).
   */
  public fun decide(
      installedVersionCode: Long,
      sdkInt: Int,
      release: UpdateFeed.Release,
  ): UpdateDecision =
      when {
        release.versionCode <= installedVersionCode -> UpdateDecision.UpToDate
        sdkInt < release.minSdk -> UpdateDecision.NeedsNewerAndroid(release)
        else -> UpdateDecision.Available(release)
      }
}

/** What the downloaded APK says about itself, read by the Android side before anything installs. */
public data class ApkFacts(
    val size: Long,
    val sha256: String,
    val packageName: String?,
    val versionCode: Long?,
    /** SHA-256 of each certificate the APK is signed with now, lower-case hex. */
    val signers: Set<String>,
    /**
     * Every certificate in its signing history (APK Signature Scheme v3 rotation), [signers] too.
     */
    val signingHistory: Set<String>,
)

/** The installed app's signing certificates, in the same form as [ApkFacts]. */
public data class InstalledSigning(val signers: Set<String>, val multipleSigners: Boolean)

public object ApkCheck {
  /**
   * Null when the downloaded file is exactly the release the signed feed names, and is signed so
   * Android will install it over this app keeping its data; otherwise the sentence saying why not.
   *
   * The signer rule is Android's own: the new APK must be signed by the installed app's
   * certificate, or by a key that certificate rotated to (its signing history includes it). An app
   * with several signers needs exactly the same set. Checking first means a mismatch is a clear
   * sentence here rather than an install that fails, or one that would need the app (and its
   * pairings) removed first.
   */
  public fun refusal(
      facts: ApkFacts,
      release: UpdateFeed.Release,
      installed: InstalledSigning,
  ): String? =
      when {
        facts.size != release.apkSize ->
            "The download is a different size from the release, so it wasn't installed."
        facts.sha256 != release.apkSha256 ->
            "The download doesn't match the release's checksum, so it wasn't installed."
        facts.packageName != UpdateFeed.PACKAGE_NAME ->
            "The download isn't Vitruvian Remote, so it wasn't installed."
        facts.versionCode != release.versionCode ->
            "The download isn't the version the update list names, so it wasn't installed."
        installed.signers.isEmpty() || facts.signers.isEmpty() ->
            "The app's signature couldn't be read, so nothing was installed."
        !signedLikeInstalled(facts, installed) ->
            "This update is signed with a different key from the app on this phone, so " +
                "Android would refuse it. Nothing was installed and your settings are untouched."
        else -> null
      }

  private fun signedLikeInstalled(facts: ApkFacts, installed: InstalledSigning): Boolean =
      if (installed.multipleSigners) {
        facts.signers == installed.signers
      } else {
        installed.signers.all { it in facts.signingHistory || it in facts.signers }
      }
}

public object Checksums {
  /** Lower-case hex SHA-256 of everything [input] holds; reads it to the end, closes nothing. */
  public fun sha256Hex(input: InputStream): String {
    val digest = MessageDigest.getInstance("SHA-256")
    val buffer = ByteArray(64 * 1024)
    while (true) {
      val n = input.read(buffer)
      if (n < 0) break
      digest.update(buffer, 0, n)
    }
    return hex(digest.digest())
  }

  public fun sha256Hex(bytes: ByteArray): String =
      hex(MessageDigest.getInstance("SHA-256").digest(bytes))

  public fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }
}
