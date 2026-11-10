<!-- Copyright 2026 VitruvianSoftware. SPDX-License-Identifier: AGPL-3.0-or-later -->
# AI providers: bring your own

Status: design, 2026-11-09. Owner: the lead. Builders follow this; change it only by asking.

## What the person gets

- Courier's AI actions work: **Draft with AI**, **rewrite in a tone**, **translate a message**, **summarize a chat**,
  and the `/draft`, `/translate`, `/summarize`, `/ai` slash commands.
- They pick where the AI runs:
  - **On this Mac**: Apple Intelligence (macOS 26 or later, when the Mac supports it), **Ollama**, **LM Studio**,
    **Unsloth Studio**. Courier finds these by itself.
  - **In the cloud, with their own key**: **Anthropic**, **Google AI Studio** (Gemini), **OpenAI**, or any
    **OpenAI-compatible** endpoint (base URL plus optional key).
- AI output is never sent for them. It lands in the composer, or in a panel, for the person to edit and send.
- AI is **off by default**. Nothing leaves the Mac until they turn it on and choose a provider.
- Voice transcription and Talk to Type stay "not available yet" (out of scope; say so honestly).

## Acceptance criteria (UAT tests these)

1. With AI off (or no provider set), AI actions are disabled with the tooltip "Set up AI in Settings" (and slash
   commands show the "Set up AI in Settings" notice), and Courier makes **no network request** to any AI host.
2. Settings ▸ AI lists the providers in two groups, **On this Mac** and **Cloud**. A local server that is running
   shows as found with its model count; one that is not shows "Not running". A **Refresh** button re-checks.
3. With Ollama running (this Mac has it on 127.0.0.1:11434), choosing Ollama fills the Model menu with its
   models, and **Test** says it connected.
4. For a cloud provider, the person pastes a key into a secure field and presses **Save**. The key goes to the
   Keychain only. **Test** reports "Connected, N models" or the provider's error in plain words (bad key, no
   network, rate limited). **Remove key** deletes it.
5. Choosing a cloud provider shows, under the picker: "Messages you use with AI are sent to <Provider>." Choosing
   a local one shows: "Stays on this Mac."
6. In a chat, Draft with AI writes a reply into the composer (replacing nothing the person typed without asking:
   if the composer has text, the AI rewrites that text instead). Rewrite tones rewrite the composer text.
7. Translate on a message shows the translation inline under it, with a loading state and a clear error state.
8. The AI pane's Summarize shows a short summary of the open chat, with loading and error states. Errors offer
   **Open AI Settings**.
9. Switching chats cancels an AI request still running for the old chat; its result never lands in the new chat.
10. The test copy (`run_test_copy`) keeps its own Keychain items and settings, separate from the installed app.

## Architecture (CourierCore, Swift; the app talks to providers, not the Go engine)

Files (new unless noted), all under `apps/desktop/courier/app/Sources/CourierCore/AI/`:

- `AIProviderKind.swift`: replaces `AIEngineChoice` (keep that name as a `typealias` so nothing else breaks).
  Cases and raw values (raw values are stored in UserDefaults; keep the three existing ones exactly):
  `appleIntelligence`, `ollama`, `lmStudio`, `unslothStudio`, `anthropic`, `googleAIStudio`, `openAI`,
  `customOpenAICompatible`. Properties: `label`, `isLocal`, `needsKey` (cloud: yes; Unsloth Studio: yes, it
  refuses requests without its API key; Ollama, LM Studio, Apple: no), `defaultBaseURL`.
- `AIChatTurn.swift`: `struct AIChatTurn { role: .system/.user/.assistant; text: String }` and
  `struct AIChatContext { title: String; messages: [(senderName: String, mine: Bool, text: String)] }`.
- `HTTPTransport.swift`: `protocol HTTPTransport { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`,
  a `URLSession` implementation, and an in-memory stub for tests. Every client takes one; tests never touch the network.
- `ChatModelClient.swift`: `protocol ChatModelClient { func listModels() async throws -> [String];
  func complete(_ turns: [AIChatTurn], model: String) async throws -> String }` and `enum AIClientError`
  (`.notConfigured`, `.badKey`, `.rateLimited`, `.unreachable`, `.server(status: Int, message: String)`,
  `.badResponse`) with a plain-English `message` for each.
- Clients:
  - `AnthropicClient`: `POST https://api.anthropic.com/v1/messages`, headers `x-api-key`,
    `anthropic-version: 2023-06-01`; system text goes in the top-level `system` field; `max_tokens` 1024.
    Models: `GET /v1/models` (`data[].id`).
  - `GeminiClient` (Google AI Studio): `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`,
    header `x-goog-api-key` (never put the key in the URL); system text in `systemInstruction`. Models:
    `GET /v1beta/models`, keep those whose `supportedGenerationMethods` contains `generateContent`, strip the
    `models/` prefix.
  - `OpenAICompatibleClient(baseURL, key?)`: `POST {base}/chat/completions`, `Authorization: Bearer` only when a
    key is set; models `GET {base}/models` (`data[].id`). Used for OpenAI (`https://api.openai.com/v1`), Ollama
    (`http://127.0.0.1:11434/v1`), LM Studio (`http://127.0.0.1:1234/v1`), Unsloth Studio
    (`http://127.0.0.1:<port>/v1`, see detection) and Custom.
  - `AppleOnDeviceClient`: `#if canImport(FoundationModels)` and `if #available(macOS 26, *)`, using
    `SystemLanguageModel.default` (report its availability reason when unavailable). One model: "On-Device".
    Courier's minimum stays macOS 14; on older systems this client reports unavailable.
- Timeouts: model list and detection 2 s (detection probes 0.4 s each); completions 60 s cloud, 180 s local.
  Map 401/403 to `.badKey`, 429 to `.rateLimited`, connection refused / offline to `.unreachable`, and read the
  provider's error message from the body when present.
- `LocalProviderDetector.swift`: probes, all at once, `127.0.0.1:11434/api/tags` (Ollama),
  `127.0.0.1:1234/v1/models` (LM Studio), and `127.0.0.1:8888…8908/v1/models` (Unsloth Studio: it takes the
  first free port in that range and needs its API key; a 401 there still counts as **found, needs key**).
  Returns `[AIProviderKind: LocalDetection]` with `.running(models: [String])`, `.needsKey`, `.notRunning`.
  Probe only localhost. Never probe other hosts.
- `AIKeyStore.swift`: API keys in the Keychain via the existing `KeychainStore`, service
  `com.vitruviansoftware.courier.ai` (test copy: `com.vitruviansoftware.courier.dev.ai`, same pattern as
  `TelegramCredentials.service(for:)`), account = provider raw value. Keys never go to UserDefaults, logs, or
  `description` (redact like `TelegramCredentials`).
- `AIPrompts.swift`: builds the turns for each action. Draft: the last 30 text messages of the chat, oldest
  first, as "Name: text" lines ("Me" for mine), then "Write my next reply. Reply with only the message text."
  Rewrite: the composer text plus the tone's instruction. Translate: "Translate into <language>. Reply with only
  the translation." Summarize: the last 100 text messages, "Summarize in at most 5 short bullet points."
  Every system prompt includes the person's **Custom instructions** and **Preferred response language**.
  Attachments, media, and messages with no text are left out.
- `ConfiguredAIProvider.swift`: implements the `AIProvider` protocol on top of one client and model. The protocol
  changes so callers pass text, not ids: `draftResponse(context: AIChatContext, draft: String, tone: AIRewriteTone?)`,
  `translate(text:targetLanguage:)` (unchanged), `summarize(context: AIChatContext)`. Transcription and Talk to
  Type keep returning `.unavailable`. `UnavailableAIProvider` stays as the "AI off / not set up" provider.
- `AIProviderStore.swift` (`@MainActor ObservableObject`): owns the current `any AIProvider`, rebuilt when
  preferences or keys change; owns detection results and the model list; exposes `test()` and `refresh()`.
  `AppDelegate` creates one and hands it to Settings, the AI pane, `ComposerModel` and `MessageActionsModel`
  (today they each default to `UnavailableAIProvider()`).
- `AIPreferences` (existing file): add `customBaseURL: String` and `selectedModelByProvider: [String: String]`
  (remember the model per provider). `selectedEngine` keeps its key. Defaults unchanged: AI off.

## UI (Courier target)

- **Settings ▸ AI** (`AISettingsPane.swift`), top to bottom:
  1. Status banner: "AI is off", "Set up a provider", or "<Provider> · <model>" with a green dot.
  2. **Provider** section: the `Enable AI` toggle, then a list (not a dropdown) of providers in two groups,
     **On this Mac** and **Cloud**. Each row: provider name, a one-line state on the right (`3 models`,
     `Not running`, `Needs key`, `Key saved`, `Not set up`), a radio-style checkmark for the selected one.
     A `Refresh` button (arrow.clockwise) at the group header re-runs detection; while running it shows a small
     spinner and "Looking for local models…".
  3. **Selected provider** section: for key providers a `SecureField` with `Save` / `Remove key`; for Custom
     also the base URL field. Then the Model menu (filled from `listModels`, with its own refresh) and a `Test`
     button whose result shows inline (✓ Connected, 12 models / the error message). Then the privacy line
     (criterion 5) in secondary text.
  4. Existing sections stay: Custom instructions, translation languages, Talk to Type (still "not available
     yet"), slash commands.
- **Composer**: Draft with AI and the tone menu call the provider. While working, the composer shows a small
  inline "Writing…" row with a Stop button; on success the text goes into the composer (undoable); on error a
  calm notice with the error and "Open AI Settings".
- **Message menu ▸ Translate**: inline row under the message with loading, result, error.
- **AI pane** (`AIPane.swift`): replace the "not available" card with: provider/model line, Summarize button,
  the summary (selectable text, Copy), quick actions (Draft reply, Translate last message). Loading and error
  states as above.
- Follow the app's existing spacing, fonts and colours; no new colours. Every string through `String(localized:)`.

### Revisions after the UX review (2026-11-09; these win where they differ from the above)

- **No separate Enable toggle.** The provider list's first row is **Off**. Choosing any other row turns AI on;
  choosing Off turns it off (`enableContextualAI` follows the selection, so existing settings keep working).
- **Local rows have three states**: *Found · N models · Stays on this Mac*, *Installed · not running* with an
  **Open <app>** button (when the app exists in /Applications: `Ollama.app`, `LM Studio.app`, `Unsloth.app`),
  *Not found* with one "Get <app>" link. Not running is not an error: secondary text, no red.
  Detection runs when the pane opens and every 30 s while it stays open.
- **Keys**: `SecureField` with **Check** beside it; a "Get a key" link per provider. After saving show
  "Stored in Keychain · …<last 4>" and **Remove**; never show the key again.
- **Provenance on every result**: a footer line "via <model> · on this Mac" or "via <model> · sent to <Provider>".
  The privacy sentence in Settings: "Only the messages you use with AI, and your draft. Never your keys or other chats."
- **Where actions live**: no new composer button. "Draft a reply" and "Rewrite…" (tones) go in the composer's
  **+** menu. AI results in the composer appear as a strip above the text with **Replace · Insert · Discard**
  (the composer text is untouched until the person picks). Message menu: **Translate** (uses *Preferred response
  language*; a submenu offers the other enabled languages) — this also fixes today's bug where it used
  `translationLanguages.first`. **Summarize** goes in the chat's ⓘ menu and the command bar; the result shows in
  the AI pane, collapsed to one line ("Summary of N messages · on this Mac"), expandable.
- **AI pane**: remove the disabled "not available yet" rows. With no provider it shows one line and an
  **Open AI Settings** button.
- **No provider set**: AI actions stay visible but disabled with the tooltip "Set up AI in Settings"; choosing
  one opens Settings ▸ AI.
- **Loading / error**: in place, never modal. Loading: "Summarizing N messages…" / "Writing…" with **Cancel**.
  Error: one plain line and **Retry**; the person's text is never changed by a failure.

## Tests (must exist and pass under Bazel)

- Each client against the stub transport: the exact request (URL, method, headers, JSON body) and parsing of a
  recorded success response, plus 401, 429 and a provider error body. Assert the key never appears in the URL.
- Detector: running / needs key / not running, using the stub transport; Unsloth found on a port other than 8888.
- Key store against the in-memory `CredentialStore`; the test copy uses its own service name.
- Prompts: draft includes custom instructions and the language; attachments are left out; the 30/100 caps hold.
- `ConfiguredAIProvider` maps errors to `.unavailable(reason:)` with the plain message.
- AI off: `AIProviderStore` hands out `UnavailableAIProvider` and the stub transport records zero requests.
- Composer: an AI result for a chat you left never lands in the new chat (criterion 9).

## Out of scope

Voice transcription, Talk to Type, "mention an AI in chat" (the toggle stays as is), tool use, streaming
(responses arrive whole; fine for short replies), and the Go engine.
