use std::{error::Error, fs::File};

pub struct Config {
    org_name: String,
}

impl Config {
    pub fn parse(file: String) -> Result<Self, Box<dyn Error>> {
        let file = File::open(&file).map_err(|err| format!("Failed to open file {file}: {err}"))?;
        todo!()
    }
}
