import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import os from 'os';
import { Telegraf, Markup } from 'telegraf';
import { execFile } from 'child_process';
import {
  executePrompt, executePromptStreaming, clearSession, hasSession, getSession,
  setSessionResume, getChatSettings, setChatSetting,
  listSessions, deleteSession, listMcpServers, listExtensions, listSkills,
  extractImagePaths, extractFilePaths, cancelPrompt, getRunningInfo,
} from './gemini.js';
import {
  getSessionName, setSessionName, getWorkspaces, setWorkspace, deleteWorkspace,
} from './sessions.js';
import { splitMessage, formatResponse } from './formatter.js';

// Temp directory for downloaded Telegram files
const TEMP_DIR = path.join(os.tmpdir(), 'nexus-agent-files');
fs.mkdirSync(TEMP_DIR, { recursive: true });

// Rate limiting (#9)
const RATE_LIMIT_MS = 3000; // minimum 3s between requests per chat
const lastRequestTime = new Map(); // chatId -> timestamp

// ─── Configuration ───────────────────────────────────────────────────────────

const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
if (!BOT_TOKEN) {
  console.error('❌ TELEGRAM_BOT_TOKEN is required. Set it in .env');
  process.exit(1);
}

const ALLOWED_USER_IDS = (process.env.ALLOWED_USER_IDS || '')
  .split(',')
  .map((id) => id.trim())
  .filter(Boolean)
  .map(Number);

const WORKING_DIR = process.env.GEMINI_WORKING_DIR || process.cwd();

// ─── Bot Setup ───────────────────────────────────────────────────────────────

const bot = new Telegraf(BOT_TOKEN, {
  handlerTimeout: 600_000, // 10 minutes — CLI with MCP servers can take a while
});

// ─── Auth Middleware ─────────────────────────────────────────────────────────

bot.use((ctx, next) => {
  const userId = ctx.from?.id;

  if (ALLOWED_USER_IDS.length > 0 && !ALLOWED_USER_IDS.includes(userId)) {
    console.log(`⛔ Unauthorized access attempt from user ${userId} (@${ctx.from?.username})`);
    return ctx.reply('⛔ You are not authorized to use this bot.');
  }

  return next();
});

// ─── Core Commands ───────────────────────────────────────────────────────────

bot.command('start', (ctx) => {
  const name = ctx.from?.first_name || 'there';
  ctx.reply(
    `👋 Hi ${name}! I'm your Gemini CLI bridge.\n\n` +
    `Send me any message and I'll forward it to Gemini CLI running on your machine.\n\n` +
    `📂 Working directory: ${WORKING_DIR}\n\n` +
    `Type /help to see all available commands.`
  );
});

bot.command('help', (ctx) => {
  ctx.reply(
    `🤖 Gemini CLI Telegram Bot\n\n` +
    `Just send me a message — I'll pass it to Gemini CLI and return the response.\n\n` +
    `━━━ Session Commands ━━━\n` +
    `/new — Start a fresh session\n` +
    `/cancel — Cancel the current running request\n` +
    `/status — Check if a request is running and how long\n` +
    `/session — Show current session info\n` +
    `/sessions — Browse and resume sessions\n` +
    `/name <label> — Name the current session\n` +
    `/resume <n> — Resume session by index\n` +
    `/delete_session <n> — Delete a session by index\n\n` +
    `━━━ CLI Management ━━━\n` +
    `/extensions — List installed extensions\n` +
    `/skills — List available skills\n` +
    `/mcp — List MCP servers\n\n` +
    `━━━ Settings ━━━\n` +
    `/model <name> — Set the Gemini model\n` +
    `/mode <mode> — Set approval mode (default|auto_edit|yolo)\n` +
    `/thinking — Toggle thinking mode\n` +
    `/sandbox — Toggle sandbox mode\n` +
    `/workdir — Manage workspace shortcuts\n` +
    `/settings — Show current settings\n\n` +
    `━━━ Other ━━━\n` +
    `/help — Show this message`
  );
});

// ─── Session Commands ────────────────────────────────────────────────────────

bot.command('new', (ctx) => {
  clearSession(ctx.chat.id);
  ctx.reply('🆕 Session cleared. Your next message will start a fresh conversation.');
});

bot.command('cancel', (ctx) => {
  const chatId = ctx.chat.id;
  const wasRunning = cancelPrompt(chatId);
  if (wasRunning) {
    ctx.reply('⛔ Request cancelled. The running prompt has been terminated.');
  } else {
    ctx.reply('ℹ️ No request is currently running.');
  }
});

bot.command('status', (ctx) => {
  const chatId = ctx.chat.id;
  const info = getRunningInfo(chatId);
  if (info) {
    const elapsed = Math.round((Date.now() - info.startTime) / 1000);
    const mins = Math.floor(elapsed / 60);
    const secs = elapsed % 60;
    ctx.reply(
      `⏳ Request in progress\n\n` +
      `⏱️ Elapsed: ${mins}m ${secs}s\n` +
      `💬 Prompt: ${info.prompt}${info.prompt.length >= 100 ? '...' : ''}\n\n` +
      `Use /cancel to stop it.`
    );
  } else {
    ctx.reply('✅ No request is currently running.');
  }
});

bot.command('session', (ctx) => {
  const chatId = ctx.chat.id;
  const settings = getChatSettings(chatId);
  if (hasSession(chatId)) {
    ctx.reply(
      `📋 Active session: ${getSession(chatId)}\n` +
      `📂 Working dir: ${settings.workingDir}`
    );
  } else {
    ctx.reply(
      `No active session. Send a message to start one.\n` +
      `📂 Working dir: ${settings.workingDir}`
    );
  }
});

bot.command('sessions', async (ctx) => {
  const chatId = ctx.chat.id;
  const settings = getChatSettings(chatId);
  await ctx.sendChatAction('typing');
  try {
    const output = await listSessions(settings.workingDir);

    // Parse session lines to create inline buttons
    const lines = output.split('\n').filter(l => l.trim());
    const buttons = [];
    for (const line of lines) {
      // Try to extract session index from lines like "1. session-id (date)"
      const match = line.match(/^\s*(\d+)\./); 
      if (match) {
        const idx = match[1];
        const label = line.trim().slice(0, 40);
        buttons.push([Markup.button.callback(`📋 ${label}`, `resume_session_${idx}`)]);
      }
    }

    if (buttons.length > 0) {
      await ctx.reply('📋 Available Sessions\n\nTap to resume:', Markup.inlineKeyboard(buttons));
    } else {
      const chunks = splitMessage(`📋 Available Sessions\n\n${output}`);
      for (const chunk of chunks) {
        await ctx.reply(chunk);
      }
    }
  } catch (err) {
    await ctx.reply(`❌ Error listing sessions: ${err.message}`);
  }
});

// Inline session resume handler
bot.action(/^resume_session_(.+)$/, async (ctx) => {
  const chatId = ctx.chat.id;
  const idx = ctx.match[1];
  setSessionResume(chatId, idx);
  await ctx.answerCbQuery(`🔗 Resuming session ${idx}`);
  await ctx.reply(`🔗 Session set to: ${idx}\nYour next message will resume that session.`);
});

bot.command('resume', async (ctx) => {
  const chatId = ctx.chat.id;
  const arg = ctx.message.text.split(/\s+/).slice(1).join(' ').trim();

  if (!arg) {
    return ctx.reply('Usage: /resume <index|latest>\n\nExample: /resume 5 or /resume latest\n\nUse /sessions to see available sessions.');
  }

  setSessionResume(chatId, arg);
  await ctx.reply(`🔗 Session set to: ${arg}\nYour next message will resume that session.`);
});

bot.command('delete_session', async (ctx) => {
  const chatId = ctx.chat.id;
  const settings = getChatSettings(chatId);
  const arg = ctx.message.text.split(/\s+/).slice(1).join(' ').trim();

  if (!arg) {
    return ctx.reply('Usage: /delete_session <index>\n\nUse /sessions to see available sessions.');
  }

  await ctx.sendChatAction('typing');
  try {
    const output = await deleteSession(arg, settings.workingDir);
    await ctx.reply(`🗑️ ${output}`);
  } catch (err) {
    await ctx.reply(`❌ Error deleting session: ${err.message}`);
  }
});

// ─── CLI Management Commands ─────────────────────────────────────────────────

bot.command('extensions', async (ctx) => {
  await ctx.sendChatAction('typing');
  try {
    const output = await listExtensions();
    const chunks = splitMessage(`🧩 Installed Extensions\n\n${output}`);
    for (const chunk of chunks) {
      await ctx.reply(chunk);
    }
  } catch (err) {
    await ctx.reply(`❌ Error listing extensions: ${err.message}`);
  }
});

bot.command('skills', async (ctx) => {
  await ctx.sendChatAction('typing');
  try {
    const output = await listSkills();
    const chunks = splitMessage(`🎯 Available Skills\n\n${output}`);
    for (const chunk of chunks) {
      await ctx.reply(chunk);
    }
  } catch (err) {
    await ctx.reply(`❌ Error listing skills: ${err.message}`);
  }
});

bot.command('mcp', async (ctx) => {
  await ctx.sendChatAction('typing');
  try {
    const output = await listMcpServers();
    const chunks = splitMessage(`🔌 MCP Servers\n\n${output}`);
    for (const chunk of chunks) {
      await ctx.reply(chunk);
    }
  } catch (err) {
    await ctx.reply(`❌ Error listing MCP servers: ${err.message}`);
  }
});

// ─── Settings Commands ───────────────────────────────────────────────────────

bot.command('model', (ctx) => {
  const chatId = ctx.chat.id;
  const arg = ctx.message.text.split(/\s+/).slice(1).join(' ').trim();

  if (!arg) {
    const settings = getChatSettings(chatId);
    return ctx.reply(
      `Current model: ${settings.model || '(default)'}\n\n` +
      `Usage: /model <name>\n` +
      `Example: /model gemini-2.5-flash`
    );
  }

  setChatSetting(chatId, 'model', arg);
  ctx.reply(`🤖 Model set to: ${arg}`);
});

bot.command('mode', (ctx) => {
  const chatId = ctx.chat.id;
  const arg = ctx.message.text.split(/\s+/).slice(1).join(' ').trim();
  const validModes = ['default', 'auto_edit', 'yolo'];

  if (!arg) {
    const settings = getChatSettings(chatId);
    return ctx.reply(
      `Current approval mode: ${settings.approvalMode}\n\n` +
      `Usage: /mode <${validModes.join('|')}>\n\n` +
      `• default — prompt for approval on each action\n` +
      `• auto_edit — auto-approve file edits only\n` +
      `• yolo — auto-approve everything`
    );
  }

  if (!validModes.includes(arg)) {
    return ctx.reply(`❌ Invalid mode: ${arg}\nValid modes: ${validModes.join(', ')}`);
  }

  setChatSetting(chatId, 'approvalMode', arg);
  ctx.reply(`⚙️ Approval mode set to: ${arg}`);
});

bot.command('sandbox', (ctx) => {
  const chatId = ctx.chat.id;
  const settings = getChatSettings(chatId);
  const newValue = !settings.sandbox;
  setChatSetting(chatId, 'sandbox', newValue);
  ctx.reply(`🏖️ Sandbox mode: ${newValue ? 'ON ✅' : 'OFF ❌'}\n\n${newValue ? 'Gemini CLI will run tools in a Docker/Podman container.' : 'Gemini CLI will run tools directly on the host.'}`);
});

bot.command('thinking', (ctx) => {
  const chatId = ctx.chat.id;
  const settings = getChatSettings(chatId);
  const newValue = !settings.thinking;
  setChatSetting(chatId, 'thinking', newValue);
  ctx.reply(
    `🧠 Thinking mode: ${newValue ? 'ON ✅' : 'OFF ❌'}\n\n` +
    (newValue
      ? 'Gemini will use deep reasoning. Responses may take longer but will be more thorough.'
      : 'Gemini will respond normally without extended thinking.')
  );
});

bot.command('workdir', (ctx) => {
  const chatId = ctx.chat.id;
  const arg = ctx.message.text.split(/\s+/).slice(1).join(' ').trim();
  const workspaces = getWorkspaces();

  // No args: show current + saved shortcuts as buttons
  if (!arg) {
    const settings = getChatSettings(chatId);
    const aliases = Object.keys(workspaces);

    if (aliases.length > 0) {
      const buttons = aliases.map(alias => [
        Markup.button.callback(`📂 ${alias}: ${workspaces[alias].split('/').pop()}`, `workdir_switch_${alias}`),
      ]);
      ctx.reply(
        `📂 Current: ${settings.workingDir}\n\n` +
        `Saved workspaces (tap to switch):`,
        Markup.inlineKeyboard(buttons)
      );
    } else {
      ctx.reply(
        `📂 Current: ${settings.workingDir}\n\n` +
        `Usage:\n` +
        `/workdir save <alias> — Save current directory\n` +
        `/workdir /path/to/dir — Switch directly\n` +
        `/workdir remove <alias> — Remove a shortcut`
      );
    }
    return;
  }

  // /workdir save <alias>
  if (arg.startsWith('save ')) {
    const alias = arg.slice(5).trim();
    if (!alias) return ctx.reply('Usage: /workdir save <alias>');
    const settings = getChatSettings(chatId);
    setWorkspace(alias, settings.workingDir);
    return ctx.reply(`💾 Saved "${alias}" → ${settings.workingDir}`);
  }

  // /workdir remove <alias>
  if (arg.startsWith('remove ')) {
    const alias = arg.slice(7).trim();
    if (!alias) return ctx.reply('Usage: /workdir remove <alias>');
    deleteWorkspace(alias);
    return ctx.reply(`🗑️ Removed workspace shortcut "${alias}"`);
  }

  // /workdir <alias> — switch to saved workspace
  if (workspaces[arg]) {
    setChatSetting(chatId, 'workingDir', workspaces[arg]);
    clearSession(chatId);
    return ctx.reply(`📂 Switched to: ${workspaces[arg]}\n\nSession cleared (new directory context).`);
  }

  // /workdir <path> — direct path
  setChatSetting(chatId, 'workingDir', arg);
  clearSession(chatId);
  ctx.reply(`📂 Working directory set to: ${arg}\n\nSession cleared (new directory context).`);
});

// Workspace switch inline button handler
bot.action(/^workdir_switch_(.+)$/, async (ctx) => {
  const chatId = ctx.chat.id;
  const alias = ctx.match[1];
  const workspaces = getWorkspaces();
  const dir = workspaces[alias];
  if (dir) {
    setChatSetting(chatId, 'workingDir', dir);
    clearSession(chatId);
    await ctx.answerCbQuery(`📂 Switched to ${alias}`);
    await ctx.reply(`📂 Switched to: ${dir}\n\nSession cleared.`);
  } else {
    await ctx.answerCbQuery('❌ Workspace not found');
  }
});

// ─── Session Naming Command ──────────────────────────────────────────────────

bot.command('name', (ctx) => {
  const chatId = ctx.chat.id;
  const label = ctx.message.text.split(/\s+/).slice(1).join(' ').trim();

  if (!label) {
    const currentName = getSessionName(chatId);
    return ctx.reply(
      currentName
        ? `📛 Current session name: "${currentName}"\n\nUsage: /name <label> to rename`
        : `No session name set.\n\nUsage: /name <label>\nExample: /name Refactoring Auth`
    );
  }

  setSessionName(chatId, label);
  ctx.reply(`📛 Session named: "${label}"`);
});

bot.command('settings', (ctx) => {
  const chatId = ctx.chat.id;
  const settings = getChatSettings(chatId);
  const sessionId = getSession(chatId);

  ctx.reply(
    `⚙️ Current Settings\n\n` +
    `📂 Working dir: ${settings.workingDir}\n` +
    `🤖 Model: ${settings.model || '(default)'}\n` +
    `🔐 Approval mode: ${settings.approvalMode}\n` +
    `🧠 Thinking: ${settings.thinking ? 'ON' : 'OFF'}\n` +
    `🏖️ Sandbox: ${settings.sandbox ? 'ON' : 'OFF'}\n` +
    `📋 Session: ${sessionId || '(none)'}`
  );
});

// ─── Send Helper ─────────────────────────────────────────────────────────────

/**
 * Try sending a message with HTML formatting. If Telegram rejects it
 * (malformed HTML), fall back to plain text.
 * @param {object} ctx - Telegraf context
 * @param {string} htmlText - HTML-formatted text
 * @param {string|undefined} parseMode - Parse mode ('HTML' or undefined)
 * @param {string} plainText - Plain text fallback
 * @param {boolean} [notify=false] - If true, enable notification sound (#10)
 */
async function sendWithFallback(ctx, htmlText, parseMode, plainText, notify = false) {
  const opts = notify ? {} : { disable_notification: true };

  if (!parseMode) {
    return ctx.reply(htmlText, opts);
  }

  try {
    await ctx.reply(htmlText, { parse_mode: parseMode, ...opts });
  } catch (err) {
    // Telegram rejected the HTML — log it and fall back to plain text
    console.warn(`⚠️ HTML parse failed, falling back to plain text: ${err.message}`);
    await ctx.reply(plainText, opts);
  }
}

// ─── Shared Response Sender ──────────────────────────────────────────────────

const STREAM_UPDATE_INTERVAL_MS = 1500; // debounce interval for editing the streaming message
const MAX_RETRIES = 1; // auto-retry on empty response
const LONG_REQUEST_THRESHOLD_MS = 30000; // requests longer than this trigger a notification sound

/**
 * Send a Gemini prompt with streaming updates.
 * Progressively edits a placeholder message as chunks arrive.
 * @param {object} ctx - Telegraf context
 * @param {string} prompt - The prompt to send
 * @param {number} chatId - Telegram chat ID
 */
async function sendGeminiResponse(ctx, prompt, chatId, retryCount = 0) {
  // Rate limiting (#9)
  const now = Date.now();
  const lastTime = lastRequestTime.get(chatId) || 0;
  if (now - lastTime < RATE_LIMIT_MS && retryCount === 0) {
    await ctx.reply('⏳ Please wait a moment before sending another request.');
    return;
  }
  lastRequestTime.set(chatId, now);

  const requestStartTime = Date.now();
  await ctx.sendChatAction('typing');

  const typingInterval = setInterval(() => {
    ctx.sendChatAction('typing').catch(() => {});
  }, 4000);

  // Send a status message with inline Cancel/Status buttons
  const inlineButtons = Markup.inlineKeyboard([
    Markup.button.callback('⛔ Cancel', 'cancel_prompt'),
    Markup.button.callback('⏱️ Status', 'check_status'),
  ]);

  let statusMsg = null;

  try {
    console.log(`📩 [${ctx.from?.username || ctx.from?.id}] ${prompt.slice(0, 120)}${prompt.length > 120 ? '...' : ''}`);

    statusMsg = await ctx.reply('⏳ Processing…', inlineButtons);

    const result = await executePrompt(prompt, { chatId });

    // Delete status message
    if (statusMsg) {
      ctx.telegram.deleteMessage(chatId, statusMsg.message_id).catch(() => {});
    }

    // Handle empty response with auto-retry (#2)
    if (!result.text || !result.text.trim()) {
      if (retryCount < MAX_RETRIES) {
        console.log(`🔄 Empty response, retrying (attempt ${retryCount + 2})...`);
        clearInterval(typingInterval);
        return sendGeminiResponse(ctx, prompt, chatId, retryCount + 1);
      }
      await ctx.reply('⚠️ Gemini CLI returned an empty response. Try rephrasing or run /new to start a fresh session.');
      return;
    }

    // Append timeout notice if partial (#3)
    let responseText = result.text;
    if (result.timedOut) {
      responseText += '\n\n⏰ _Response timed out — partial output shown above._';
    }

    // Send the final formatted response
    const { text: htmlText, parseMode } = formatResponse(responseText);
    const rawText = responseText;
    const htmlChunks = splitMessage(htmlText);
    const rawChunks = splitMessage(rawText);

    // For long requests (>30s), enable notification sound (#10) + macOS notification (#2)
    const requestElapsed = Date.now() - requestStartTime;
    const notifyUser = requestElapsed > LONG_REQUEST_THRESHOLD_MS || result.timedOut;

    if (notifyUser && process.platform === 'darwin') {
      const preview = (result.text || '').replace(/"/g, '\\"').slice(0, 100);
      execFile('osascript', [
        '-e', `display notification "${preview}" with title "Gemini Bot" subtitle "Response ready" sound name "Glass"`,
      ], () => {}); // fire-and-forget
    }

    for (let i = 0; i < htmlChunks.length; i++) {
      await sendWithFallback(ctx, htmlChunks[i], parseMode, rawChunks[i] || htmlChunks[i], notifyUser);
    }

    if (result.sessionId && !hasSession(chatId)) {
      console.log(`🔗 New session for chat ${chatId}: ${result.sessionId}`);
    }

    // Check for generated images in the response and send them
    const imagePaths = extractImagePaths(result.text || '');
    for (const imgPath of imagePaths) {
      try {
        console.log(`🖼️ Sending image: ${imgPath}`);
        await ctx.sendPhoto({ source: imgPath });
      } catch (imgErr) {
        console.warn(`⚠️ Failed to send image ${imgPath}: ${imgErr.message}`);
      }
    }

    // Send detected code/document files (#6)
    const filePaths = extractFilePaths(result.text || '');
    for (const filePath of filePaths) {
      try {
        console.log(`📎 Sending file: ${filePath}`);
        await ctx.sendDocument({ source: filePath, filename: path.basename(filePath) });
      } catch (fileErr) {
        console.warn(`⚠️ Failed to send file ${filePath}: ${fileErr.message}`);
      }
    }
  } catch (err) {
    // Delete status message on error too
    if (statusMsg) {
      ctx.telegram.deleteMessage(chatId, statusMsg.message_id).catch(() => {});
    }
    console.error(`❌ Error processing message:`, err.message);
    await ctx.reply(`❌ Error: ${err.message.slice(0, 200)}`);
  } finally {
    clearInterval(typingInterval);
  }
}

// ─── Inline Button Handlers ──────────────────────────────────────────────────

bot.action('cancel_prompt', async (ctx) => {
  const chatId = ctx.chat.id;
  const wasRunning = cancelPrompt(chatId);
  await ctx.answerCbQuery(wasRunning ? '⛔ Request cancelled' : 'ℹ️ No request running');
  if (wasRunning) {
    await ctx.reply('⛔ Request cancelled.');
  }
});

bot.action('check_status', async (ctx) => {
  const chatId = ctx.chat.id;
  const info = getRunningInfo(chatId);
  if (info) {
    const elapsed = Math.round((Date.now() - info.startTime) / 1000);
    const mins = Math.floor(elapsed / 60);
    const secs = elapsed % 60;
    await ctx.answerCbQuery(`⏱️ Running for ${mins}m ${secs}s`);
  } else {
    await ctx.answerCbQuery('✅ No request running');
  }
});

// ─── File Download Helper ────────────────────────────────────────────────────

/**
 * Download a file from Telegram's servers to a local temp path.
 * @param {object} ctx - Telegraf context
 * @param {string} fileId - Telegram file ID
 * @param {string} [extension='jpg'] - File extension
 * @returns {Promise<string>} Local file path
 */
async function downloadTelegramFile(ctx, fileId, extension = 'jpg') {
  const fileLink = await ctx.telegram.getFileLink(fileId);
  const fileName = `telegram_${Date.now()}.${extension}`;
  const filePath = path.join(TEMP_DIR, fileName);

  const response = await fetch(fileLink.href);
  const buffer = Buffer.from(await response.arrayBuffer());
  fs.writeFileSync(filePath, buffer);

  console.log(`📥 Downloaded file: ${filePath} (${buffer.length} bytes)`);
  return filePath;
}

// ─── Text Handler ────────────────────────────────────────────────────────

bot.on('text', (ctx) => {
  let prompt = ctx.message.text;

  // Feature #5: If replying to a bot message, include that context
  const reply = ctx.message.reply_to_message;
  if (reply && reply.from?.is_bot && reply.text) {
    const quotedText = reply.text.slice(0, 2000); // limit context size
    prompt = `Previous assistant response:\n"""\n${quotedText}\n"""\n\nUser follow-up:\n${prompt}`;
  }

  // Fire-and-forget to avoid Telegraf handler timeout
  sendGeminiResponse(ctx, prompt, ctx.chat.id).catch((err) => {
    console.error(`❌ Unhandled error in text handler:`, err.message);
  });
});

// ─── Photo Handler ───────────────────────────────────────────────────────────

bot.on('photo', (ctx) => {
  const chatId = ctx.chat.id;
  const caption = ctx.message.caption || 'Describe this image.';

  (async () => {
    try {
      const photos = ctx.message.photo;
      const bestPhoto = photos[photos.length - 1];
      const localPath = await downloadTelegramFile(ctx, bestPhoto.file_id, 'jpg');
      const prompt = `The user sent an image saved at: ${localPath}\n\nPlease use the view_file tool to look at this image, then respond to the user's request:\n\n${caption}`;
      await sendGeminiResponse(ctx, prompt, chatId);
      fs.unlink(localPath, () => {});
    } catch (err) {
      console.error(`❌ Error processing photo:`, err.message);
      ctx.reply(`❌ Error processing photo: ${err.message}`).catch(() => {});
    }
  })();
});

// ─── Document Handler ────────────────────────────────────────────────────────

bot.on('document', (ctx) => {
  const chatId = ctx.chat.id;
  const doc = ctx.message.document;
  const caption = ctx.message.caption || `Review this file: ${doc.file_name}`;

  (async () => {
    try {
      const ext = path.extname(doc.file_name || '').slice(1) || 'bin';
      const localPath = await downloadTelegramFile(ctx, doc.file_id, ext);
      const prompt = `The user sent a file saved at: ${localPath} (original name: ${doc.file_name}, MIME: ${doc.mime_type})\n\nPlease use the view_file tool to look at this file, then respond to the user's request:\n\n${caption}`;
      await sendGeminiResponse(ctx, prompt, chatId);
      fs.unlink(localPath, () => {});
    } catch (err) {
      console.error(`❌ Error processing document:`, err.message);
      ctx.reply(`❌ Error processing document: ${err.message.slice(0, 200)}`).catch(() => {});
    }
  })();
});

// ─── Voice Message Handler ────────────────────────────────────────────────

bot.on('voice', (ctx) => {
  const chatId = ctx.chat.id;

  (async () => {
    try {
      const localPath = await downloadTelegramFile(ctx, ctx.message.voice.file_id, 'oga');
      const prompt = `The user sent a voice message saved at: ${localPath}\n\nPlease use the view_file tool to listen to/transcribe this audio, then respond to what the user said.`;
      await sendGeminiResponse(ctx, prompt, chatId);
      fs.unlink(localPath, () => {});
    } catch (err) {
      console.error(`❌ Error processing voice:`, err.message);
      ctx.reply(`❌ Error processing voice message: ${err.message.slice(0, 200)}`).catch(() => {});
    }
  })();
});

// ─── Error Handling ──────────────────────────────────────────────────────────

bot.catch((err, ctx) => {
  console.error(`❌ Bot error for ${ctx.updateType}:`, err.message);
});

// ─── Launch ──────────────────────────────────────────────────────────────────

const BOT_COMMANDS = [
  { command: 'help', description: 'Show all available commands' },
  { command: 'cancel', description: 'Cancel the current running request' },
  { command: 'status', description: 'Check if a request is running' },
  { command: 'new', description: 'Start a fresh session (clears context)' },
  { command: 'session', description: 'Show current session info' },
  { command: 'sessions', description: 'Browse and resume sessions' },
  { command: 'name', description: 'Name current session (e.g. /name Auth Fix)' },
  { command: 'resume', description: 'Resume a session by index' },
  { command: 'delete_session', description: 'Delete a session by index' },
  { command: 'extensions', description: 'List installed Gemini CLI extensions' },
  { command: 'skills', description: 'List available agent skills' },
  { command: 'mcp', description: 'List configured MCP servers' },
  { command: 'model', description: 'Set or show the Gemini model' },
  { command: 'mode', description: 'Set approval mode (default|auto_edit|yolo)' },
  { command: 'thinking', description: 'Toggle thinking mode (deep reasoning)' },
  { command: 'sandbox', description: 'Toggle sandbox mode (Docker/Podman)' },
  { command: 'workdir', description: 'Manage workspace shortcuts' },
  { command: 'settings', description: 'Show all current settings' },
];

console.log('🚀 Starting Gemini CLI Telegram Bot...');
console.log(`📂 Working directory: ${WORKING_DIR}`);
console.log(`🔒 Allowed users: ${ALLOWED_USER_IDS.length > 0 ? ALLOWED_USER_IDS.join(', ') : 'ALL (no whitelist set!)'}`);

(async () => {
  try {
    await bot.launch();
    console.log('✅ Bot is running!');

    // Register command menu with Telegram (shows when user types /)
    try {
      await bot.telegram.setMyCommands(BOT_COMMANDS);
      console.log(`📋 Registered ${BOT_COMMANDS.length} commands with Telegram.`);

      // Verify commands were set
      const registered = await bot.telegram.getMyCommands();
      console.log(`📋 Telegram reports ${registered.length} commands registered.`);
    } catch (cmdErr) {
      console.error('⚠️ Failed to register commands:', cmdErr.message);
    }
  } catch (err) {
    console.error('❌ Failed to launch bot:', err.message);
    process.exit(1);
  }
})();

// Graceful shutdown
process.once('SIGINT', () => bot.stop('SIGINT'));
process.once('SIGTERM', () => bot.stop('SIGTERM'));

