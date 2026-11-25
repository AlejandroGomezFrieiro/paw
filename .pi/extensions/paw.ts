/**
 * The hooks and the rules of paw for pi.
 *
 * A session of pi in this checkout gets what .claude/settings.json gives a
 * session of Claude Code:
 *
 * - The skills of .claude/skills, through .pi/settings.json.
 * - tools/guard-hook.py before each command of the tool `bash`. It refuses
 *   the commands that AGENTS.md forbids.
 * - tools/vale-hook.sh after each edit or write. It checks each Markdown
 *   file with Vale and gives the alerts to the agent.
 * - The folder of the suite slots, /tmp/paw-suite-locks, when a session
 *   starts.
 * - The local rules of CLAUDE.local.md in the system prompt. pi reads
 *   AGENTS.md and CLAUDE.md, and not CLAUDE.local.md.
 *
 * The two scripts stay the only copy of the rules: this file gives them the
 * shape of a tool call and nothing else. pi has no sandbox, so the sandbox
 * block of .claude/settings.json does not apply to a command of pi.
 */

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const GUARD_TIMEOUT_MS = 10_000;
const VALE_TIMEOUT_MS = 120_000;
const SUITE_LOCKS = "/tmp/paw-suite-locks";

interface HookResult {
	/** The exit code, or null when a signal stopped the script. */
	code: number | null;
	stdout: string;
	stderr: string;
	signal: string | null;
}

/** The root of the checkout that holds the file, or undefined. */
function repoRoot(dir: string): string | undefined {
	let current = path.resolve(dir);
	for (;;) {
		if (fs.existsSync(path.join(current, "tools", "guard-hook.py"))) return current;
		const parent = path.dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

/** Run a program, with its input as the text of stdin when the program reads one. */
function runProcess(
	script: string,
	args: string[],
	input: string | undefined,
	cwd: string,
	timeoutMs: number,
): Promise<HookResult> {
	return new Promise((resolve) => {
		const child = spawn(script, args, {
			cwd,
			timeout: timeoutMs,
			stdio: [input === undefined ? "ignore" : "pipe", "pipe", "pipe"],
		});
		let stdout = "";
		let stderr = "";
		child.stdout?.on("data", (data: Buffer) => {
			stdout += data.toString();
		});
		child.stderr?.on("data", (data: Buffer) => {
			stderr += data.toString();
		});
		child.on("error", (error: Error) => {
			resolve({ code: null, stdout, stderr: `${stderr}${error.message}\n`, signal: null });
		});
		child.on("close", (code, signal) => {
			resolve({ code, stdout, stderr, signal });
		});
		if (input !== undefined) {
			child.stdin?.on("error", () => {
				// The script can stop before it reads its input. Its result says why.
			});
			child.stdin?.end(input);
		}
	});
}

/** Run a hook of .claude/settings.json with the JSON of a Claude tool call. */
function runHook(script: string, payload: unknown, cwd: string, timeoutMs: number): Promise<HookResult> {
	return runProcess(script, [], JSON.stringify(payload), cwd, timeoutMs);
}

function notify(ctx: ExtensionContext, message: string, type: "info" | "warning" | "error"): void {
	if (ctx.hasUI) ctx.ui.notify(message, type);
}

function hookFailure(name: string, result: HookResult): string {
	const reason = result.stderr.trim() || (result.signal ? `the signal ${result.signal}` : `the exit code ${result.code}`);
	return `${name} did not run: ${reason}`;
}

const CODE_EXTENSIONS = new Set([
	".rs",
	".lua",
	".tl",
	".ts",
	".mts",
	".cts",
	".js",
	".mjs",
	".cjs",
	".sh",
	".bash",
	".py",
	".nix",
	".go",
	".c",
	".h",
	".cc",
	".cpp",
	".hpp",
	".java",
	".kt",
	".toml",
	".yaml",
	".yml",
]);

/** The comment text of a line, or undefined when the line is not a comment. */
function commentText(extension: string, line: string): string | undefined {
	const text = line.trim();
	if (!text) return undefined;
	if (/^#!/i.test(text)) return undefined;
	// Legal headers, public API docs, required project notes, and tool directives.
	if (/SPDX-License-Identifier|Copyright|Licensed under|This file is part of|MIT License|Apache License/i.test(text)) return undefined;
	const content = text.replace(/^(?:\/\/\/|\/\/!|\/\*\*|\/\*!|\/\/|\/\*|---|--|#|;|\*)\s*/, "").trim();
	if (/^(prettier-ignore|stylua:|luacheck:|rustfmt::|eslint-|@ts-|type: ignore|noqa\b|fmt: (off|on)|shellcheck\s|pragma\s|SAFETY:)/i.test(content)) return undefined;
	if (extension === ".rs") {
		if (/^(\/\/\/|\/\/!|\/\*\*|\/\*!)/.test(text)) return undefined;
		if (/^(\/\/|\/\*|\*)/.test(text)) return text;
		return undefined;
	}
	if (extension === ".lua" || extension === ".tl") {
		if (/^---/.test(text)) return undefined;
		if (/^--/.test(text)) return text;
		return undefined;
	}
	if (extension === ".js" || extension === ".mjs" || extension === ".cjs" || extension === ".ts" || extension === ".mts" || extension === ".cts") {
		if (/^(\/\/\/|\/\*\*)/.test(text)) return undefined;
		if (/^(\/\/|\/\*|\*)/.test(text)) return text;
		return undefined;
	}
	if (/^(#|;)/.test(text)) return text;
	return undefined;
}

interface AddedLine {
	number: number;
	text: string;
}

/** The lines that an edit adds, with their numbers in the new file. */
function addedLines(absolute: string, patch: string | undefined): AddedLine[] {
	if (!patch) {
		return fs
			.readFileSync(absolute, "utf8")
			.split("\n")
			.map((text, index) => ({ number: index + 1, text }));
	}
	const lines: AddedLine[] = [];
	let number = 0;
	for (const line of patch.split("\n")) {
		const hunk = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)/);
		if (hunk) {
			number = Number(hunk[1]);
			continue;
		}
		if (line.startsWith("+++") || line.startsWith("---")) continue;
		if (line.startsWith("+")) {
			lines.push({ number, text: line.slice(1) });
			number += 1;
		} else if (line.startsWith(" ")) {
			number += 1;
		}
	}
	return lines;
}

const C_LIKE = new Set([".rs", ".ts", ".mts", ".cts", ".js", ".mjs", ".cjs"]);

interface BlockStart {
	/** A doc comment that defines an API or a module, which the hook keeps. */
	doc: boolean;
	end: string;
}

/** The start of a block comment, and where it ends. */
function blockStart(extension: string, text: string): BlockStart | undefined {
	if (C_LIKE.has(extension) && /^\/\*\*|^\/\*!/.test(text)) return { doc: true, end: "*/" };
	if (C_LIKE.has(extension) && /^\/\*/.test(text)) return { doc: false, end: "*/" };
	if ((extension === ".lua" || extension === ".tl") && /^--\[=*\[/.test(text)) return { doc: false, end: "]]" };
	return undefined;
}

/** The comments that the no-comments skill refuses, with their lines. */
function commentFindings(filePath: string, patch: string | undefined): string[] {
	const extension = path.extname(filePath).toLowerCase();
	if (!CODE_EXTENSIONS.has(extension)) return [];
	const findings: string[] = [];
	let blockEnd: string | undefined;
	for (const line of addedLines(filePath, patch)) {
		const text = line.text.trim();
		if (blockEnd) {
			if (text.includes(blockEnd)) blockEnd = undefined;
			continue;
		}
		const block = blockStart(extension, text);
		if (block) {
			if (!text.includes(block.end)) blockEnd = block.end;
			if (block.doc) continue;
		}
		const comment = commentText(extension, line.text);
		if (comment) findings.push(`L${line.number}: ${comment}`);
	}
	return findings;
}

const PAW_IMPLEMENTERS = new Set(["paw-builder", "paw-worker"]);
const AGENT_TIMEOUT_MS = 30_000;
const TICKET_TIMEOUT_MS = 5_000;
const ticketTitles = new Map<string, string>();

interface SubagentInfo {
	id: string;
	type: string;
	description: string;
	status: string;
	depth: number;
	parentAgentId?: string;
	workflowId?: string;
}

const runningAgents = new Map<string, SubagentInfo>();
let uiCtx: ExtensionContext | undefined;

/** The title of a ticket, read from the board once for each session. */
async function ticketTitle(root: string, ticket: string): Promise<string | undefined> {
	const cached = ticketTitles.get(ticket);
	if (cached) return cached;
	const result = await runProcess("backlog", ["task", ticket, "--plain"], undefined, root, TICKET_TIMEOUT_MS);
	if (result.code !== 0) return undefined;
	const title = result.stdout.match(/^Task TASK-\d+ - (.+)$/m)?.[1]?.trim();
	if (title) ticketTitles.set(ticket, title);
	return title;
}

/** Put the ticket and its title in the agent description that the UI shows. */
async function labelAgentDescription(
	root: string,
	ticket: string,
	input: { description?: unknown },
): Promise<void> {
	const description = typeof input.description === "string" ? input.description : "";
	if (description.toLowerCase().includes(`task-${ticket}`)) return;
	const title = await ticketTitle(root, ticket);
	const label = `TASK-${ticket}${title ? ` - ${title.slice(0, 70)}` : ""}`;
	input.description = description ? `${label} | ${description}` : label;
}

/** Show the ticket of each running agent in the footer. */
function renderAgentStatus(): void {
	const ctx = uiCtx;
	if (!ctx || !ctx.hasUI || ctx.mode !== "tui") return;
	const agents = [...runningAgents.values()].filter((agent) => agent.depth === 1);
	if (agents.length === 0) {
		ctx.ui.setStatus("paw:agents", undefined);
		return;
	}
	const shown = agents.slice(0, 3).map((agent) => {
		const ticket = agent.description.match(/TASK-\d+/i)?.[0] ?? agent.type;
		return `${ticket} ${agent.type.replace(/^paw-/, "")}`;
	});
	const more = agents.length > shown.length ? ` +${agents.length - shown.length}` : "";
	ctx.ui.setStatus("paw:agents", `paw: ${shown.join(" | ")}${more}`);
}

/**
 * Label an agent with its ticket, and refuse a builder or a worker whose
 * type disagrees with the `agent:` label. The type comes from the label
 * (`.orchestrator/agent-for.sh`), so the orchestrator cannot start a worker
 * on a builder ticket by mistake. A spawn with no ticket passes.
 */
async function guardAgent(event: { input: Record<string, unknown> }, ctx: ExtensionContext) {
	const input = event.input as { subagent_type?: unknown; prompt?: unknown; description?: unknown };
	const type = typeof input.subagent_type === "string" ? input.subagent_type.toLowerCase() : "";
	const root = repoRoot(ctx.cwd);
	if (!root) return undefined;
	const text = `${typeof input.prompt === "string" ? input.prompt : ""}\n${typeof input.description === "string" ? input.description : ""}`;
	const match = text.match(/TASK-(\d+)/i) ?? text.match(/\bticket\s+(\d+)\b/i);
	if (!match) return undefined;
	const ticket = match[1];
	await labelAgentDescription(root, ticket, input);
	if (!PAW_IMPLEMENTERS.has(type)) return undefined;
	const agentFor = path.join(root, ".orchestrator", "agent-for.sh");
	if (!fs.existsSync(agentFor)) return undefined;
	const result = await runProcess(agentFor, [ticket], undefined, root, AGENT_TIMEOUT_MS);
	if (result.code !== 0) {
		const reason = result.stderr.trim() || `agent-for.sh failed for TASK-${ticket}`;
		return { block: true, reason };
	}
	const expected = result.stdout.trim();
	if (expected !== type) {
		return {
			block: true,
			reason: `TASK-${ticket} takes ${expected}, not ${type}. Use the type that the label agent: gives, or change the label first.`,
		};
	}
	return undefined;
}

const OPENROUTER_PIN = { only: ["openai"], allow_fallbacks: false };

/**
 * Keep each request of the pinned model on the OpenAI upstream provider of
 * OpenRouter, and on no other. A split backend loses the prompt cache.
 */
function pinOpenRouterProvider(pi: ExtensionAPI): void {
	pi.on("before_provider_request", (event, ctx) => {
		if (ctx.model?.provider !== "openrouter") return;
		const payload = event.payload as { model?: unknown; provider?: unknown } | undefined;
		if (!payload || typeof payload !== "object") return;
		if (payload.model !== "openai/gpt-6.2-sol") return;
		payload.provider = OPENROUTER_PIN;
	});
}

/** Show the ticket of each running agent in the footer, and in its description. */
function installAgentTrace(pi: ExtensionAPI): void {
	const onSubagent = (data: unknown): void => {
		const info = data as Partial<SubagentInfo>;
		if (info.depth !== 1) return;
		if (typeof info.id !== "string" || typeof info.type !== "string" || typeof info.description !== "string") return;
		runningAgents.set(info.id, info as SubagentInfo);
		renderAgentStatus();
	};
	const offSubagent = (data: unknown): void => {
		const id = (data as { id?: unknown }).id;
		if (typeof id !== "string") return;
		runningAgents.delete(id);
		renderAgentStatus();
	};
	pi.events.on("subagents:created", onSubagent);
	pi.events.on("subagents:started", onSubagent);
	pi.events.on("subagents:completed", offSubagent);
	pi.events.on("subagents:failed", offSubagent);
	pi.on("session_start", (_event, ctx) => {
		uiCtx = ctx;
		runningAgents.clear();
		renderAgentStatus();
	});
	pi.on("session_shutdown", () => {
		if (uiCtx?.hasUI && uiCtx.mode === "tui") uiCtx.ui.setStatus("paw:agents", undefined);
		runningAgents.clear();
		uiCtx = undefined;
	});
}

export default function paw(pi: ExtensionAPI) {
	pinOpenRouterProvider(pi);
	installAgentTrace(pi);
	pi.on("session_start", () => {
		// The env block of .claude/settings.json gives this value to Claude Code.
		process.env.PAW_SUITE_LOCKS = SUITE_LOCKS;
		try {
			fs.mkdirSync(SUITE_LOCKS, { recursive: true });
		} catch {
			// tests/tools/suite.sh makes the folder itself when it can.
		}
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName === "Agent") return guardAgent(event, ctx);
		if (event.toolName !== "bash") return undefined;
		const root = repoRoot(ctx.cwd);
		if (!root) return undefined;
		const command = (event.input as { command?: unknown }).command;
		if (typeof command !== "string") return undefined;
		const result = await runHook(
			path.join(root, "tools", "guard-hook.py"),
			{ tool_name: "Bash", tool_input: { command } },
			root,
			GUARD_TIMEOUT_MS,
		);
		if (result.code === 2) {
			return { block: true, reason: result.stderr.trim() || "The command is refused by tools/guard-hook.py." };
		}
		if (result.code !== 0) notify(ctx, hookFailure("tools/guard-hook.py", result), "warning");
		return undefined;
	});

	pi.on("tool_result", async (event, ctx) => {
		if (event.isError) return undefined;
		if (event.toolName !== "edit" && event.toolName !== "write") return undefined;
		const root = repoRoot(ctx.cwd);
		if (!root) return undefined;
		const filePath = (event.input as { path?: unknown }).path;
		if (typeof filePath !== "string") return undefined;
		const absolute = path.resolve(ctx.cwd, filePath);
		const notices: string[] = [];
		const result = await runHook(
			path.join(root, "tools", "vale-hook.sh"),
			{
				tool_name: event.toolName === "edit" ? "Edit" : "Write",
				tool_input: { file_path: absolute },
				tool_response: { filePath: absolute },
			},
			root,
			VALE_TIMEOUT_MS,
		);
		if (result.code === 2 && result.stderr.trim()) {
			notify(ctx, `Vale: alerts in ${filePath}`, "warning");
			notices.push(result.stderr.trim());
		} else if (result.code !== 0) {
			notify(ctx, hookFailure("tools/vale-hook.sh", result), "warning");
		}
		const patch = (event as { details?: { patch?: string } }).details?.patch;
		const comments = commentFindings(absolute, patch);
		if (comments.length > 0) {
			const shown = comments.slice(0, 20);
			const more = comments.length > shown.length ? `\n  and ${comments.length - shown.length} more` : "";
			notify(ctx, `no-comments: ${comments.length} added comment(s) in ${filePath}`, "warning");
			notices.push(
				`no-comments: ${comments.length} added comment(s) in ${filePath}:\n  ${shown.join("\n  ")}${more}\n` +
					"Delete each one. Keep a line only for a legal header, a public API doc comment, a `// SAFETY:` note, " +
					"an external dependency or protocol constraint, or a tool directive. Do not shorten it.",
			);
		}
		if (notices.length === 0) return undefined;
		return {
			content: [...event.content, ...notices.map((text) => ({ type: "text" as const, text }))],
		};
	});

	pi.on("before_agent_start", (event, ctx) => {
		const root = repoRoot(ctx.cwd);
		if (!root) return undefined;
		const local = path.join(root, "CLAUDE.local.md");
		let text: string;
		try {
			text = fs.readFileSync(local, "utf8").trim();
		} catch {
			return undefined;
		}
		if (!text) return undefined;
		event.systemPromptOptions.sections.paw_local_rules = text;
		return undefined;
	});
}
