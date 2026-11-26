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
import { Type } from "typebox";
import { installAgentTrace, TICKET_PREFIX } from "../lib/agent-trace.ts";

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
		if (comment && looksLikeNarration(comment)) findings.push(`L${line.number}: ${comment}`);
	}
	return findings;
}

function looksLikeNarration(comment: string): boolean {
	const text = comment.replace(/^(?:\/\/|\/\*|--|#|;|\*)\s*/, "");
	return /^(?:[-=#*]{3,}|this (?:function|method|loop)\b|(?:get|set|return|call|increment|decrement|initialize)\b|(?:if|for|while)\s*\(|(?:let|const|local)\s+\w+\s*=)/i.test(text);
}

const PAW_IMPLEMENTERS = new Set(["paw-builder", "paw-worker"]);
const AGENT_TIMEOUT_MS = 30_000;
const TICKET_TIMEOUT_MS = 5_000;

interface SkillInfo {
	name: string;
	description: string;
	filePath: string;
	baseDir: string;
	disableModelInvocation: boolean;
}

async function ticketTitle(root: string, ticket: string): Promise<string | undefined> {
	const result = await runProcess("backlog", ["task", ticket, "--plain"], undefined, root, TICKET_TIMEOUT_MS);
	if (result.code !== 0) return undefined;
	return result.stdout.match(/^Task TASK-\d+(?:\.\d+)* - (.+)$/m)?.[1]?.trim();
}

/** Put the ticket and its title in the agent description that the UI shows. */
async function labelAgentDescription(root: string, ticket: string, summary: string): Promise<string> {
	const title = await ticketTitle(root, ticket);
	const caption = [title?.slice(0, 70), summary].filter(Boolean).join(" | ");
	return `TASK-${ticket}: ${caption}`.trimEnd();
}

/**
 * Label an agent with its ticket, and refuse a builder or a worker whose
 * type disagrees with the `agent:` label. The type comes from the label
 * (`.orchestrator/agent-for.sh`), so the orchestrator cannot start a worker
 * on a builder ticket by mistake. A spawn with no ticket passes.
 */
async function guardAgent(event: { input: Record<string, unknown> }, ctx: ExtensionContext) {
	const input = event.input;
	if (typeof input.description !== "string" || input.resume) return undefined;
	const description = input.description;
	const type = typeof input.subagent_type === "string" ? input.subagent_type.toLowerCase() : "";
	const root = repoRoot(ctx.cwd);
	if (!root) return undefined;
	const match = TICKET_PREFIX.exec(description);
	if (!match) {
		const prompt = typeof input.prompt === "string" ? input.prompt : "";
		if (PAW_IMPLEMENTERS.has(type) && /\b(?:TASK-|ticket\s+)\d/i.test(`${description}\n${prompt}`)) {
			return { block: true, reason: "Start the agent description with TASK-<id>: to assign the Backlog ticket." };
		}
		return undefined;
	}
	const ticket = match[1].slice("TASK-".length);
	const refusal = PAW_IMPLEMENTERS.has(type) ? await checkAgentRole(root, ticket, type) : undefined;
	if (refusal) return refusal;
	input.description = await labelAgentDescription(root, ticket, description.slice(match[0].length));
	return undefined;
}

async function checkAgentRole(root: string, ticket: string, type: string) {
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

/**
 * The upstream provider of OpenRouter that serves a family of models, by the
 * prefix of the model id. Only a family with a provider of its own goes here.
 * DeepSeek serves its models through other providers, and the session affinity
 * headers of the model keep one of them for the session.
 */
const UPSTREAM: Record<string, string> = {
	"openai/": "openai",
};

/**
 * Keep each request of a pinned model on one upstream provider of
 * OpenRouter, and on no other. A split backend loses the prompt cache.
 * A model without an entry keeps the routing of OpenRouter.
 */
function pinOpenRouterProvider(pi: ExtensionAPI): void {
	pi.on("before_provider_request", (event, ctx) => {
		if (ctx.model?.provider !== "openrouter") return;
		const payload = event.payload as { model?: unknown; provider?: unknown } | undefined;
		if (!payload || typeof payload !== "object") return;
		const model = payload.model;
		if (typeof model !== "string") return;
		const entry = Object.keys(UPSTREAM).find((prefix) => model.startsWith(prefix));
		if (!entry) return;
		return { ...payload, provider: { only: [UPSTREAM[entry]], allow_fallbacks: false } };
	});
}

export default function paw(pi: ExtensionAPI) {
	pinOpenRouterProvider(pi);
	installAgentTrace(pi);
	const skillIndex = new Map<string, SkillInfo>();
	pi.registerTool({
		name: "Skill",
		label: "Load a skill",
		description:
			"Load a skill by name and return its instructions (SKILL.md). Use it when a prompt says 'Call the Skill tool with <name>'. A skill that names another skill is loaded the same way. Files that the skill names are relative to the folder in the result.",
		parameters: Type.Object({
			name: Type.String({ description: "The exact skill name, for example code-review or retro." }),
		}),
		execute: async (_toolCallId, params) => {
			const key = params.name.trim().toLowerCase();
			const skill = skillIndex.get(key) ?? skillIndex.get(key.replace(/^.*:/, ""));
			if (!skill) {
				const names = [...skillIndex.keys()].sort().join(", ");
				return {
					content: [{ type: "text" as const, text: `No skill named ${params.name}. Available skills: ${names}` }],
					details: undefined,
					isError: true,
				};
			}
			let text: string;
			try {
				text = fs.readFileSync(skill.filePath, "utf8");
			} catch {
				return {
					content: [{ type: "text" as const, text: `Cannot read the skill file of ${skill.name}.` }],
					details: undefined,
					isError: true,
				};
			}
			return {
				content: [{ type: "text" as const, text: `Skill ${skill.name} (folder: ${skill.baseDir})\n\n${text}` }],
				details: { name: skill.name, baseDir: skill.baseDir },
			};
		},
	});
	pi.on("session_start", () => {
		// The env block of .claude/settings.json gives this value to Claude Code.
		const locks = process.env.PAW_SUITE_LOCKS ??= SUITE_LOCKS;
		try {
			fs.mkdirSync(locks, { recursive: true });
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
			notify(ctx, `no-comments: ${comments.length} review candidate(s) in ${filePath}`, "warning");
			notices.push(
				`no-comments: ${comments.length} review candidate(s) in ${filePath}:\n  ${shown.join("\n  ")}${more}\n` +
					"Review these candidates for narration or dead code. Keep comments that explain a non-obvious reason; see CODING_STANDARDS.md.",
			);
		}
		if (notices.length === 0) return undefined;
		return {
			content: [...event.content, ...notices.map((text) => ({ type: "text" as const, text }))],
		};
	});

	pi.on("before_agent_start", (event, ctx) => {
		const skills = (event.systemPromptOptions.skills ?? []) as SkillInfo[];
		skillIndex.clear();
		for (const skill of skills) skillIndex.set(skill.name.toLowerCase(), skill);
		const hidden = skills.filter((skill) => skill.disableModelInvocation).map((skill) => skill.name);
		if (hidden.length > 0) {
			event.systemPromptOptions.sections.paw_hidden_skills =
				`These skills are not auto-selected. Load one with the Skill tool by name: ${hidden.join(", ")}.`;
		} else {
			delete event.systemPromptOptions.sections.paw_hidden_skills;
		}
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
