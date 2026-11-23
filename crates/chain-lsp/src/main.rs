//! `chain-lsp`: the language server of the chain language on standard input
//! and output.

use std::path::PathBuf;

use anyhow::Result;
use chain_lsp::{Options, SchemaSource, serve};
use clap::Parser;
use lsp_server::Connection;

/// A language server for the chain language, on standard input and output.
/// The client's `initializationOptions` can give the schema of the host in
/// place of these options.
#[derive(Parser, Debug)]
#[command(version)]
struct Cli {
    /// The schema of the host: a JSON file.
    #[arg(long, value_name = "FILE", conflicts_with = "schema_command")]
    schema: Option<PathBuf>,
    /// The schema of the host: a program and its arguments, which print it
    /// as JSON, such as `--schema-command paw chain schema`. It takes the
    /// rest of the command line.
    #[arg(long, value_name = "PROGRAM", num_args = 1.., allow_hyphen_values = true, trailing_var_arg = true)]
    schema_command: Option<Vec<String>>,
    /// Talk on standard input and output, which the server always does.
    /// Some editors give this option.
    #[arg(long)]
    stdio: bool,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let schema = match (cli.schema, cli.schema_command) {
        (Some(path), _) => Some(SchemaSource::File(path)),
        (None, Some(words)) => Some(SchemaSource::Command(words)),
        (None, None) => None,
    };
    let (connection, threads) = Connection::stdio();
    serve(&connection, &Options { schema })?;
    // The reader thread ends with the input, after `exit`.
    drop(connection);
    threads.join()?;
    Ok(())
}
