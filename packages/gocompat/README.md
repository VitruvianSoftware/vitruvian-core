# vitruvian-gocompat

## What it gives you

- `goexec` reproduces Go's `os/exec` and `path/filepath.Clean` behaviour for Rust ports of Go tools: `exec.LookPath`'s `PATH` walk (including `ErrDot` refusal of relative hits), launching processes with `execve(2)` without Rust's `execvp` `/bin/sh` fallback, and Go's exact `*exec.Error`, `*fs.PathError`, and syscall error text.
- `gostd` provides the shared Go standard-library helpers used across ported tools: `decode_rune` (`utf8.DecodeRune` returning `(Option<char>, usize)` with per-byte invalid-sequence handling), Unix `clean` and `join` (`filepath.Clean`/`Join`), `errno_text` (`syscall.Errno.Error()`), and `path_error` (`*os.PathError`). When an error message contains `" (os error "` more than once, `errno_text` strips from the last occurrence (`rfind`), matching `delivery/gen` and `delivery/orchestrate` rather than `actionpins`'s earlier first-match (`find`) behaviour.
- `unicode` provides Go 1.26.6's `unicode.ToUpper` single-rune uppercase mapping (`TO_UPPER`, `to_upper`), where one rune always maps to one rune.

## When to use it

Use `vitruvian_gocompat` in Rust ports of Go CLI or automation tools that must resolve binaries, enforce `ErrDot`, clean/join Unix paths, decode UTF-8 runes byte-by-byte like Go, map rune case like `unicode.ToUpper`, or emit `os/exec` and syscall error messages byte-for-byte identically to the Go program they replaced.

## When not to use it

Do not use this package in new Rust code that does not require Go standard-library parity; use `std::process::Command`, `std::path::Path`, `std::str::from_utf8`, and `char::to_uppercase` directly instead.

## Example

From `tools/copybara/sync`:

```rust
use vitruvian_gocompat::goexec;

let mut cmd = goexec::command(b"docker", &args).map_err(|e| e.go_string())?;
let status = cmd.status();
if let Err(e) = status {
    let path = goexec::look_path(b"docker").unwrap_or_else(|_| b"docker".to_vec());
    return Err(goexec::ExecError::Start {
        path,
        errno: e.raw_os_error().unwrap_or(0),
    }
    .go_string());
}
```

From `tools/delivery/orchestrate`:

```rust
pub use vitruvian_gocompat::gostd::{clean, errno_text, join, path_error};

let out_path = join(&[&dir, "github_output"]);
std::fs::write(&out_path, data).map_err(|e| path_error("write", &out_path, &e))?;
```

## Depend on it

Add `//packages/gocompat:vitruvian_gocompat` to your target's `deps` in `BUILD`, and import or re-export the modules:

```rust
pub use vitruvian_gocompat::{goexec, gostd, unicode};
```

## Constraints

- Rust standard library only (`std` only, zero third-party crates), so any tool can link it regardless of crate hub.
- Unix-only crate: `goexec` unconditionally uses `std::os::unix` (`faccessat`, `execve`), and `gostd`'s `clean` and `join` depend on `goexec::clean`.
