/**
 * Copyright (c) 2026 VitruvianSoftware
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import { createTextChat } from './textChat.js';
import { GevRealtimeController } from './realtimeController.js';

/** Adapt the existing WebRTC implementation to the common voice session. */
export function createRealtimeSession({
  emit,
  runAction,
  createController = (options) => new GevRealtimeController(options),
  ...options
}) {
  const controller = createController({
    ...options,
    actionExecutor: runAction,
    onSessionEvent: emit,
  });
  let textOnly = false;
  const chat = createTextChat({
    ...options,
    provider: 'openai',
    runAction,
    emit: (event) => {
      if (event.type === 'state') controller.status = event.state;
      emit(event);
    },
  });
  const startVoice = (settings) => {
    chat.stop({ preserveStatus: true });
    textOnly = false;
    return controller.start(settings);
  };
  if (controller._input) controller._input.start = startVoice;
  if (controller._radio)
    controller._radio.isActive = () => !textOnly && controller.isActive();
  return {
    controller,
    capabilities: { costControls: true, pushToTalk: true },
    start: (settings) => {
      if (!settings?.textOnly) return startVoice(settings);
      textOnly = true;
      return chat.start();
    },
    getStartOptions: () => ({
      pushToTalk: Boolean(controller.pushToTalkMode),
      ...(textOnly ? { textOnly: true } : {}),
    }),
    stop: (settings) => {
      chat.stop({ ...settings, preserveStatus: true });
      controller.stop(settings);
    },
    // Chat Stop: abort the reply in progress, keep the conversation.
    cancelTurn: () => textOnly && chat.cancelTurn(),
    sendText: (text) =>
      textOnly ? chat.sendText(text) : controller.sendTextCommand(text),
    sendMapEvent: (event) =>
      textOnly ? chat.sendMapEvent(event) : controller.notifyMapEvent(event),
    ignoreButtonClick: () => Boolean(controller.spaceKeyHeld),
    bindControls() {
      // Kept as the remover; a full stop releases it. The cost readout and
      // tier toggle are worded again in a new locale.
      const offTier = controller.ui.on('tier', () =>
        controller.toggleVoiceTier(),
      );
      const offLocale = controller.ui.on('locale', () =>
        controller.syncCostUi(),
      );
      controller.tierHandler = () => {
        offTier();
        offLocale();
      };
      controller.syncCostUi();
      controller.bindPushToTalkShortcut();
    },
  };
}
