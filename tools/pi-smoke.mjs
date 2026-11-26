import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { EventEmitter, once } from "node:events";
import { installAgentTrace } from "../.pi/lib/agent-trace.ts";

const checkout = fileURLToPath(new URL("../", import.meta.url));
const packages = join(checkout, ".pi", "npm", "node_modules");
const extensions = ["@tintinweb/pi-subagents/src/index.ts", "pi-cache-optimizer/index.ts"].map((entry) => join(packages, entry));
assert.ok(extensions.every(existsSync), "Install the Pi project packages before you run the smoke test.");
const scratch = mkdtempSync(join(tmpdir(), "paw-pi-smoke-"));
const repo = join(scratch, "repo");
const home = join(scratch, "home");
const agentDir = join(home, ".pi", "agent");
const model = "deepseek/deepseek-v4.1-flash-1017";
const ticket = "41.2";
const ticketLabel = `TASK-${ticket}: Child ticket | Review code`;
const scoutTicket = "42";
const failure = [];
const env = {
	PATH: process.env.PATH,
	HOME: home,
	XDG_CONFIG_HOME: join(home, ".config"),
	XDG_CACHE_HOME: join(home, ".cache"),
	XDG_DATA_HOME: join(home, ".local", "share"),
	TMPDIR: scratch,
	PI_CODING_AGENT_DIR: agentDir,
	PI_OFFLINE: "1",
	PAW_SUITE_LOCKS: join(scratch, "locks"),
	OPENROUTER_API_KEY: "local-fixture",
	GIT_CONFIG_NOSYSTEM: "1",
	GIT_AUTHOR_NAME: "Pi Smoke",
	GIT_AUTHOR_EMAIL: "smoke@example.invalid",
	GIT_COMMITTER_NAME: "Pi Smoke",
	GIT_COMMITTER_EMAIL: "smoke@example.invalid",
};

function put(path, value, mode) {
	mkdirSync(join(path, ".."), { recursive: true });
	writeFileSync(path, value, { mode });
}

function git(...args) {
	return execFileSync("git", args, { cwd: repo, env, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

function call(name, args, id = name, index = 0) {
	return { index, id, type: "function", function: { name, arguments: JSON.stringify(args) } };
}

function checkFooter() {
	const events = new EventEmitter();
	const hooks = new EventEmitter();
	let status;
	installAgentTrace({ events, on: hooks.on.bind(hooks) });
	hooks.emit("session_start", {}, { hasUI: true, mode: "tui", ui: { setStatus: (_key, value) => { status = value; } } });
	const worker = { id: "worker", type: "paw-worker", description: ticketLabel, depth: 1 };
	const scout = { id: "scout", type: "paw-scout", description: `TASK-${scoutTicket}: Locate code`, depth: 1 };
	events.emit("subagents:started", worker);
	events.emit("subagents:created", scout);
	assert.equal(status, `paw: TASK-${ticket} worker | TASK-${scoutTicket} scout`);
	events.emit("subagents:completed", worker);
	assert.equal(status, `paw: TASK-${scoutTicket} scout`);
	events.emit("subagents:failed", scout);
	assert.equal(status, undefined);
}

function responseFor(body) {
	assert.equal(body.model, model);
	// The default model has no provider of its own, so it keeps the routing of OpenRouter.
	assert.equal(body.provider, undefined);
	const tools = body.tools?.map((tool) => tool.function.name) ?? [];
	const text = JSON.stringify(body.messages);
	const next = body.messages.at(-1);
	const root = tools.includes("Agent");
	if (root && next.role !== "tool") {
		assert.match(JSON.stringify(next.content), /Explicit retro fixture instructions/);
		return { tool_calls: [
			call("Agent", { subagent_type: "paw-worker", run_in_background: false,
				description: `TASK-${ticket}: Review code`, prompt: "Read the review skill and report the checkout." }, "worker", 0),
			call("Agent", { subagent_type: "paw-scout", run_in_background: false,
				description: `TASK-${scoutTicket}: Locate code`, prompt: "Locate code." }, "scout", 1),
		] };
	}
	if (root) {
		if (next.tool_call_id !== "comment-check") {
			return { tool_calls: [call("write", { path: "sample.ts", content:
				"// Set the result\nconst result = 1;\n// The remote protocol reserves zero for errors.\n" }, "comment-check")] };
		}
		assert.match(next.content, /review candidate.*\n +L1: \/\/ Set the result/);
		assert.doesNotMatch(next.content, /reserves zero/);
		assert.match(next.content, /Keep comments/);
		return { content: "smoke complete" };
	}
	if (body.messages[0].content.includes('<active_agent name="paw-scout"/>')) return { content: "scout complete" };
	assert.ok(tools.includes("Skill"), "The isolated worker must have the Skill tool");
	if (next.role !== "tool") return { tool_calls: [call("Skill", { name: "code-review" }), call("bash", { command: "pwd" }, "cwd", 1)] };
	assert.match(text, /Review skill fixture instructions/);
	const cwd = body.messages.find((msg) => msg.role === "tool" && msg.tool_call_id === "cwd");
	assert.ok(cwd?.content.startsWith(join(scratch, "pi-agent-")), JSON.stringify(cwd));
	return { content: "worker complete" };
}

const server = createServer(async (req, res) => {
	try {
		assert.equal(req.url, "/v1/chat/completions");
		let data = "";
		for await (const chunk of req) data += chunk;
		const delta = responseFor(JSON.parse(data));
		const event = { id: "fixture", model, choices: [{ index: 0, delta: { role: "assistant", ...delta },
			finish_reason: delta.tool_calls ? "tool_calls" : "stop" }] };
		res.writeHead(200, { "Content-Type": "text/event-stream" });
		res.end(`data: ${JSON.stringify(event)}\n\ndata: [DONE]\n\n`);
	} catch (error) {
		failure.push(error);
		res.writeHead(400);
		res.end("Smoke fixture assertion failed");
	}
});

try {
	checkFooter();
	server.listen(0, "127.0.0.1");
	await once(server, "listening");
	for (const path of [".pi/extensions/paw.ts", ".pi/lib/agent-trace.ts", ".pi/agents/paw-worker.md", ".pi/agents/paw-scout.md", "tools/guard-hook.py"]) {
		mkdirSync(join(repo, path, ".."), { recursive: true });
		cpSync(join(checkout, path), join(repo, path));
	}
	put(join(repo, ".pi/settings.json"), JSON.stringify({ defaultProvider: "openrouter", defaultModel: model, extensions }));
	put(join(repo, ".pi/subagents.json"), JSON.stringify({ workflowsEnabled: false, rememberAgents: false, outputTranscript: false }));
	put(join(agentDir, "models.json"), JSON.stringify({ providers: { openrouter: {
		baseUrl: `http://127.0.0.1:${server.address().port}/v1`, api: "openai-completions",
		models: [{ id: model, reasoning: true }],
	} } }));
	put(join(agentDir, "skills/retro/SKILL.md"), "---\nname: retro\ndescription: Run a retrospective.\ndisable-model-invocation: true\n---\nExplicit retro fixture instructions\n");
	put(join(agentDir, "skills/code-review/SKILL.md"), "---\nname: code-review\ndescription: Review changes.\n---\nReview skill fixture instructions\n");
	put(join(repo, ".orchestrator/agent-for.sh"), `#!/bin/sh\n[ "$1" = '${ticket}' ] && echo paw-worker\n`, 0o755);
	put(join(scratch, "bin/backlog"), `#!/bin/sh\ncase "$2" in\n  ${ticket}) title='Child ticket' ;;\n  ${scoutTicket}) title='Other ticket' ;;\n  *) exit 1 ;;\nesac\nprintf 'Task TASK-%s - %s\\n' "$2" "$title"\n`, 0o755);
	env.PATH = `${join(scratch, "bin")}:${env.PATH}`;
	git("init", "-q");
	git("add", ".");
	git("commit", "-qm", "Smoke fixture");

	const child = spawn("pi", ["--approve", "--no-mcp", "--no-session", "--mode", "rpc"], {
		cwd: repo, env, stdio: ["pipe", "pipe", "pipe"], timeout: 60_000,
	});
	const exit = once(child, "close");
	child.stdin.on("error", () => {});
	let stderr = "";
	child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
	child.stdin.write(JSON.stringify({ type: "prompt", message: "/skill:retro" }) + "\n");
	let pending = "";
	const records = [];
	try {
		for await (const chunk of child.stdout.setEncoding("utf8")) {
			pending += chunk;
			const lines = pending.split("\n");
			pending = lines.pop();
			for (const line of lines) {
				const record = JSON.parse(line);
				records.push(record);
				if (record.type === "agent_settled" || (record.type === "response" && !record.success)) child.stdin.end();
			}
		}
	} finally {
		child.stdin.end();
	}
	assert.equal((await exit)[0], 0, stderr);
	if (failure.length) throw failure[0];
	assert.ok(records.some((r) => r.type === "agent_settled"), stderr);
	assert.ok(!records.some((r) => r.type === "extension_error"), stderr);
	assert.ok(records.some((r) => r.type === "message_end" && JSON.stringify(r.message.content).includes("smoke complete")), stderr);
	const agents = records.filter((r) => r.type === "tool_execution_end" && r.toolName === "Agent");
	assert.equal(agents.length, 2);
	assert.ok(agents.every((r) => !r.isError), JSON.stringify(agents));
	const output = JSON.stringify(agents);
	assert.ok(output.includes(ticketLabel) && output.includes("worker complete"), output);
	assert.ok(output.includes(`TASK-${scoutTicket}: Other ticket | Locate code`) && output.includes("scout complete"), output);
	console.log("Pi smoke: skills, worktree, ticket labels, footer, comment advice and wire route pass");
} finally {
	server.close();
	rmSync(scratch, { recursive: true, force: true });
}
