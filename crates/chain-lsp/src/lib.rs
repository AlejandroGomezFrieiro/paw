#![doc = include_str!("../README.md")]

mod host;
mod position;
mod server;

use anyhow::Result;
use lsp_server::{Connection, Message, Notification};
use lsp_types::notification::{Notification as _, ShowMessage};
use lsp_types::{
    CompletionOptions, HoverProviderCapability, InitializeParams, MessageType, OneOf,
    ServerCapabilities, ServerInfo, ShowMessageParams, TextDocumentSyncCapability,
    TextDocumentSyncKind,
};

pub use host::{Host, InitOptions, SchemaSource, read_context};
pub use server::CONTEXT;

/// How the server starts: the source of the schema that the command line
/// gives. The `initializationOptions` of the client come before it.
#[derive(Clone, Debug, Default)]
pub struct Options {
    pub schema: Option<SchemaSource>,
}

/// Serves one client on `connection`, from its `initialize` to its `exit`.
///
/// # Errors
///
/// When the connection breaks, or the client does not start with
/// `initialize`.
pub fn serve(connection: &Connection, options: &Options) -> Result<()> {
    let (id, params) = connection.initialize_start()?;
    let params: InitializeParams = serde_json::from_value(params)?;
    let (init, mut warnings) = InitOptions::read(params.initialization_options);
    let mut host = Host::default();
    match read_context(init.chain_context.clone().unwrap_or_default()) {
        Ok(context) => host.context = context,
        Err(message) => warnings.push(message),
    }
    match init.schema_source().or_else(|| options.schema.clone()) {
        Some(source) => match source.load() {
            Ok(schema) => host.schema = Some(schema),
            Err(message) => warnings.push(format!(
                "{message}; only the errors of the grammar are checked"
            )),
        },
        None => warnings
            .push("no schema of the host: only the errors of the grammar are checked".into()),
    }
    let result = serde_json::json!({
        "capabilities": capabilities(),
        "serverInfo": ServerInfo { name: "chain-lsp".into(), version: Some(env!("CARGO_PKG_VERSION").into()) },
    });
    connection.initialize_finish(id, result)?;
    for message in warnings {
        let params = ShowMessageParams {
            typ: MessageType::WARNING,
            message: format!("chain-lsp: {message}"),
        };
        connection
            .sender
            .send(Notification::new(ShowMessage::METHOD.into(), params).into())?;
    }
    let mut server = server::Server::new(host);
    for message in &connection.receiver {
        match message {
            Message::Request(request) => {
                if connection.handle_shutdown(&request)? {
                    return Ok(());
                }
                connection.sender.send(server.request(request).into())?;
            }
            Message::Notification(notification) => {
                for out in server.notify(notification) {
                    connection.sender.send(out.into())?;
                }
            }
            // The server sends no request, so no response comes to it.
            Message::Response(_) => {}
        }
    }
    Ok(())
}

/// What the server does: the whole text at each change, diagnostics,
/// formatting, completion after `=`, hover and go to definition.
fn capabilities() -> ServerCapabilities {
    ServerCapabilities {
        text_document_sync: Some(TextDocumentSyncCapability::Kind(TextDocumentSyncKind::FULL)),
        document_formatting_provider: Some(OneOf::Left(true)),
        completion_provider: Some(CompletionOptions {
            trigger_characters: Some(vec!["=".into()]),
            ..CompletionOptions::default()
        }),
        hover_provider: Some(HoverProviderCapability::Simple(true)),
        definition_provider: Some(OneOf::Left(true)),
        ..ServerCapabilities::default()
    }
}
