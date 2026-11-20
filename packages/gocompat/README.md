# vitruvian-gocompat

## What it gives you

`goexec` reproduces Go's `os/exec` and `path/filepath.Clean` behaviour for Rust ports of Go tools: `exec.LookPath`'s `PATH` walk (including `ErrDot` refusal of relative hits), launching processes with `execve(2)` without Rust's `execvp` `/bin/sh` fallback, and Go's exact `*exec.Error`, `*fs.PathError`, and syscall error text.

## When to use it

Use `vitruvian_gocompat` in Rust ports of Go CLI or automation tools that must resolve binaries, enforce `ErrDot`, and emit `os/exec` or syscall error messages byte-for-byte identically to the Go program they replaced.

## When not to use it

Do not use this package in new Rust code that does not require Go `os/exec` parity; use `std::process::Command` directly instead.

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

## Depend on it

Add `//packages/gocompat:vitruvian_gocompat` to your target's `deps` in `BUILD`, and import or re-export the module:

```rust
pub use vitruvian_gocompat::goexec;
```

## Constraints

- Rust standard library only (`std` only, zero third-party crates), so any tool can link it regardless of crate hub.
- Unix-only (`std::os::unix`, `faccessat`, `execve`).
