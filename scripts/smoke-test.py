#!/usr/bin/env python3
"""Exercise discovery and graceful stopping against a real, isolated server."""
import json
import pathlib
import socket
import subprocess
import sys
import tempfile

binary = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="quick-port test ") as folder:
    root = pathlib.Path(folder)
    (root / "package.json").write_text('{"name":"quick-port-smoke"}')
    # Bind port zero in the child so another process cannot steal a reserved port.
    server = subprocess.Popen(
        [sys.executable, "-u", "-c", "import http.server; s=http.server.HTTPServer(('127.0.0.1',0), http.server.SimpleHTTPRequestHandler); print(s.server_port,flush=True); s.serve_forever()"],
        cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        port = int(server.stdout.readline().strip())
        result = json.loads(subprocess.check_output([binary, "--json"]))
        match = next(row for row in result if row["pid"] == server.pid and row["port"] == port)
        assert pathlib.Path(match["project"]).resolve() == root.resolve(), match
        assert match["owned"] and match["development"], match
        assert match["url"] == f"http://localhost:{port}", match
        assert match["started_at"], match
        stale = subprocess.run([binary, "stop", "--pid", str(server.pid), "--started-at", "stale identity"], capture_output=True, text=True)
        assert stale.returncode != 0, "Stale process identity was accepted"
        assert server.poll() is None, "Rejected stop terminated the process"
        with socket.create_connection(("127.0.0.1", port), timeout=2):
            pass
        subprocess.run([binary, "stop", "--pid", str(server.pid), "--started-at", match["started_at"]], check=True)
        server.wait(timeout=5)
        result = json.loads(subprocess.check_output([binary, "--json"]))
        assert not any(row["pid"] == server.pid for row in result), "Stopped server still listed"
        print("PASS: live discovery, project path with spaces, ownership, stale identity rejection, graceful stop, and removal")
    finally:
        if server.poll() is None:
            server.terminate()
            server.wait(timeout=5)
