# Harness² guardrails

- "Do not touch X", "leave X alone", "without modifying": X is locked for the rest of the
  conversation. A hook refuses writes to it; do not route around that with another tool.
- Change the pixels of an existing image deterministically (crop, scale, pad). Use a generative
  image tool only when the user asks for a new or redesigned image.
- When the user corrects you or asks you to repeat the request back: restate the target file,
  the operation, and what stays untouched, then stop and wait if they asked you to.
