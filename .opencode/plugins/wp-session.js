import { tool } from "@opencode-ai/plugin";
import {
  canonicalWpSessionTitle,
  chooseSessionCandidate,
  findWorkProduct,
  normalizeWpId,
  rankSessionCandidates,
} from "./wp-session-lib.js";

async function safeToast(client, directory, message, variant = "info") {
  try {
    await client.tui.showToast({ directory, message, variant });
  } catch {
    // Toasts are best-effort only.
  }
}

export const WpSessionPlugin = async ({ client, directory }) => {
  if (!client.tui.selectSession) {
    client.tui.selectSession = async ({ directory, sessionID }) => {
      await client.tui._client.post({
        url: "/tui/select-session",
        query: { directory },
        body: { sessionID },
        headers: { "Content-Type": "application/json" },
      });
    };
  }

  async function switchSession(dir, sessionID) {
    try {
      await client.tui.selectSession({ directory: dir, sessionID });
    } catch {
      await client.tui._client.post({
        url: "/tui/select-session",
        query: { directory: dir },
        body: { sessionID },
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  return {
    tool: {
      wp_session_switch: tool({
        description: "Find or create a work-product session and switch the OpenCode TUI to it",
        args: {
          wp: tool.schema.string().describe("Work-product identifier like WP-5, РП5, or 5"),
        },
        async execute(args, context) {
          const wpId = normalizeWpId(args.wp);
          if (!wpId) {
            await safeToast(client, context.directory, `Invalid work-product id: ${args.wp}`, "error");
            return {
              output: `Invalid work-product id: ${args.wp}`,
              metadata: { action: "invalid", input: args.wp },
            };
          }

          context.metadata({
            title: `Switch ${wpId}`,
            metadata: { wpId },
          });

          const wp = await findWorkProduct(directory, wpId);
          if (!wp) {
            const output = `${wpId} not found in MEMORY.md or WP-REGISTRY.md.`;
            await safeToast(client, context.directory, output, "error");
            return { output, metadata: { action: "missing-wp", wpId } };
          }

          const listResult = await client.session.list({
            directory: context.directory,
            roots: true,
            limit: 100,
          });
          const sessions = listResult.data ?? [];
          const ranked = rankSessionCandidates(sessions, wpId);
          const decision = chooseSessionCandidate(ranked);

          if (decision.action === "ambiguous") {
            const titles = decision.candidates.slice(0, 5).map((candidate) => candidate.session.title).join("; ");
            const output = `${wpId} is ambiguous across existing sessions: ${titles}`;
            await safeToast(client, context.directory, output, "warning");
            return {
              output,
              metadata: {
                action: "ambiguous",
                wpId,
                titles: decision.candidates.map((candidate) => candidate.session.title),
              },
            };
          }

          if (decision.action === "select") {
            const sessionID = decision.candidate.session.id;
            await switchSession(context.directory, sessionID);
            const output = `Switched to ${wpId} using existing session \"${decision.candidate.session.title}\".`;
            await safeToast(client, context.directory, output, "success");
            return {
              output,
              metadata: {
                action: "select",
                wpId,
                sessionID,
                title: decision.candidate.session.title,
              },
            };
          }

          const title = canonicalWpSessionTitle(wpId, wp.title);
          const createResult = await client.session.create({
            directory: context.directory,
            title,
          });
          const created = createResult.data;

          await switchSession(context.directory, created.id);
          const output = `Created and switched to ${wpId} with session \"${title}\".`;
          await safeToast(client, context.directory, output, "success");
          return {
            output,
            metadata: {
              action: "create",
              wpId,
              sessionID: created.id,
              title,
              source: wp.source,
            },
          };
        },
      }),
    },
  };
};

export default WpSessionPlugin;
