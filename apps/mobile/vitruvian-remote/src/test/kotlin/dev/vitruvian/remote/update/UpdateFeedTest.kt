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

import java.io.ByteArrayInputStream
import java.io.File
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateFeedTest {
  private val pair: KeyPair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
  private val publicKey: String =
      Base64.getEncoder().encodeToString(pair.public.encoded.takeLast(32).toByteArray())
  private val sha = "ab".repeat(32)

  private fun feed(
      version: String = "0.1.47",
      versionCode: Long = 147,
      url: String =
          "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/" +
              "vitruvian-remote-v$version/VitruvianRemote-$version.apk",
      kind: String = "vitruvian-android-update",
      schema: Int = 1,
      packageName: String = "dev.vitruvian.remote",
      size: String = "9700000",
      sha256: String = sha,
  ): String =
      """
      {
        "kind": "$kind",
        "schema": $schema,
        "packageName": "$packageName",
        "version": "$version",
        "versionCode": $versionCode,
        "minSdk": 26,
        "published": "2026-11-18T17:00:00Z",
        "apk": { "url": "$url", "size": $size, "sha256": "$sha256" },
        "notes": ["Settings → About can update the app.", "  ", 5]
      }
      """
          .trimIndent()

  private fun sign(bytes: ByteArray, with: KeyPair = pair): String {
    val s = Signature.getInstance("Ed25519")
    s.initSign(with.private)
    s.update(bytes)
    return Base64.getEncoder().encodeToString(s.sign())
  }

  private fun check(json: String): UpdateFeed.Result {
    val bytes = json.toByteArray()
    return UpdateFeed.verify(bytes, sign(bytes), publicKey)
  }

  private fun refused(result: UpdateFeed.Result): String =
      (result as? UpdateFeed.Result.Refused)?.reason ?: error("expected a refusal, got $result")

  @Test
  fun aSignedFeedReads() {
    val ok = check(feed()) as UpdateFeed.Result.Ok
    assertEquals("0.1.47", ok.release.version)
    assertEquals(147L, ok.release.versionCode)
    assertEquals(9_700_000L, ok.release.apkSize)
    assertEquals(sha, ok.release.apkSha256)
    assertEquals(listOf("Settings → About can update the app."), ok.release.notes)
  }

  @Test
  fun anyChangeAfterSigningIsRefused() {
    val bytes = feed().toByteArray()
    val signature = sign(bytes)
    val changed = String(bytes).replace("9700000", "9700001").toByteArray()
    assertTrue(refused(UpdateFeed.verify(changed, signature, publicKey)).contains("isn't signed"))
    val other = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
    assertTrue(refused(UpdateFeed.verify(bytes, sign(bytes, other), publicKey)).contains("signed"))
    assertTrue(refused(UpdateFeed.verify(bytes, "not base64!", publicKey)).contains("signed"))
    assertTrue(refused(UpdateFeed.verify(bytes, "", publicKey)).contains("signed"))
  }

  @Test
  fun everyFieldIsChecked() {
    refused(check(feed(kind = "vitruvian-tool-catalog")))
    refused(check(feed(packageName = "com.example.other")))
    assertTrue(refused(check(feed(schema = 2))).contains("newer format"))
    refused(check(feed(versionCode = 148)))
    refused(check(feed(version = "0.1.47-beta", versionCode = 147)))
    refused(check(feed(size = "0")))
    refused(check(feed(size = "1.5")))
    refused(check(feed(size = "999999999999")))
    refused(check(feed(sha256 = sha.uppercase())))
    refused(check(feed(sha256 = sha.dropLast(1))))
    refused(check("[]"))
    refused(check("{"))
  }

  @Test
  fun theApkMayOnlyComeFromThisRepositorysOwnRelease() {
    val github = "https://github.com/VitruvianSoftware/vitruvian-core/releases/download"
    for (url in
        listOf(
            "http://github.com/VitruvianSoftware/vitruvian-core/releases/download/" +
                "vitruvian-remote-v0.1.47/VitruvianRemote-0.1.47.apk",
            "https://example.com/VitruvianRemote-0.1.47.apk",
            "$github/vitruvian-remote-v0.1.46/VitruvianRemote-0.1.47.apk",
            "$github/vitruvian-speaker-v0.1.47/VitruvianRemote-0.1.47.apk",
            "$github/vitruvian-remote-v0.1.47/VitruvianRemote-0.1.47.apk?x=1",
        )) {
      assertTrue(url, refused(check(feed(url = url))).contains("somewhere other"))
    }
  }

  @Test
  fun oversizedFeedsAreRefusedBeforeAnyCrypto() {
    val big = ByteArray(UpdateFeed.MAX_FEED_BYTES + 1)
    assertTrue(refused(UpdateFeed.verify(big, sign(big), publicKey)).contains("too large"))
  }

  @Test
  fun versionCodesMatchBuildsFormula() {
    assertEquals(146L, Versions.code("0.1.46"))
    assertEquals(10203L, Versions.code("1.2.3"))
    assertEquals(1_00_00L, Versions.code("1.0.0"))
    assertNull(Versions.code("0.1.100"))
    assertNull(Versions.code("1.2"))
    assertNull(Versions.code("dev"))
    assertNull(Versions.code("1.2.3-rc.1"))
    // Ordering by code is ordering by version, which is what makes comparing codes enough.
    val ordered = listOf("0.1.9", "0.1.10", "0.1.46", "0.2.0", "0.10.0", "1.0.0", "2.0.1")
    assertEquals(ordered, ordered.shuffled(java.util.Random(3)).sortedBy { Versions.code(it) })
  }

  @Test
  fun decideComparesVersionCodes() {
    val release = (check(feed()) as UpdateFeed.Result.Ok).release
    assertEquals(UpdateDecision.Available(release), UpdatePolicy.decide(138, 36, release))
    assertEquals(UpdateDecision.UpToDate, UpdatePolicy.decide(147, 36, release))
    assertEquals(UpdateDecision.UpToDate, UpdatePolicy.decide(200, 36, release))
    assertEquals(
        UpdateDecision.NeedsNewerAndroid(release),
        UpdatePolicy.decide(138, 25, release),
    )
  }

  private val installed = InstalledSigning(setOf("aa".repeat(32)), multipleSigners = false)

  private fun facts(
      release: UpdateFeed.Release,
      signers: Set<String> = installed.signers,
      history: Set<String> = signers,
      sha256: String = release.apkSha256,
      size: Long = release.apkSize,
      packageName: String? = "dev.vitruvian.remote",
      versionCode: Long? = release.versionCode,
  ) = ApkFacts(size, sha256, packageName, versionCode, signers, history)

  @Test
  fun theApkMustBeTheReleaseAndSignedLikeTheInstalledApp() {
    val release = (check(feed()) as UpdateFeed.Result.Ok).release
    assertNull(ApkCheck.refusal(facts(release), release, installed))
    assertTrue(
        ApkCheck.refusal(facts(release, sha256 = "cd".repeat(32)), release, installed)!!.contains(
            "checksum"))
    assertTrue(ApkCheck.refusal(facts(release, size = 1), release, installed)!!.contains("size"))
    assertTrue(
        ApkCheck.refusal(facts(release, packageName = "x"), release, installed)!!.contains(
            "isn't Vitruvian Remote"))
    assertTrue(
        ApkCheck.refusal(facts(release, versionCode = 146), release, installed)!!.contains(
            "version"))
    val stranger = setOf("bb".repeat(32))
    assertTrue(
        ApkCheck.refusal(facts(release, signers = stranger), release, installed)!!.contains(
            "different key"))
    assertTrue(
        ApkCheck.refusal(facts(release, signers = emptySet()), release, installed)!!.contains(
            "couldn't be read"))
    assertTrue(
        ApkCheck.refusal(facts(release), release, InstalledSigning(emptySet(), false))!!.contains(
            "couldn't be read"))
  }

  @Test
  fun aKeyRotatedFromTheInstalledOneIsAccepted() {
    val release = (check(feed()) as UpdateFeed.Result.Ok).release
    val newKey = setOf("cc".repeat(32))
    val rotated = facts(release, signers = newKey, history = newKey + installed.signers)
    assertNull(ApkCheck.refusal(rotated, release, installed))
    val several = InstalledSigning(setOf("aa".repeat(32), "dd".repeat(32)), multipleSigners = true)
    assertTrue(ApkCheck.refusal(facts(release), release, several) != null)
    assertNull(ApkCheck.refusal(facts(release, signers = several.signers), release, several))
  }

  @Test
  fun checksumsAreLowerCaseHexSha256() {
    val abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    assertEquals(abc, Checksums.sha256Hex("abc".toByteArray()))
    assertEquals(abc, Checksums.sha256Hex(ByteArrayInputStream("abc".toByteArray())))
    val big = ByteArray(200_000) { (it % 251).toByte() }
    assertEquals(Checksums.sha256Hex(big), Checksums.sha256Hex(ByteArrayInputStream(big)))
  }

  @Test
  fun aboutStatesFollowTheCheckAndTheInstaller() {
    val release = (check(feed()) as UpdateFeed.Result.Ok).release
    assertEquals(UpdateUi.UpToDate, UpdateUi.from(UpdateCheck.Decided(UpdateDecision.UpToDate)))
    assertEquals(
        UpdateUi.Available(release),
        UpdateUi.from(UpdateCheck.Decided(UpdateDecision.Available(release))),
    )
    assertEquals(UpdateUi.Failed("offline", null), UpdateUi.from(UpdateCheck.Failed("offline")))
    val installing = UpdateUi.Installing(release)
    assertTrue(installing.busy)
    assertEquals(
        UpdateUi.Confirm(release), UpdateUi.after(installing, InstallEvent.NeedsConfirmation))
    assertEquals(UpdateUi.UpToDate, UpdateUi.after(installing, InstallEvent.Installed))
    assertEquals(
        UpdateUi.Failed("no space", release),
        UpdateUi.after(installing, InstallEvent.Failed("no space")),
    )
    // A confirmation with nothing in flight changes nothing.
    assertEquals(UpdateUi.Idle, UpdateUi.after(UpdateUi.Idle, InstallEvent.NeedsConfirmation))
  }

  @Test
  fun aboutSaysWhatIsAvailableInPlainWords() {
    val release = (check(feed()) as UpdateFeed.Result.Ok).release
    assertEquals(
        "Update available: 0.1.47", UpdateCopy.headline(UpdateUi.Available(release), "0.1.38"))
    assertEquals("You're up to date (0.1.47).", UpdateCopy.headline(UpdateUi.UpToDate, "0.1.47"))
    assertEquals(
        "Downloading 0.1.47… 42%",
        UpdateCopy.headline(UpdateUi.Downloading(release, 0.42f), "0.1.38"),
    )
    assertTrue(UpdateCopy.PERMISSION.contains("Install unknown apps"))
    assertTrue(UpdateCopy.INSTALLING.contains("settings stay"))
  }

  private val root = File(System.getenv("TEST_SRCDIR"), System.getenv("TEST_WORKSPACE"))

  @Test
  fun thePinnedKeyIsTheCataloguesKey() {
    assertEquals(File(root, "catalog/public-key.txt").readText().trim(), UpdateFeed.PUBLIC_KEY)
  }

  /** The feed on main is one this app reads, and names a release built by BUILD's formula. */
  @Test
  fun theCommittedFeedReads() {
    val text = File(root, "catalog/android/vitruvian-remote.json").readText()
    val ok = UpdateFeed.parse(text) as UpdateFeed.Result.Ok
    assertEquals(Versions.code(ok.release.version), ok.release.versionCode)
  }

  /**
   * Once the website serves the feed, it serves it signed with the catalogue key. Absent only
   * between this test landing and catalog-publish's first run; a copy that is there must verify.
   */
  @Test
  fun theWebsitesCopyIsSigned() {
    val site = File(root, "apps/web/vitruviansoftware-dev/updates/android")
    val copy = File(site, "vitruvian-remote.json")
    if (!copy.exists()) return
    val result =
        UpdateFeed.verify(copy.readBytes(), File(site, "vitruvian-remote.json.sig").readText())
    assertTrue("$result", result is UpdateFeed.Result.Ok)
  }
}
