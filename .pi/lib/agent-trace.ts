import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

export const TICKET_PREFIX = /^(TASK-\d+(?:\.\d+)*):(?:\s+|$)/i;

interface SubagentInfo {
	id: string;
	type: string;
	description: string;
	depth: number;
}

/** Show the ticket of each running agent in the footer. */
function renderAgentStatus(ctx: ExtensionContext | undefined, runningAgents: Map<string, SubagentInfo>): void {
	if (!ctx || !ctx.hasUI || ctx.mode !== "tui") return;
	const agents = [...runningAgents.values()];
	if (agents.length === 0) {
		ctx.ui.setStatus("paw:agents", undefined);
		return;
	}
	const shown = agents.slice(0, 3).map((agent) => {
		const ticket = TICKET_PREFIX.exec(agent.description)?.[1];
		return ticket ? `${ticket} ${agent.type.replace(/^paw-/, "")}` : agent.type;
	});
	const more = agents.length > shown.length ? ` +${agents.length - shown.length}` : "";
	ctx.ui.setStatus("paw:agents", `paw: ${shown.join(" | ")}${more}`);
}

/** Show the ticket of each running agent in the footer. */
export function installAgentTrace(pi: ExtensionAPI): void {
	const runningAgents = new Map<string, SubagentInfo>();
	let uiCtx: ExtensionContext | undefined;
	const render = () => renderAgentStatus(uiCtx, runningAgents);
	const onSubagent = (data: unknown): void => {
		const info = data as SubagentInfo | undefined;
		if (info?.depth !== 1) return;
		if (typeof info.id !== "string" || typeof info.type !== "string" || typeof info.description !== "string") return;
		runningAgents.set(info.id, info);
		render();
	};
	const offSubagent = (data: unknown): void => {
		const id = (data as { id?: unknown } | undefined)?.id;
		if (typeof id !== "string") return;
		runningAgents.delete(id);
		render();
	};
	pi.events.on("subagents:created", onSubagent);
	pi.events.on("subagents:started", onSubagent);
	pi.events.on("subagents:completed", offSubagent);
	pi.events.on("subagents:failed", offSubagent);
	pi.on("session_start", (_event, ctx) => {
		uiCtx = ctx;
		runningAgents.clear();
		render();
	});
	pi.on("session_shutdown", () => {
		if (uiCtx?.hasUI && uiCtx.mode === "tui") uiCtx.ui.setStatus("paw:agents", undefined);
		runningAgents.clear();
		uiCtx = undefined;
	});
}
