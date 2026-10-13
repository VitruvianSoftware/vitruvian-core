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

// @vitruviansoftware/tool-kit: write a tool for the Vitruvian app. See README.md.

export * from "./generated/messages.js";
export * from "./generated/manifest.js";
export {
  type AppCalls,
  METHODS,
  type MethodInfo,
  PROTOCOL_VERSION,
} from "./generated/methods.js";
export {
  type App,
  AppUnreachable,
  CommandRefused,
  type Handler,
  Refusal,
  RefusalCode,
  RPCErrorCode,
  Tool,
  type ToolOptions,
} from "./tool.js";
export {
  lineOf,
  MAX_LINE_BYTES,
  messageOf,
  type RPCID,
  type RPCMessage,
} from "./wire.js";
