use git2::{Repository, Worktree, WorktreeAddOptions, WorktreeLockStatus, WorktreePruneOptions};
use std::{env, error::Error};
use uuid::Uuid;

pub struct WorktreeGuard {
    worktree: Worktree,
}

impl WorktreeGuard {
    const WORKTREE_NAME: &str = "repo_push_worktree";

    pub fn new(repo: &Repository) -> Result<Self, Box<dyn Error>> {
        let tmp = env::temp_dir();
        let worktree_path = tmp.join(format!("{}-{}", Self::WORKTREE_NAME, Uuid::new_v4()));
        let head = repo
            .head()
            .map_err(|err| format!("Failed to get repository head: {err}"))?;
        let worktree = repo
            .worktree(
                Self::WORKTREE_NAME,
                &worktree_path,
                Some(WorktreeAddOptions::new().reference(Some(&head))),
            )
            .map_err(|err| format!("Failed to create worktree: {err}"))?;
        println!("worktree: {:?}", worktree.path());
        return Ok(Self { worktree });
    }
}

impl Drop for WorktreeGuard {
    fn drop(&mut self) {
        if let Err(err) = self
            .worktree
            .prune(Some(WorktreePruneOptions::new().locked(true).valid(true)))
        {
            eprintln!(
                "Failed to prune worktree: {:?}, remove it manually. Reason: {err}",
                self.worktree.path()
            );
        } else {
            println!("Pruned worktree");
        }
    }
}
