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

package dev.vitruvian.wear.common

import java.util.Locale

/**
 * Voice-to-Agent routing and wrist approval models for `nexus-wrist`.
 *
 * Classifies spoken transcripts from the Pixel Watch 4 microphone into the specialist subagent
 * roster (`ridge`, `scout`, `atlas`, `aegis`, `wren`, or `beacon`) and encodes one-tap PR/alert
 * approvals for the Mac agent bridge.
 */
public enum class SpecialistAgent(public val id: String, public val roleTitle: String) {
  BEACON("beacon", "Lead Dispatcher"),
  RIDGE("ridge", "Homelab & SRE"),
  SCOUT("scout", "CI & Merge Queue"),
  ATLAS("atlas", "Pulumi & Infra"),
  AEGIS("aegis", "Security & RBAC"),
  WREN("wren", "App Engineering"),
}

public enum class ApprovalDecision(public val wireValue: String, public val label: String) {
  APPROVE_AND_ENQUEUE("approve_enqueue", "Enqueue"),
  HOLD_PR("hold_pr", "Hold"),
  ACK_ALERT("ack_alert", "Ack Alert"),
  DISMISS("dismiss", "Dismiss"),
}

public data class PendingApprovalItem(
    val id: String,
    val title: String,
    val subtitle: String,
    val agent: SpecialistAgent,
    val prNumber: Int? = null,
)

public data class VoiceDispatchRequest(
    val transcript: String,
    val routedAgent: SpecialistAgent,
) {
  public fun toJsonPayload(): String = buildString {
    append("""{"agent":"""")
    append(RemoteWireCodec.escapeJson(routedAgent.id))
    append("""","prompt":"""")
    append(RemoteWireCodec.escapeJson(transcript.trim()))
    append("""","source":"pixel-watch-4"}""")
  }
}

public object VoiceAgentRouter {
  private val ridgeKeywords =
      listOf("pod", "k3s", "cluster", "argocd", "flap", "flapping", "homelab", "prometheus", "node")
  private val scoutKeywords =
      listOf("pr", "pull request", "ci", "check", "merge queue", "enqueue", "test", "flaky")
  private val atlasKeywords =
      listOf("pulumi", "envoy", "cilium", "gateway", "dns", "cloudflare", "terraform")
  private val aegisKeywords =
      listOf("cve", "security", "secret", "rbac", "networkpolicy", "vault", "bitwarden")
  private val wrenKeywords =
      listOf("watch", "ui", "kotlin", "swift", "typescript", "component", "app", "refactor")

  public fun route(transcript: String): VoiceDispatchRequest {
    val cleaned = transcript.trim()
    val lower = cleaned.lowercase(Locale.ROOT)
    val words = lower.split(Regex("[^a-z0-9]+")).filter { it.isNotEmpty() }.toSet()
    fun matchesAny(keywords: List<String>): Boolean =
        keywords.any { kw -> if (' ' in kw) kw in lower else kw in words }
    val agent =
        when {
          matchesAny(ridgeKeywords) -> SpecialistAgent.RIDGE
          matchesAny(atlasKeywords) -> SpecialistAgent.ATLAS
          matchesAny(aegisKeywords) -> SpecialistAgent.AEGIS
          matchesAny(scoutKeywords) -> SpecialistAgent.SCOUT
          matchesAny(wrenKeywords) -> SpecialistAgent.WREN
          else -> SpecialistAgent.BEACON
        }
    return VoiceDispatchRequest(transcript = cleaned, routedAgent = agent)
  }

  public fun encodeApproval(item: PendingApprovalItem, decision: ApprovalDecision): String =
      buildString {
        append("""{"itemId":"""")
        append(RemoteWireCodec.escapeJson(item.id))
        append("""","decision":"""")
        append(RemoteWireCodec.escapeJson(decision.wireValue))
        append("""","agent":"""")
        append(RemoteWireCodec.escapeJson(item.agent.id))
        append('"')
        if (item.prNumber != null) {
          append(""","prNumber":""")
          append(item.prNumber)
        }
        append('}')
      }
}
