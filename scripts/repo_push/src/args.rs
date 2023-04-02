use clap::Parser;

#[derive(Parser, Debug)]
pub struct Args {
    /// Path of the repository
    #[arg(short, long)]
    pub path: String,

    /// Whether to overwrite remote history
    #[arg(short, long, default_value_t = false)]
    pub overwrite: bool,

    /// Whether to resume push from the last point
    #[arg(short, long, default_value_t = true)]
    pub resume: bool,

    /// Number of commits to push per iteration
    #[arg(short, long, default_value_t = 10)]
    pub window_size: usize,

    /// Config file location
    #[arg(short, long, default_value_t = String::from("./config.toml"))]
    pub config_file: String
}

impl Args {
    pub fn create() -> Self {
        Self::parse()
    }
}