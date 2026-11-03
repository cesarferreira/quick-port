use anyhow::Result;
use serde::Serialize;
#[derive(Debug, Clone, Serialize)]
pub struct Server {
    pub pid: u32,
    pub port: u16,
    pub process: String,
    pub address: String,
    pub url: String,
    pub cwd: Option<String>,
    pub project: Option<String>,
    pub command: String,
    pub started_at: String,
    pub owned: bool,
    pub development: bool,
}
pub fn scan() -> Result<Vec<Server>> {
    let uid = current_uid()?;
    let mut listeners = parse_listeners(&lsof(&["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcun"])?);
    if listeners.is_empty() {
        return Ok(listeners);
    }
    let processes = parse_processes(&run(
        "/bin/ps",
        &["-ww", "-axo", "pid=,uid=,lstart=,command="],
    )?);
    let pids = listeners
        .iter()
        .map(|s| s.pid.to_string())
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>()
        .join(",");
    let cwds = parse_cwds(&lsof(&["-a", "-p", &pids, "-d", "cwd", "-Fn"])?);
    for server in &mut listeners {
        if let Some((_, owner, start, command)) = processes.iter().find(|p| p.0 == server.pid) {
            server.owned = *owner == uid;
            server.started_at = start.clone();
            server.command = command.clone();
        }
        server.cwd = cwds.iter().find(|p| p.0 == server.pid).map(|p| p.1.clone());
        server.project = server.cwd.as_deref().and_then(project_root);
        let runtime = server.process.to_lowercase();
        server.development = server.owned
            && (server.project.is_some()
                || [
                    "node",
                    "bun",
                    "deno",
                    "python",
                    "ruby",
                    "php",
                    "java",
                    "uvicorn",
                    "gunicorn",
                    "vite",
                    "next-server",
                    "cargo",
                    "go",
                    "docker",
                    "com.docker",
                    "postgres",
                    "redis-server",
                ]
                .iter()
                .any(|name| runtime.starts_with(name)));
    }
    listeners.sort_by_key(|s| (s.port, s.pid));
    Ok(listeners)
}

pub fn stop(pid: u32, started_at: &str) -> Result<()> {
    let uid = current_uid()?;
    let rows = parse_processes(&run(
        "/bin/ps",
        &[
            "-ww",
            "-p",
            &pid.to_string(),
            "-o",
            "pid=,uid=,lstart=,command=",
        ],
    )?);
    let (_, owner, actual, _) = rows
        .first()
        .ok_or_else(|| anyhow::anyhow!("Process has already exited"))?;
    anyhow::ensure!(
        can_stop(pid, *owner, uid, started_at, actual),
        "Process identity changed or this process is not owned by you; refresh the list"
    );
    let listeners = parse_listeners(&lsof(&[
        "-nP",
        "-a",
        "-p",
        &pid.to_string(),
        "-iTCP",
        "-sTCP:LISTEN",
        "-Fpcun",
    ])?);
    anyhow::ensure!(
        listeners.iter().any(|s| s.pid == pid),
        "Process is no longer listening; refresh the list"
    );
    run("/bin/kill", &["-TERM", &pid.to_string()])?;
    Ok(())
}

fn run(program: &str, args: &[&str]) -> Result<String> {
    use anyhow::Context;
    let output = std::process::Command::new(program)
        .args(args)
        .env("LC_ALL", "C")
        .output()
        .with_context(|| format!("Unable to run {program}"))?;
    anyhow::ensure!(
        output.status.success(),
        "{program}: {}",
        String::from_utf8_lossy(&output.stderr).trim()
    );
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn lsof(args: &[&str]) -> Result<String> {
    use anyhow::Context;
    let output = std::process::Command::new("/usr/sbin/lsof")
        .args(args)
        .env("LC_ALL", "C")
        .output()
        .context("Unable to inspect TCP listeners")?;
    // lsof exits 1 when no matching files exist, including when a server exits mid-scan.
    anyhow::ensure!(
        output.status.success() || (output.status.code() == Some(1) && output.stderr.is_empty()),
        "lsof: {}",
        String::from_utf8_lossy(&output.stderr).trim()
    );
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn current_uid() -> Result<u32> {
    Ok(run("/usr/bin/id", &["-u"])?.trim().parse()?)
}

fn parse_listeners(input: &str) -> Vec<Server> {
    let mut rows = Vec::new();
    let mut pid = None;
    let mut process = String::new();
    let mut seen = std::collections::HashSet::new();
    for line in input.lines().filter(|line| !line.is_empty()) {
        let (kind, value) = line.split_at(1);
        match kind {
            "p" => {
                pid = value.parse::<u32>().ok();
                process.clear();
            }
            "c" => process = value.to_string(),
            "n" => {
                let Some(pid) = pid else { continue };
                let Some((host, port)) = value.rsplit_once(':') else {
                    continue;
                };
                let Ok(port) = port.parse::<u16>() else {
                    continue;
                };
                if port == 0 || !seen.insert((pid, port)) {
                    continue;
                }
                let local_host = match host {
                    "*" | "0.0.0.0" | "[::]" | "127.0.0.1" | "[::1]" => "localhost",
                    other => other,
                };
                rows.push(Server {
                    pid,
                    port,
                    process: process.clone(),
                    address: value.into(),
                    url: format!("http://{local_host}:{port}"),
                    cwd: None,
                    project: None,
                    command: String::new(),
                    started_at: String::new(),
                    owned: false,
                    development: false,
                });
            }
            _ => {}
        }
    }
    rows
}

fn parse_processes(input: &str) -> Vec<(u32, u32, String, String)> {
    input
        .lines()
        .filter_map(|line| {
            let mut rest = line.trim();
            let mut fields = Vec::new();
            for _ in 0..7 {
                let end = rest.find(char::is_whitespace)?;
                fields.push(&rest[..end]);
                rest = rest[end..].trim_start();
            }
            Some((
                fields[0].parse().ok()?,
                fields[1].parse().ok()?,
                fields[2..7].join(" "),
                rest.to_string(),
            ))
        })
        .collect()
}

fn parse_cwds(input: &str) -> Vec<(u32, String)> {
    let mut pid = None;
    let mut result = Vec::new();
    for line in input.lines() {
        if let Some(value) = line.strip_prefix('p') {
            pid = value.parse().ok();
        }
        if let Some(path) = line.strip_prefix('n') {
            if let Some(pid) = pid {
                result.push((pid, path.to_string()));
            }
        }
    }
    result
}

fn project_root(cwd: &str) -> Option<String> {
    let path = std::path::Path::new(cwd);
    // Application bundles are not development projects, even if they contain package.json.
    if path
        .components()
        .any(|part| part.as_os_str().to_string_lossy().ends_with(".app"))
    {
        return None;
    }
    path.ancestors()
        .find(|dir| {
            [
                ".git",
                "package.json",
                "Cargo.toml",
                "go.mod",
                "pyproject.toml",
                "Gemfile",
                "build.gradle",
                "build.gradle.kts",
                "Package.swift",
                "composer.json",
            ]
            .iter()
            .any(|marker| dir.join(marker).exists())
        })
        .map(|dir| dir.to_string_lossy().into_owned())
}

fn can_stop(pid: u32, uid: u32, current_uid: u32, expected: &str, actual: &str) -> bool {
    pid > 1
        && pid != std::process::id()
        && uid == current_uid
        && !expected.is_empty()
        && expected == actual
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parses_listeners_and_collapses_ipv4_ipv6_duplicates() {
        let rows = parse_listeners(
            "p42\ncnode\nu501\nf12\nn127.0.0.1:3000\nf13\nn[::1]:3000\nf14\nn*:3001\np50\ncPython\nn*:8000\n",
        );
        assert_eq!(rows.len(), 3);
        assert_eq!(
            (rows[0].pid, rows[0].port, rows[0].process.as_str()),
            (42, 3000, "node")
        );
        assert_eq!(rows[0].url, "http://localhost:3000");
        assert_eq!(rows[2].port, 8000);
    }
    #[test]
    fn ignores_invalid_endpoints_and_handles_process_names_with_spaces() {
        let rows = parse_listeners(
            "p9\ncMy Server\nn[::1]:9000\nn*:invalid\nn*:0\nnmissing\npbad\nn*:7777\n",
        );
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].process, "My Server");
        assert_eq!(rows[0].address, "[::1]:9000");
    }
    #[test]
    fn parses_identity_without_truncating_commands_with_spaces() {
        let rows = parse_processes(
            " 42 501 Mon Nov  2 22:00:00 2026 /usr/bin/node /my project/server.js\n",
        );
        assert_eq!(
            rows,
            vec![(
                42,
                501,
                "Mon Nov 2 22:00:00 2026".into(),
                "/usr/bin/node /my project/server.js".into()
            )]
        );
    }
    #[test]
    fn preserves_spaces_in_working_directories() {
        assert_eq!(
            parse_cwds("p42\nfcwd\nn/Users/me/my project\np51\nfcwd\nn/tmp\n"),
            vec![(42, "/Users/me/my project".into()), (51, "/tmp".into())]
        );
    }
    #[test]
    fn stop_requires_ownership_and_unchanged_identity() {
        assert!(can_stop(42, 501, 501, "start-a", "start-a"));
        assert!(!can_stop(42, 502, 501, "start-a", "start-a"));
        assert!(!can_stop(42, 501, 501, "start-a", "start-b"));
        assert!(!can_stop(1, 501, 501, "start-a", "start-a"));
        assert!(!can_stop(42, 501, 501, "", ""));
    }
}
