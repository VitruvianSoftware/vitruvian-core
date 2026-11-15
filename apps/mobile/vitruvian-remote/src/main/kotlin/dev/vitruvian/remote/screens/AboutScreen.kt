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

package dev.vitruvian.remote.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.vitruvian.design.ButtonVariant
import dev.vitruvian.design.Hit
import dev.vitruvian.design.Label
import dev.vitruvian.design.ListItem
import dev.vitruvian.design.Plate
import dev.vitruvian.design.Rule
import dev.vitruvian.design.Space
import dev.vitruvian.design.Tag
import dev.vitruvian.design.TagTone
import dev.vitruvian.design.VButton
import dev.vitruvian.design.VDialog
import dev.vitruvian.design.VIcon
import dev.vitruvian.design.VMark
import dev.vitruvian.design.VSwitch
import dev.vitruvian.design.VText
import dev.vitruvian.design.Vitruvian
import dev.vitruvian.design.VitruvianIcons
import dev.vitruvian.design.VitruvianType
import dev.vitruvian.remote.R
import dev.vitruvian.remote.state.AboutPage
import dev.vitruvian.remote.state.AppInfo
import dev.vitruvian.remote.state.RemoteState
import kotlinx.coroutines.delay

private val ABOUT_MARK_SIZE = Space.s5
private const val COPIED_BADGE_TIMEOUT_MS = 2000L

/**
 * About Vitruvian Remote: identity, support, privacy (with the persisted crash-report switch),
 * bundled MIT license, and open-source notices.
 */
@Composable
public fun ColumnScope.AboutScreen(state: RemoteState) {
  when (state.aboutPage) {
    AboutPage.Main -> AboutMainContent(state)
    AboutPage.Privacy -> PrivacyContent(state)
    AboutPage.License -> LicenseContent()
    AboutPage.OpenSourceLicenses -> OpenSourceLicensesContent()
  }
}

@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
private fun AboutMainContent(state: RemoteState) {
  val colors = Vitruvian
  LaunchedEffect(state.versionCopied) {
    if (state.versionCopied) {
      delay(COPIED_BADGE_TIMEOUT_MS)
      state.clearVersionCopied()
    }
  }

  Column(
      modifier = Modifier.padding(horizontal = Space.s4, vertical = Space.s4).fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s4),
  ) {
    Plate(modifier = Modifier.fillMaxWidth()) {
      Column(
          modifier = Modifier.padding(Space.s4).fillMaxWidth(),
          verticalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.s3),
        ) {
          VMark(markSize = ABOUT_MARK_SIZE)
          VText(text = AppInfo.name, style = VitruvianType.h2, color = colors.text)
        }
        Row(
            modifier =
                Modifier.fillMaxWidth()
                    .defaultMinSize(minHeight = Hit.h1)
                    .combinedClickable(
                        onClick = {},
                        onLongClick = state::copyVersionInfo,
                    ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.s2),
        ) {
          VText(
              text = "Version ${state.appVersion}",
              style = VitruvianType.listSub,
              color = colors.textDim,
          )
          if (AppInfo.isPrerelease(state.appVersion)) {
            Tag(text = "beta", tone = TagTone.Warn)
          }
          if (state.versionCopied) {
            Tag(text = "Copied", tone = TagTone.Ok)
          }
        }
        VText(text = AppInfo.tagline, style = VitruvianType.body, color = colors.text)
        VText(
            text = AppInfo.copyrightNotice,
            style = VitruvianType.listSub,
            color = colors.textDim,
        )
        state.aboutMacHelperLine?.let { line ->
          VText(text = line, style = VitruvianType.listSub, color = colors.textDim)
        }
      }
    }

    Plate(modifier = Modifier.fillMaxWidth()) {
      Column(
          modifier = Modifier.padding(Space.s4).fillMaxWidth(),
          verticalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        Label("Support")
        VText(text = AppInfo.supportBody, style = VitruvianType.body, color = colors.text)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(Space.s3),
            verticalArrangement = Arrangement.spacedBy(Space.s3),
        ) {
          VButton(
              label = "Donate",
              onClick = { state.openExternalUrl(AppInfo.donateURL) },
              variant = ButtonVariant.Primary,
              trailingIcon = VitruvianIcons.EXTERNAL_LINK,
          )
          VButton(
              label = "Star on GitHub",
              onClick = { state.openExternalUrl(AppInfo.repositoryURL) },
              trailingIcon = VitruvianIcons.EXTERNAL_LINK,
          )
        }
      }
    }
  }

  AboutLinkRow(
      title = "Source code",
      subtitle = AppInfo.repositoryLabel,
      iconPath = VitruvianIcons.EXTERNAL_LINK,
      onClick = { state.openExternalUrl(AppInfo.repositoryURL) },
  )
  AboutLinkRow(
      title = "Privacy",
      subtitle = "What leaves this phone",
      iconPath = VitruvianIcons.CHEVRON_RIGHT,
      onClick = { state.openAboutPage(AboutPage.Privacy) },
  )
  AboutLinkRow(
      title = "License",
      subtitle = "MIT",
      iconPath = VitruvianIcons.CHEVRON_RIGHT,
      onClick = { state.openAboutPage(AboutPage.License) },
  )
  AboutLinkRow(
      title = "Open-source licenses",
      subtitle = "Libraries and fonts",
      iconPath = VitruvianIcons.CHEVRON_RIGHT,
      onClick = { state.openAboutPage(AboutPage.OpenSourceLicenses) },
  )
  AboutLinkRow(
      title = "Help and feedback",
      subtitle = "Report a problem on GitHub",
      iconPath = VitruvianIcons.EXTERNAL_LINK,
      onClick = { state.openExternalUrl(AppInfo.issuesURL) },
  )
  AboutLinkRow(
      title = "Setup guide",
      subtitle = "Install the Mac helper",
      iconPath = VitruvianIcons.EXTERNAL_LINK,
      onClick = state::openInstallGuide,
  )
}

@Composable
private fun AboutLinkRow(
    title: String,
    subtitle: String,
    iconPath: String,
    onClick: () -> Unit,
) {
  ListItem(
      title = title,
      subtitle = subtitle,
      onClick = onClick,
      contentPadding = PaddingValues(horizontal = Space.s4, vertical = Space.s3),
  ) {
    VIcon(path = iconPath, color = Vitruvian.textDim, contentDescription = null)
  }
}

@Composable
private fun PrivacyContent(state: RemoteState) {
  val colors = Vitruvian
  Box(modifier = Modifier.padding(horizontal = Space.s4, vertical = Space.s4).fillMaxWidth()) {
    Plate(modifier = Modifier.fillMaxWidth()) {
      Column(
          modifier = Modifier.padding(Space.s4).fillMaxWidth(),
          verticalArrangement = Arrangement.spacedBy(Space.s4),
      ) {
        Label("What leaves this phone")
        AppInfo.privacyLeadingStatements.forEach { statement ->
          VText(text = statement, style = VitruvianType.body, color = colors.text)
          Rule(modifier = Modifier.fillMaxWidth().height(1.dp))
        }
        VText(
            text = AppInfo.privacyCrashReportsStatement,
            style = VitruvianType.body,
            color = colors.text,
        )
        VSwitch(
            checked = state.sendCrashReports,
            onCheckedChange = state::updateSendCrashReports,
            label = "Send crash reports",
        )
        AppInfo.privacyTrailingStatements.forEach { statement ->
          Rule(modifier = Modifier.fillMaxWidth().height(1.dp))
          VText(text = statement, style = VitruvianType.body, color = colors.text)
        }
      }
    }
  }
}

@Composable
private fun LicenseContent() {
  val context = LocalContext.current
  val licenseText =
      remember(context) {
        context.resources.openRawResource(R.raw.app_license).bufferedReader().use { it.readText() }
      }
  Box(modifier = Modifier.padding(horizontal = Space.s4, vertical = Space.s4).fillMaxWidth()) {
    Plate(modifier = Modifier.fillMaxWidth()) {
      Column(
          modifier = Modifier.padding(Space.s4).fillMaxWidth(),
          verticalArrangement = Arrangement.spacedBy(Space.s3),
      ) {
        Label("MIT License")
        SelectionContainer {
          VText(text = licenseText.trimEnd(), style = VitruvianType.mono, color = Vitruvian.text)
        }
      }
    }
  }
}

@Composable
private fun OpenSourceLicensesContent() {
  Column(
      modifier = Modifier.padding(horizontal = Space.s4, vertical = Space.s4).fillMaxWidth(),
      verticalArrangement = Arrangement.spacedBy(Space.s3),
  ) {
    Label("Libraries and fonts")
    Plate(modifier = Modifier.fillMaxWidth()) {
      Column(modifier = Modifier.fillMaxWidth()) {
        AppInfo.openSourceLicenses.forEach { entry ->
          ListItem(
              title = entry.name,
              subtitle = entry.detail,
              contentPadding = PaddingValues(horizontal = Space.s4, vertical = Space.s3),
          ) {
            Tag(text = entry.license, tone = TagTone.Outline)
          }
        }
      }
    }
  }
}

/** Shown when `ACTION_VIEW` cannot find a browser on the device so the URL stays usable. */
@Composable
public fun FallbackUrlDialog(state: RemoteState) {
  val url = state.fallbackUrl ?: return
  val colors = Vitruvian
  VDialog(
      onDismissRequest = state::dismissFallbackUrl,
      kicker = "Open in browser",
      kickerColor = colors.accentText,
      title = "No browser found",
      body = "Copy or select this link to open it in a browser.",
  ) {
    SelectionContainer { VText(text = url, style = VitruvianType.mono, color = colors.text) }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(Space.s3, Alignment.End),
    ) {
      VButton("Copy link", state::copyFallbackUrl)
      VButton(
          label = "Done",
          onClick = state::dismissFallbackUrl,
          variant = ButtonVariant.Primary,
      )
    }
  }
}
