//! The messages of the server: each request is a function of the open texts
//! and the host, and each change of a text publishes its diagnostics.

use std::collections::HashMap;

use chain_syntax::{
    CompletionKind, Severity, check_text, complete, definition, format, format_with, hover, parse,
};
use lsp_server::{ErrorCode, Notification, Request, Response};
use lsp_types::notification::{
    DidChangeTextDocument, DidCloseTextDocument, DidOpenTextDocument, Notification as _,
    PublishDiagnostics,
};
use lsp_types::request::{Completion, Formatting, GotoDefinition, HoverRequest, Request as _};
use lsp_types::{
    CompletionItem, CompletionItemKind, CompletionParams, CompletionResponse, CompletionTextEdit,
    Diagnostic, DiagnosticSeverity, DidChangeTextDocumentParams, DidCloseTextDocumentParams,
    DidOpenTextDocumentParams, DocumentFormattingParams, GotoDefinitionParams,
    GotoDefinitionResponse, Hover, HoverContents, HoverParams, Location, MarkupContent, MarkupKind,
    NumberOrString, PublishDiagnosticsParams, TextDocumentPositionParams, TextEdit, Uri,
};
use serde::Serialize;
use serde::de::DeserializeOwned;
use serde_json::Value;

use crate::host::Host;
use crate::position::{offset, range};

/// The notification of a client that changes [`Host::context`].
pub const CONTEXT: &str = "chain/context";

/// The open texts, by their URI, and the host.
pub(crate) struct Server {
    pub host: Host,
    texts: HashMap<String, String>,
}

impl Server {
    pub fn new(host: Host) -> Self {
        Self {
            host,
            texts: HashMap::new(),
        }
    }

    /// The answer to a request.
    pub fn request(&self, request: Request) -> Response {
        let id = request.id.clone();
        let result = match request.method.as_str() {
            Formatting::METHOD => answer(request, |params: DocumentFormattingParams| {
                self.format(&params)
            }),
            Completion::METHOD => answer(request, |params: CompletionParams| {
                self.complete(&params.text_document_position)
            }),
            HoverRequest::METHOD => answer(request, |params: HoverParams| {
                self.hover(&params.text_document_position_params)
            }),
            GotoDefinition::METHOD => answer(request, |params: GotoDefinitionParams| {
                self.definition(&params.text_document_position_params)
            }),
            method => Err((
                ErrorCode::MethodNotFound,
                format!("chain-lsp does not answer `{method}`"),
            )),
        };
        match result {
            Ok(value) => Response::new_ok(id, value),
            Err((code, message)) => Response::new_err(id, code as i32, message),
        }
    }

    /// What the server sends after a notification: the diagnostics of a
    /// text that opened, changed or closed.
    pub fn notify(&mut self, notification: Notification) -> Vec<Notification> {
        let Notification { method, params } = notification;
        match method.as_str() {
            DidOpenTextDocument::METHOD => {
                let Ok(params) = serde_json::from_value::<DidOpenTextDocumentParams>(params) else {
                    return Vec::new();
                };
                let document = params.text_document;
                self.texts
                    .insert(document.uri.as_str().to_string(), document.text);
                vec![self.diagnostics(document.uri, Some(document.version))]
            }
            DidChangeTextDocument::METHOD => {
                let Ok(params) = serde_json::from_value::<DidChangeTextDocumentParams>(params)
                else {
                    return Vec::new();
                };
                // The server asks for the whole text at each change, so the
                // last change holds it.
                let Some(change) = params.content_changes.into_iter().last() else {
                    return Vec::new();
                };
                let document = params.text_document;
                self.texts
                    .insert(document.uri.as_str().to_string(), change.text);
                vec![self.diagnostics(document.uri, Some(document.version))]
            }
            DidCloseTextDocument::METHOD => {
                let Ok(params) = serde_json::from_value::<DidCloseTextDocumentParams>(params)
                else {
                    return Vec::new();
                };
                let uri = params.text_document.uri;
                self.texts.remove(uri.as_str());
                // An editor shows no diagnostics of a closed text.
                vec![publish(uri, Vec::new(), None)]
            }
            CONTEXT => {
                self.host.context = params;
                Vec::new()
            }
            _ => Vec::new(),
        }
    }

    fn text(&self, uri: &Uri) -> Result<&str, (ErrorCode, String)> {
        self.texts
            .get(uri.as_str())
            .map(String::as_str)
            .ok_or_else(|| {
                (
                    ErrorCode::InvalidParams,
                    format!("{} is not open", uri.as_str()),
                )
            })
    }

    /// The diagnostics of a text: those of the parser and, with a schema,
    /// those of the check.
    fn diagnostics(&self, uri: Uri, version: Option<i32>) -> Notification {
        let text = self.texts.get(uri.as_str()).map_or("", String::as_str);
        let parsed = match &self.host.schema {
            Some(schema) => check_text(text, schema),
            None => parse(text),
        };
        let list = parsed
            .diagnostics
            .iter()
            .map(|diagnostic| Diagnostic {
                range: range(text, diagnostic.span.start, diagnostic.span.end),
                severity: Some(match diagnostic.severity() {
                    Severity::Error => DiagnosticSeverity::ERROR,
                    Severity::Warning => DiagnosticSeverity::WARNING,
                }),
                code: Some(NumberOrString::String(diagnostic.code.as_str().into())),
                source: Some("chain".into()),
                message: diagnostic.message.clone(),
                ..Diagnostic::default()
            })
            .collect();
        publish(uri, list, version)
    }

    /// The whole text in its one layout, as one edit. Null for a text with
    /// an error: the formatter changes no text that it cannot read.
    fn format(
        &self,
        params: &DocumentFormattingParams,
    ) -> Result<Option<Vec<TextEdit>>, (ErrorCode, String)> {
        let text = self.text(&params.text_document.uri)?;
        let formatted = match &self.host.schema {
            Some(schema) => format_with(text, schema),
            None => format(text),
        };
        Ok(formatted.ok().map(|new_text| {
            vec![TextEdit {
                range: range(text, 0, text.len()),
                new_text,
            }]
        }))
    }

    fn complete(
        &self,
        at: &TextDocumentPositionParams,
    ) -> Result<Option<CompletionResponse>, (ErrorCode, String)> {
        let text = self.text(&at.text_document.uri)?;
        let Some(schema) = &self.host.schema else {
            return Ok(None);
        };
        let items = complete(text, offset(text, at.position), schema)
            .into_iter()
            .map(|completion| CompletionItem {
                kind: Some(match completion.kind {
                    CompletionKind::Device => CompletionItemKind::CLASS,
                    CompletionKind::Split => CompletionItemKind::MODULE,
                    CompletionKind::Modulator => CompletionItemKind::EVENT,
                    CompletionKind::Parameter => CompletionItemKind::PROPERTY,
                    CompletionKind::Value => CompletionItemKind::ENUM_MEMBER,
                }),
                detail: Some(completion.detail),
                text_edit: Some(CompletionTextEdit::Edit(TextEdit {
                    range: range(text, completion.span.start, completion.span.end),
                    new_text: completion.insert,
                })),
                label: completion.label,
                ..CompletionItem::default()
            })
            .collect();
        Ok(Some(CompletionResponse::Array(items)))
    }

    fn hover(&self, at: &TextDocumentPositionParams) -> Result<Option<Hover>, (ErrorCode, String)> {
        let text = self.text(&at.text_document.uri)?;
        let Some(schema) = &self.host.schema else {
            return Ok(None);
        };
        Ok(
            hover(text, offset(text, at.position), schema).map(|found| Hover {
                // A Markdown line break after each line.
                contents: HoverContents::Markup(MarkupContent {
                    kind: MarkupKind::Markdown,
                    value: found.lines.join("  \n"),
                }),
                range: Some(range(text, found.span.start, found.span.end)),
            }),
        )
    }

    fn definition(
        &self,
        at: &TextDocumentPositionParams,
    ) -> Result<Option<GotoDefinitionResponse>, (ErrorCode, String)> {
        let text = self.text(&at.text_document.uri)?;
        Ok(definition(text, offset(text, at.position)).map(|span| {
            let location = Location {
                uri: at.text_document.uri.clone(),
                range: range(text, span.start, span.end),
            };
            GotoDefinitionResponse::Scalar(location)
        }))
    }
}

/// The result of a handler as JSON, or an error for params that do not read.
fn answer<P: DeserializeOwned, R: Serialize>(
    request: Request,
    handler: impl FnOnce(P) -> Result<R, (ErrorCode, String)>,
) -> Result<Value, (ErrorCode, String)> {
    let params = serde_json::from_value(request.params)
        .map_err(|error| (ErrorCode::InvalidParams, error.to_string()))?;
    let result = handler(params)?;
    serde_json::to_value(result).map_err(|error| (ErrorCode::InternalError, error.to_string()))
}

fn publish(uri: Uri, diagnostics: Vec<Diagnostic>, version: Option<i32>) -> Notification {
    Notification::new(
        PublishDiagnostics::METHOD.into(),
        PublishDiagnosticsParams {
            uri,
            diagnostics,
            version,
        },
    )
}
