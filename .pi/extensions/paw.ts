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

/** Run a hook of .claude/settings.json with the JSON of a Claude tool call. */
function runHook(script: string, payload: unknown, cwd: string, timeoutMs: number): Promise<HookResult> {
	return new Promise((resolve) => {
		const child = spawn(script, [], { cwd, timeout: timeoutMs, stdio: ["pipe", "pipe", "pipe"] });
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
		child.stdin?.on("error", () => {
			// The script can stop before it reads its input. Its result says why.
		});
		child.stdin?.end(JSON.stringify(payload));
	});
}

function notify(ctx: ExtensionContext, message: string, type: "info" | "warning" | "error"): void {
	if (ctx.hasUI) ctx.ui.notify(message, type);
}

function hookFailure(name: string, result: HookResult): string {
	const reason = result.stderr.trim() || (result.signal ? `the signal ${result.signal}` : `the exit code ${result.code}`);
	return `${name} did not run: ${reason}`;
}

export default function paw(pi: ExtensionAPI) {
	pi.on("session_start", async () => {
		// The env block of .claude/settings.json gives this value to Claude Code.
		process.env.PAW_SUITE_LOCKS = SUITE_LOCKS;
		try {
			fs.mkdirSync(SUITE_LOCKS, { recursive: true });
		} catch {
			// tests/tools/suite.sh makes the folder itself when it can.
		}
	});

	pi.on("tool_call", async (event, ctx) => {
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
			return { content: [...event.content, { type: "text" as const, text: result.stderr.trim() }] };
		}
		if (result.code !== 0) notify(ctx, hookFailure("tools/vale-hook.sh", result), "warning");
		return undefined;
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
