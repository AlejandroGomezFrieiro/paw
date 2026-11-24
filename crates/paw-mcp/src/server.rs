//! The MCP server: `rmcp`'s handler over [`Tools`]. rmcp speaks the protocol
//! (the handshake, the revisions, JSON-RPC on stdio); this gives it the tool
//! list, runs the calls and serves the resources.
//!
//! A tool call waits on the kernel and may measure audio, so it runs on a
//! blocking thread of the runtime. Calls take their turn on one [`Tools`],
//! as the kernel takes them one at a time anyway.

use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use anyhow::{Context, Result};
use rmcp::model::{
    CallToolRequestParams, CallToolResponse, CallToolResult, ContentBlock, Implementation,
    InitializeRequestParams, InitializeResult, ListResourceTemplatesResult, ListResourcesResult,
    ListToolsResult, PaginatedRequestParams, ProtocolVersion, ReadResourceRequestParams,
    ReadResourceResponse, ReadResourceResult, ServerCapabilities,
};
use rmcp::service::{NotificationContext, RequestContext, RoleServer};
use rmcp::{ErrorData, ServerHandler, ServiceExt};
use serde_json::{Value, json};

use crate::schema;
use crate::tools::{Reply, ToolError, Tools};

/// Protocol revisions with an `initialize` handshake, newest first, and the
/// one that carries the revision in each request's `_meta`.
const VERSIONS: [ProtocolVersion; 5] = [
    ProtocolVersion::V_2025_11_25,
    ProtocolVersion::V_2025_06_18,
    ProtocolVersion::V_2025_03_26,
    ProtocolVersion::V_2024_11_05,
    ProtocolVersion::V_2026_07_28,
];

#[derive(Clone)]
pub(crate) struct PawServer {
    tools: Arc<Mutex<Tools>>,
}

impl PawServer {
    pub(crate) fn new(tools: Tools) -> Self {
        Self { tools: Arc::new(Mutex::new(tools)) }
    }

    pub(crate) fn tools(&self) -> Arc<Mutex<Tools>> {
        self.tools.clone()
    }

    /// Serve on stdin and stdout until stdin closes.
    pub(crate) async fn serve_stdio(self) -> Result<()> {
        let running = self.serve(rmcp::transport::stdio()).await.context("starting MCP")?;
        running.waiting().await.context("serving MCP")?;
        Ok(())
    }

    /// Run `job` on the tools on a blocking thread.
    async fn with_tools<T: Send + 'static>(
        &self,
        job: impl FnOnce(&mut Tools) -> T + Send + 'static,
    ) -> Result<T, ErrorData> {
        let tools = self.tools.clone();
        tokio::task::spawn_blocking(move || job(&mut lock(&tools)))
            .await
            .map_err(|err| ErrorData::internal_error(err.to_string(), None))
    }
}

fn lock(tools: &Mutex<Tools>) -> MutexGuard<'_, Tools> {
    // A tool that panicked leaves nothing half done that the next call reads.
    tools.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Refuse a cursor. Each list comes whole in one page and gives no
/// `nextCursor`, so no cursor that a client sends is one of ours: the spec
/// answers an invalid cursor with "Invalid params" (-32602).
fn refuse_cursor(request: Option<&PaginatedRequestParams>) -> Result<(), ErrorData> {
    match request.and_then(|params| params.cursor.as_deref()) {
        Some(cursor) => Err(ErrorData::invalid_params(
            format!("invalid cursor `{cursor}`: the list has one page and no cursors"),
            None,
        )),
        None => Ok(()),
    }
}

/// A value of an rmcp type from the JSON it has on the wire.
fn from_json<T: serde::de::DeserializeOwned>(value: Value) -> Result<T, ErrorData> {
    serde_json::from_value(value).map_err(|err| ErrorData::internal_error(err.to_string(), None))
}

impl ServerHandler for PawServer {
    fn get_info(&self) -> InitializeResult {
        // listChanged stays false because the server sends no list_changed
        // notification. The tool list is fixed when the server starts
        // (--allow-eval). The manual's pages change only when the kernel
        // loads other extensions, and the server does not watch for that.
        let capabilities: ServerCapabilities = serde_json::from_value(json!({
            "tools": { "listChanged": false },
            "resources": { "subscribe": false, "listChanged": false },
        }))
        .expect("the capabilities are valid");
        InitializeResult::new(capabilities)
            .with_protocol_version(VERSIONS[0].clone())
            .with_server_info(
                Implementation::new("paw-mcp", env!("CARGO_PKG_VERSION"))
                    .with_title("paw")
                    .with_website_url(env!("CARGO_PKG_REPOSITORY")),
            )
            .with_instructions(schema::INSTRUCTIONS)
    }

    fn supported_protocol_versions(&self) -> std::borrow::Cow<'static, [ProtocolVersion]> {
        std::borrow::Cow::Borrowed(&VERSIONS)
    }

    async fn initialize(
        &self,
        request: InitializeRequestParams,
        context: RequestContext<RoleServer>,
    ) -> Result<InitializeResult, ErrorData> {
        context.peer.set_peer_info(request.clone());
        let result = self.negotiate_initialize(&request)?;
        let client = &request.client_info;
        eprintln!(
            "paw-mcp: {} {} asked for protocol {}; speaking {}",
            client.name, client.version, request.protocol_version, result.protocol_version
        );
        Ok(result)
    }

    async fn on_initialized(&self, _context: NotificationContext<RoleServer>) {
        eprintln!("paw-mcp: client ready");
    }

    async fn list_tools(
        &self,
        request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, ErrorData> {
        refuse_cursor(request.as_ref())?;
        let tools = lock(&self.tools).list();
        Ok(ListToolsResult::with_all_items(tools))
    }

    async fn call_tool(
        &self,
        request: CallToolRequestParams,
        _context: RequestContext<RoleServer>,
    ) -> Result<CallToolResponse, ErrorData> {
        let name = request.name.to_string();
        let args = request.arguments.map_or(Value::Null, Value::Object);
        let started = std::time::Instant::now();
        let shown = name.clone();
        let outcome = self.with_tools(move |tools| tools.call(&name, &args)).await?;
        eprintln!(
            "paw-mcp: {shown} {} in {} ms",
            if outcome.is_err() { "failed" } else { "done" },
            started.elapsed().as_millis()
        );
        let mut result = match outcome {
            Ok(Reply { text, data }) => {
                let mut result = CallToolResult::success(vec![ContentBlock::text(text.trim_end())]);
                result.structured_content = Some(data);
                result
            }
            Err(ToolError(text)) => {
                let mut result = CallToolResult::error(vec![ContentBlock::text(text.trim_end())]);
                result.structured_content = Some(json!({ "error": text }));
                result
            }
        };
        result.is_error = Some(result.is_error.unwrap_or(false));
        Ok(result.into())
    }

    async fn list_resources(
        &self,
        request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListResourcesResult, ErrorData> {
        refuse_cursor(request.as_ref())?;
        let list = self.with_tools(|tools| tools.resources_list()).await?;
        Ok(ListResourcesResult::with_all_items(from_json(Value::Array(list))?))
    }

    async fn list_resource_templates(
        &self,
        request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListResourceTemplatesResult, ErrorData> {
        refuse_cursor(request.as_ref())?;
        let list = lock(&self.tools).resource_templates();
        Ok(ListResourceTemplatesResult::with_all_items(from_json(Value::Array(list))?))
    }

    async fn read_resource(
        &self,
        request: ReadResourceRequestParams,
        _context: RequestContext<RoleServer>,
    ) -> Result<ReadResourceResponse, ErrorData> {
        let uri = request.uri.clone();
        let read = self.with_tools(move |tools| tools.resource_read(&uri)).await?;
        let value = read.map_err(|ToolError(msg)| ErrorData::resource_not_found(msg, None))?;
        let result: ReadResourceResult = from_json(value)?;
        Ok(result.into())
    }
}
