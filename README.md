<div align="center">
  <h1>quick-port</h1>

  <p><strong>See and manage your local development servers</strong></p>

  <p>
    <img alt="License" src="https://img.shields.io/badge/license-MIT-green">
    <img alt="Rust" src="https://img.shields.io/badge/rust-1.85%2B-orange">
    <img alt="Edition" src="https://img.shields.io/badge/edition-2024-blue">
  </p>

  <p>
    <a href="#install">Install</a>
    &nbsp;·&nbsp;
    <a href="#quickstart">Quickstart</a>
    &nbsp;·&nbsp;
    <a href="#development">Development</a>
  </p>
</div>

---

A native macOS menu bar app for the servers running on your machine. See listening TCP ports, their processes and project folders without hunting through Activity Monitor.

- Search by port, process, PID, command or project.
- Switch between development servers and all visible TCP listeners.
- Open a local URL, copy it, or open the project folder in Finder.
- Send a graceful stop after confirming the process. Ownership and process start time are checked again before stopping; every port belonging to that process closes.
- Refreshes every three seconds while the panel is open; no background polling when closed.

SwiftUI/AppKit interface with a Rust discovery helper. No third-party UI dependencies, accounts or network services.

## Install

Requires macOS 14+, Xcode Command Line Tools, Rust 1.85+ and Python 3 for packaging.

```bash
make install-app
open "/Applications/Quick Port.app"
```

Click the network icon in the menu bar. The number beside it shows detected development ports. Quick Port has no Dock icon.

## Quickstart

Start a server in a project folder, then open Quick Port:

```bash
python3 -m http.server 8000
```

Use the arrow to open its HTTP URL, or the row's action menu to copy details, open its folder or stop its process. “All listeners” includes databases, emulators and other TCP services; their HTTP URL may not serve a web page.

Development detection uses project markers (`.git`, `package.json`, `Cargo.toml`, `pyproject.toml`, and others) and known runtime names. It is a convenience filter; all visible listeners remain available in the other tab. Project paths come from the process's working directory and may be unavailable for protected processes. IPv4/IPv6 listeners belonging to the same process and port appear once. UDP sockets are excluded.

A stop sends SIGTERM to one process, with no automatic escalation or process-tree termination. A supervisor may restart it. Processes owned by another user cannot be stopped here.

## CLI

The Rust helper also works on its own on macOS:

```bash
cargo run --                 # Port / PID / process / project table
cargo run -- --json          # Full discovery data
cargo run -- --help
```

## Development

```bash
make app                    # Build dist/Quick Port.app
make run-app                # Build and launch
make install-app            # Build and copy to /Applications
cargo test
make test-ui                # Native popover sizing regression
cargo fmt -- --check
cargo clippy --all-targets -- -D warnings
python3 scripts/smoke-test.py "dist/Quick Port.app/Contents/Helpers/quick-port"
```

The smoke test starts its own temporary HTTP server, verifies discovery and project resolution, rejects a stale process identity, then verifies a graceful stop and removal from the list. It does not stop existing servers.

For UI inspection, launch the bundled executable with `--preview-window` or `--show` to open the menu bar panel immediately.

`RUST_TARGET=x86_64-apple-darwin make app` builds the Intel variant after installing that Rust target. The default uses the host architecture. Local bundles are ad-hoc signed; distribution notarization requires an Apple Developer signing identity.

## License

MIT
