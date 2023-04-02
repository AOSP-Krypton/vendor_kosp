mod args;
mod config;
mod worktree_guard;

use std::error::Error;

use args::Args;
use config::Config;
use worktree_guard::WorktreeGuard;
use git2::{Repository, Worktree};

fn main() -> Result<(), Box<dyn Error>> {
    let args = Args::create();
    //let config = Config::parse(args.config_file)?;
    let repo =
        Repository::open(args.path).map_err(|err| format!("Failed to open repository: {err}"))?;
    let guard = WorktreeGuard::new(&repo)?;
    drop(guard);
    Ok(())
}
