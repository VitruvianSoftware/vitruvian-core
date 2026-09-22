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

// Files: the object Slack lets a caller name without naming a channel.
//
// A file ID reaches files.info with nothing for the parameter guard to check,
// so every method here has to make its allow-list decision on the answer —
// the conversations Slack says the file is shared into — and has to make it
// *before* any bytes move. The tests below assert the ordering as much as the
// verdict: a refused file produces no download request, not a download that
// is then discarded.

import {
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
  existsSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { SlackClient } from "../src/slackClient.js";
import {
  ChannelNotAllowedError,
  FileNotAllowedError,
} from "../src/channelAllowlist.js";
import { resolveConfig } from "../src/config.js";
import { HTTP_WITHHELD_ALWAYS, toolsFor } from "../src/tools.js";

const STDIO_ENV = {
  SLACK_BOT_TOKEN: "xoxb-test",
  SLACK_USER_TOKEN: "xoxp-test",
  SLACK_TEAM_ID: "T123",
};

const HTTP_ENV = {
  MCP_TRANSPORT: "http",
  SLACK_BOT_TOKEN: "xoxb-test",
  SLACK_TEAM_ID: "T123",
  SLACK_CHANNEL_IDS: "C0ALLOWED1",
  OIDC_ISSUER: "https://auth.example.test",
  OIDC_PROJECT_ID: "999",
  OIDC_ALLOWED_SUBJECTS: "379361013981513322",
  OIDC_ALLOWED_CLIENT_ID: "111222333",
};

function clientFor(env: Record<string, string | undefined>) {
  const config = resolveConfig(env);
  return new SlackClient(config.slack, {
    channelGuard: config.channelGuard,
    writeToken: config.writeToken,
  });
}

const PRIVATE_URL =
  "https://files.slack.com/files-pri/T123-F0TEXT0001/notes.txt";

function fileInfo(overrides: Record<string, unknown> = {}) {
  return {
    id: "F0TEXT0001",
    name: "notes.txt",
    title: "notes",
    mimetype: "text/plain",
    filetype: "text",
    size: 11,
    url_private: PRIVATE_URL,
    channels: ["C0ALLOWED1"],
    groups: [],
    ims: [],
    ...overrides,
  };
}

type Call = {
  url: string;
  method: string;
  auth: string | undefined;
  body?: string | Uint8Array;
};

/**
 * Routes by URL: Slack Web API calls get JSON, the private file URL gets
 * bytes, the upload URL accepts anything. Recording the body as bytes for the
 * upload leg is what lets the test check the payload actually sent.
 */
function routeFetch(routes: {
  info?: Record<string, unknown>;
  bytes?: string;
  uploadUrl?: Record<string, unknown>;
  complete?: Record<string, unknown>;
}) {
  const calls: Call[] = [];
  const spy = jest
    .spyOn(globalThis, "fetch")
    .mockImplementation(
      async (input: RequestInfo | URL, init?: RequestInit) => {
        const url = String(input);
        const headers = (init?.headers ?? {}) as Record<string, string>;
        let body: string | Uint8Array | undefined;
        if (typeof init?.body === "string") body = init.body;
        else if (init?.body instanceof Uint8Array) body = init.body;
        calls.push({
          url,
          method: init?.method ?? "GET",
          auth: headers.Authorization,
          body,
        });

        const json = (payload: unknown) =>
          new Response(JSON.stringify(payload), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          });
        if (url.includes("/api/files.info")) {
          return json({ ok: true, file: routes.info ?? fileInfo() });
        }
        if (url.includes("/api/files.getUploadURLExternal")) {
          return json(
            routes.uploadUrl ?? {
              ok: true,
              upload_url: "https://files.slack.com/upload/v1/abc",
              file_id: "F0NEW00001",
            },
          );
        }
        if (url.includes("/api/files.completeUploadExternal")) {
          return json(
            routes.complete ?? { ok: true, files: [{ id: "F0NEW00001" }] },
          );
        }
        if (url.startsWith("https://files.slack.com/upload/")) {
          return new Response("OK", { status: 200 });
        }
        if (url === PRIVATE_URL) {
          return new Response(routes.bytes ?? "hello world", {
            status: 200,
            headers: { "Content-Type": "text/plain" },
          });
        }
        return json({ ok: false, error: "unrouted_in_test" });
      },
    );
  return { calls, restore: () => spy.mockRestore() };
}

describe("getFileInfo", () => {
  let capture: ReturnType<typeof routeFetch>;
  afterEach(() => capture.restore());

  it("returns the file when it is shared into an allow-listed channel", async () => {
    capture = routeFetch({});
    const result = (await clientFor(HTTP_ENV).getFileInfo("F0TEXT0001")) as {
      ok: boolean;
      file: { id: string };
    };
    expect(result.ok).toBe(true);
    expect(result.file.id).toBe("F0TEXT0001");
    expect(capture.calls[0]!.url).toContain("files.info");
    expect(capture.calls[0]!.url).toContain("file=F0TEXT0001");
    expect(capture.calls[0]!.auth).toBe("Bearer xoxb-test");
  });

  it("refuses a file shared only into channels outside the allow-list", async () => {
    capture = routeFetch({ info: fileInfo({ channels: ["C0OTHER00"] }) });
    await expect(
      clientFor(HTTP_ENV).getFileInfo("F0TEXT0001"),
    ).rejects.toBeInstanceOf(FileNotAllowedError);
  });

  it("does not leak the private download URL in the refusal", async () => {
    capture = routeFetch({ info: fileInfo({ channels: ["C0OTHER00"] }) });
    await expect(
      clientFor(HTTP_ENV).getFileInfo("F0TEXT0001"),
    ).rejects.not.toThrow(/files-pri/);
  });

  it("imposes no restriction on stdio without an allow-list", async () => {
    capture = routeFetch({ info: fileInfo({ channels: [] }) });
    await expect(
      clientFor(STDIO_ENV).getFileInfo("F0TEXT0001"),
    ).resolves.toMatchObject({ ok: true });
  });
});

describe("readFile", () => {
  let capture: ReturnType<typeof routeFetch>;
  afterEach(() => capture.restore());

  it("downloads the bytes with the bot token and returns them as text", async () => {
    capture = routeFetch({});
    const result = (await clientFor(HTTP_ENV).readFile("F0TEXT0001")) as {
      ok: boolean;
      content: string;
      mimetype: string;
      name: string;
    };
    expect(result).toMatchObject({
      ok: true,
      name: "notes.txt",
      mimetype: "text/plain",
      content: "hello world",
    });
    expect(capture.calls).toHaveLength(2);
    expect(capture.calls[1]!.url).toBe(PRIVATE_URL);
    expect(capture.calls[1]!.auth).toBe("Bearer xoxb-test");
  });

  it("never fetches the bytes of a file outside the allow-list", async () => {
    capture = routeFetch({ info: fileInfo({ channels: ["C0OTHER00"] }) });
    await expect(
      clientFor(HTTP_ENV).readFile("F0TEXT0001"),
    ).rejects.toBeInstanceOf(FileNotAllowedError);
    expect(capture.calls).toHaveLength(1);
    expect(capture.calls[0]!.url).toContain("files.info");
  });

  it("refuses a binary file rather than returning garbage", async () => {
    capture = routeFetch({
      info: fileInfo({ mimetype: "image/png", filetype: "png", name: "a.png" }),
    });
    await expect(clientFor(HTTP_ENV).readFile("F0TEXT0001")).rejects.toThrow(
      /not a text file/,
    );
    expect(capture.calls).toHaveLength(1);
  });

  it("refuses a file larger than the cap before downloading it", async () => {
    capture = routeFetch({ info: fileInfo({ size: 2_000_000 }) });
    await expect(
      clientFor(HTTP_ENV).readFile("F0TEXT0001", 1_000_000),
    ).rejects.toThrow(/larger than/);
    expect(capture.calls).toHaveLength(1);
  });

  it("does not include the private URL in what it returns", async () => {
    capture = routeFetch({});
    const result = await clientFor(HTTP_ENV).readFile("F0TEXT0001");
    expect(JSON.stringify(result)).not.toContain("files-pri");
  });
});

describe("uploadFile", () => {
  let capture: ReturnType<typeof routeFetch>;
  afterEach(() => capture.restore());

  it("runs the three-step external upload and shares into the channel", async () => {
    capture = routeFetch({});
    const result = await clientFor(STDIO_ENV).uploadFile({
      channelId: "C0ALLOWED1",
      filename: "hello.txt",
      content: "hello",
      title: "Hello",
      initialComment: "here you go",
      threadTs: "1.000001",
    });
    expect(result).toMatchObject({ ok: true });
    expect(capture.calls).toHaveLength(3);

    const [getUrl, put, complete] = capture.calls;
    expect(getUrl!.url).toContain("files.getUploadURLExternal");
    expect(getUrl!.url).toContain("filename=hello.txt");
    expect(getUrl!.url).toContain("length=5");
    expect(getUrl!.auth).toBe("Bearer xoxp-test"); // writes as the user on stdio

    expect(put!.url).toBe("https://files.slack.com/upload/v1/abc");
    expect(put!.method).toBe("POST");
    expect(Buffer.from(put!.body as Uint8Array).toString()).toBe("hello");

    expect(complete!.url).toContain("files.completeUploadExternal");
    expect(JSON.parse(complete!.body as string)).toEqual({
      files: [{ id: "F0NEW00001", title: "Hello" }],
      channel_id: "C0ALLOWED1",
      initial_comment: "here you go",
      thread_ts: "1.000001",
    });
  });

  it("decodes base64 content", async () => {
    capture = routeFetch({});
    await clientFor(STDIO_ENV).uploadFile({
      channelId: "C0ALLOWED1",
      filename: "b.bin",
      contentBase64: Buffer.from([1, 2, 3]).toString("base64"),
    });
    expect(Buffer.from(capture.calls[1]!.body as Uint8Array)).toEqual(
      Buffer.from([1, 2, 3]),
    );
    expect(capture.calls[0]!.url).toContain("length=3");
  });

  it("refuses a channel outside the allow-list before requesting an upload URL", async () => {
    capture = routeFetch({});
    await expect(
      clientFor(HTTP_ENV).uploadFile({
        channelId: "G0PRIVATE1",
        filename: "x.txt",
        content: "x",
      }),
    ).rejects.toBeInstanceOf(ChannelNotAllowedError);
    expect(capture.calls).toHaveLength(0);
  });

  it("uses the bot token for writes on bot-only HTTP", async () => {
    capture = routeFetch({});
    await clientFor(HTTP_ENV).uploadFile({
      channelId: "C0ALLOWED1",
      filename: "x.txt",
      content: "x",
    });
    expect(capture.calls[0]!.auth).toBe("Bearer xoxb-test");
    expect(capture.calls[2]!.auth).toBe("Bearer xoxb-test");
  });

  it("requires exactly one of content and content_base64", async () => {
    capture = routeFetch({});
    const client = clientFor(STDIO_ENV);
    await expect(
      client.uploadFile({ channelId: "C0ALLOWED1", filename: "x" }),
    ).rejects.toThrow(/content/);
    await expect(
      client.uploadFile({
        channelId: "C0ALLOWED1",
        filename: "x",
        content: "a",
        contentBase64: "YQ==",
      }),
    ).rejects.toThrow(/content/);
    expect(capture.calls).toHaveLength(0);
  });
});

describe("downloadFile", () => {
  let capture: ReturnType<typeof routeFetch>;
  let dir: string;
  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "mcp-slack-dl-"));
  });
  afterEach(() => {
    capture.restore();
    rmSync(dir, { recursive: true, force: true });
  });

  it("writes the bytes to the requested path", async () => {
    capture = routeFetch({});
    const target = join(dir, "out.txt");
    const result = await clientFor(STDIO_ENV).downloadFile(
      "F0TEXT0001",
      target,
    );
    expect(result).toEqual({
      ok: true,
      path: target,
      bytes: 11,
      name: "notes.txt",
    });
    expect(readFileSync(target, "utf8")).toBe("hello world");
  });

  it("refuses to overwrite an existing file", async () => {
    capture = routeFetch({});
    const target = join(dir, "exists.txt");
    writeFileSync(target, "keep me");
    await expect(
      clientFor(STDIO_ENV).downloadFile("F0TEXT0001", target),
    ).rejects.toThrow(/already exists/);
    expect(readFileSync(target, "utf8")).toBe("keep me");
  });

  it("does not download a file outside the allow-list", async () => {
    capture = routeFetch({ info: fileInfo({ channels: ["C0OTHER00"] }) });
    const target = join(dir, "no.txt");
    await expect(
      clientFor({ ...STDIO_ENV, SLACK_CHANNEL_IDS: "C0ALLOWED1" }).downloadFile(
        "F0TEXT0001",
        target,
      ),
    ).rejects.toBeInstanceOf(FileNotAllowedError);
    expect(capture.calls).toHaveLength(1);
    expect(existsSync(target)).toBe(false);
  });
});

describe("file tools per transport", () => {
  it("never advertises slack_download_file on HTTP, even with a user token", () => {
    expect(HTTP_WITHHELD_ALWAYS.has("slack_download_file")).toBe(true);
    const withUser = toolsFor(
      resolveConfig({ ...HTTP_ENV, SLACK_USER_TOKEN: "xoxp-test" }),
    ).map((t) => t.name);
    expect(withUser).not.toContain("slack_download_file");
    const botOnly = toolsFor(resolveConfig(HTTP_ENV)).map((t) => t.name);
    expect(botOnly).not.toContain("slack_download_file");
  });

  it("advertises slack_download_file on stdio", () => {
    const advertised = toolsFor(resolveConfig(STDIO_ENV)).map((t) => t.name);
    expect(advertised).toContain("slack_download_file");
  });

  it("advertises info, read and upload on bot-only HTTP", () => {
    const advertised = toolsFor(resolveConfig(HTTP_ENV)).map((t) => t.name);
    expect(advertised).toEqual(
      expect.arrayContaining([
        "slack_get_file_info",
        "slack_read_file",
        "slack_upload_file",
      ]),
    );
  });
});
