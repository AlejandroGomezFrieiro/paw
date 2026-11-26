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
const COMMENT_TIMEOUT_MS = 30_000;
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
		const comments = await runHook(
			path.join(root, "tools", "comment-hook.py"),
			{ tool_input: { file_path: absolute }, tool_response: { filePath: absolute, patch } },
			root,
			COMMENT_TIMEOUT_MS,
		);
		if (comments.code === 2 && comments.stderr.trim()) {
			notify(ctx, `no-comments: comments in ${filePath}`, "warning");
			notices.push(comments.stderr.trim());
		} else if (comments.code !== 0) {
			notify(ctx, hookFailure("tools/comment-hook.py", comments), "warning");
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
