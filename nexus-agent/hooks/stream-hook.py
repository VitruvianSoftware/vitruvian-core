#!/usr/bin/env python3
"""Gemini CLI Hook: Stream events to a JSONL file for live UI updates.

Reads hook event JSON from stdin, extracts relevant data, and appends
a JSON line to the stream file specified by GEMINI_STREAM_FILE env var.

If GEMINI_STREAM_FILE is not set, the hook is a no-op (pass-through).

TODO_GEMINI_HOOKS: This hook requires Gemini CLI hooks support (AfterModel,
BeforeTool, AfterTool, AfterAgent), which is NOT available in gemini v0.35.1.
Hooks exist only in the upstream main branch. Check for a new release and
verify by running: GEMINI_STREAM_FILE=/tmp/test.jsonl gemini -p "say hi"
See also: macos/Sources/GeminiBotBar/QuickPromptWindow.swift and TODO.md
"""

import json
import os
import sys


def main():
    stream_file = os.environ.get("GEMINI_STREAM_FILE", "")
    if not stream_file:
        # No stream file configured — pass through
        print("{}")
        return

    try:
        raw = sys.stdin.read()
        data = json.loads(raw) if raw.strip() else {}
    except (json.JSONDecodeError, Exception):
        print("{}")
        return

    hook_event = data.get("hook_event", data.get("hookEvent", ""))

    try:
        if hook_event == "AfterModel":
            handle_after_model(data, stream_file)
        elif hook_event == "BeforeTool":
            handle_before_tool(data, stream_file)
        elif hook_event == "AfterTool":
            handle_after_tool(data, stream_file)
        elif hook_event == "AfterAgent":
            handle_after_agent(data, stream_file)
    except Exception as e:
        # Log errors to stderr (visible in gemini logs, not parsed as output)
        print(f"stream-hook error: {e}", file=sys.stderr)

    # Always output empty JSON (allow/pass-through)
    print("{}")


def write_event(stream_file: str, event: dict):
    """Append a JSON event line to the stream file."""
    with open(stream_file, "a") as f:
        f.write(json.dumps(event, ensure_ascii=False) + "\n")
        f.flush()


def handle_after_model(data: dict, stream_file: str):
    """Extract text chunks from model response and write to stream."""
    resp = data.get("llm_response", data.get("llmResponse", {}))
    candidates = resp.get("candidates", [])

    for candidate in candidates:
        content = candidate.get("content", {})
        parts = content.get("parts", [])
        for part in parts:
            is_thought = part.get("thought", False)
            text = part.get("text", "")
            if not text:
                continue

            if is_thought:
                write_event(stream_file, {"type": "thinking", "text": text})
            else:
                write_event(stream_file, {"type": "chunk", "text": text})


def handle_before_tool(data: dict, stream_file: str):
    """Write tool start event."""
    tool = data.get("tool_name", data.get("toolName", "unknown"))
    tool_input = data.get("tool_input", data.get("toolInput", {}))
    # Include a brief summary of what the tool is doing
    summary = ""
    if isinstance(tool_input, dict):
        # For shell commands, show the command
        if "command" in tool_input:
            summary = str(tool_input["command"])[:100]
        elif "file_path" in tool_input:
            summary = str(tool_input["file_path"])
    write_event(stream_file, {"type": "tool_start", "tool": tool, "summary": summary})


def handle_after_tool(data: dict, stream_file: str):
    """Write tool completion event."""
    tool = data.get("tool_name", data.get("toolName", "unknown"))
    write_event(stream_file, {"type": "tool_done", "tool": tool})


def handle_after_agent(data: dict, stream_file: str):
    """Write agent completion event with full response."""
    response = data.get("prompt_response", data.get("promptResponse", ""))
    write_event(stream_file, {"type": "done", "response": response})


if __name__ == "__main__":
    main()
