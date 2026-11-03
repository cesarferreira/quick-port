mod discovery;
use anyhow::Result;
use clap::{Parser, Subcommand};
#[derive(Parser)]
#[command(version, about = "See and manage your local development servers")]
struct Cli {
    #[command(subcommand)]
    command: Option<Action>,
    /// Print all listeners as JSON
    #[arg(long)]
    json: bool,
}
#[derive(Subcommand)]
enum Action {
    /// Gracefully stop an owned process after verifying its start time
    Stop {
        #[arg(long)]
        pid: u32,
        #[arg(long)]
        started_at: String,
    },
}
fn main() -> Result<()> {
    let cli = Cli::parse();
    if let Some(Action::Stop { pid, started_at }) = cli.command {
        return discovery::stop(pid, &started_at);
    }
    let servers = discovery::scan()?;
    if cli.json {
        println!("{}", serde_json::to_string(&servers)?);
    } else {
        println!("{:<7} {:<8} {:<20} PROJECT", "PORT", "PID", "PROCESS");
        for server in servers {
            println!(
                "{:<7} {:<8} {:<20} {}",
                server.port,
                server.pid,
                server.process,
                server.project.as_deref().unwrap_or("—")
            );
        }
    }
    Ok(())
}
