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

package dev.vitruvian.remote.state

import java.io.File
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

public class AppInfoTest {
  private fun resolvePath(rel: String): File {
    val direct = File(rel)
    if (direct.exists()) return direct
    val base = System.getenv("TEST_SRCDIR") ?: error("TEST_SRCDIR unset and missing $rel")
    return listOf("_main", "vitruvian_core", "")
        .map { sub -> if (sub.isEmpty()) File(base, rel) else File(File(base, sub), rel) }
        .firstOrNull { it.exists() } ?: error("Runfile not found: $rel")
  }

  @Test
  public fun `donate URL is pinned and public URLs match spec`() {
    assertEquals("Vitruvian Remote", AppInfo.name)
    assertEquals(
        "https://vitruviansoftware.dev/donate/vitruvian-remote/?src=app-vitruvian-remote",
        AppInfo.donateURL,
    )
    assertEquals("https://github.com/VitruvianSoftware/vitruvian-remote", AppInfo.repositoryURL)
    assertEquals(
        "https://github.com/VitruvianSoftware/vitruvian-remote/issues",
        AppInfo.issuesURL,
    )
    assertEquals("https://vitruviansoftware.dev", AppInfo.websiteURL)
    assertEquals(
        "https://github.com/VitruvianSoftware/vitruvian-remote#readme",
        AppInfo.setupGuideURL,
    )
  }

  @Test
  public fun `no URL or source file in the app references stripe dot com`() {
    val srcMain = resolvePath("apps/mobile/vitruvian-remote/src/main")
    val files =
        srcMain
            .walkTopDown()
            .filter { file ->
              file.isFile &&
                  file.extension.lowercase(Locale.ROOT) in setOf("kt", "xml", "txt", "json")
            }
            .toList()
    assertTrue("Expected at least 20 files under src/main, got ${files.size}", files.size >= 20)
    val offenders =
        files.filter { file -> file.readText().contains("stripe.com", ignoreCase = true) }
    assertTrue(
        "No app source/resource may embed stripe.com: ${offenders.map { it.path }}",
        offenders.isEmpty(),
    )
  }

  @Test
  public fun `bundled raw license matches repo LICENSE file`() {
    val repoLicense = resolvePath("apps/mobile/vitruvian-remote/LICENSE").readText()
    val bundledLicense =
        resolvePath("apps/mobile/vitruvian-remote/src/main/res/raw/app_license.txt").readText()
    assertEquals(repoLicense, bundledLicense)
    assertTrue(repoLicense.startsWith("MIT License"))
  }

  @Test
  public fun `every maven dependency in BUILD has an open source license entry`() {
    val buildText = resolvePath("apps/mobile/vitruvian-remote/BUILD").readText()
    val libBlock = buildText.substringAfter("name = \"lib\",").substringBefore("_MANIFEST_BASE =")
    val mavenTargetsInBuild =
        Regex("\"@maven//:[A-Za-z0-9_]+\"").findAll(libBlock).map { it.value.trim('"') }.toSet()
    assertTrue("Expected @maven deps in :lib BUILD rule", mavenTargetsInBuild.isNotEmpty())

    val coveredTargets = AppInfo.openSourceLicenses.flatMap { it.mavenTargets }.toSet()
    assertEquals(
        "Every @maven dep in apps/mobile/vitruvian-remote/BUILD :lib must have an AppInfo.openSourceLicenses entry",
        mavenTargetsInBuild,
        coveredTargets,
    )

    val byName = AppInfo.openSourceLicenses.associateBy { it.name }
    assertEquals("MIT", byName.getValue("Sentry SDK").license)
    assertEquals("Apache-2.0", byName.getValue("AndroidX Compose").license)
    assertEquals("SIL OFL 1.1", byName.getValue("JetBrains Mono").license)
    assertEquals("SIL OFL 1.1", byName.getValue("IBM Plex Sans").license)
  }

  @Test
  public fun `version prerelease release copy and About back helpers work`() {
    assertFalse(AppInfo.isPrerelease("0.1.40"))
    assertFalse(AppInfo.isPrerelease("dev"))
    assertFalse(AppInfo.isPrerelease("0.1.40+build1"))
    assertTrue(AppInfo.isPrerelease("0.1.40-beta.1"))
    assertTrue(AppInfo.isPrerelease("0.1.40-rc.2"))
    assertTrue(AppInfo.isPrerelease("0.1.40-alpha"))

    assertEquals("vitruvian-remote@0.1.40", AppInfo.sentryRelease("0.1.40"))
    assertEquals("vitruvian-remote@dev", AppInfo.sentryRelease(""))
    assertEquals("vitruvian-remote@dev", AppInfo.sentryRelease(null))

    assertEquals(
        "Vitruvian Remote 0.1.40 (Android 15, Pixel Fold)",
        AppInfo.versionCopyLine("0.1.40", "15", "Pixel Fold"),
    )
    assertEquals(
        "Mac helper v0.1.40 on atlas",
        AppInfo.macHelperLine(isLive = true, agentVersion = "0.1.40", shortHostName = "atlas"),
    )
    assertEquals(
        "Mac helper v0.1.40 on atlas",
        AppInfo.macHelperLine(isLive = true, agentVersion = "v0.1.40", shortHostName = "atlas"),
    )
    assertNull(
        AppInfo.macHelperLine(isLive = false, agentVersion = "0.1.40", shortHostName = "atlas"),
    )
    assertNull(
        AppInfo.macHelperLine(isLive = true, agentVersion = "", shortHostName = "atlas"),
    )
    assertNull(
        AppInfo.macHelperLine(isLive = true, agentVersion = "0.1.40", shortHostName = "no host"),
    )

    assertNull(AppInfo.parentOfAboutPage(AboutPage.Main))
    assertEquals(AboutPage.Main, AppInfo.parentOfAboutPage(AboutPage.Privacy))
    assertEquals(AboutPage.Main, AppInfo.parentOfAboutPage(AboutPage.License))
    assertEquals(AboutPage.Main, AppInfo.parentOfAboutPage(AboutPage.OpenSourceLicenses))

    assertTrue(AppInfo.shouldAllowWhileUnpaired("Hosts"))
    assertTrue(AppInfo.shouldAllowWhileUnpaired("About"))
    assertFalse(AppInfo.shouldAllowWhileUnpaired("Home"))
  }
}
