import { readFile } from "node:fs/promises";
import path from "node:path";

function normalizeWhitespace(value) {
  return value.replace(/\s+/g, " ").trim();
}

export function extractWpNumber(raw) {
  if (!raw) return null;
  const value = String(raw).trim();
  const patterns = [/^WP-(\d+)$/i, /^РП\s*(\d+)$/i, /^(\d+)$/];

  for (const pattern of patterns) {
    const match = value.match(pattern);
    if (match) return Number.parseInt(match[1], 10);
  }

  return null;
}

export function normalizeWpId(raw) {
  const number = extractWpNumber(raw);
  if (!Number.isInteger(number) || number <= 0) return null;
  return `WP-${number}`;
}

export function stripWpPrefix(title, wpId) {
  const number = extractWpNumber(wpId);
  if (!number) return normalizeWhitespace(title);

  const patterns = [
    new RegExp(`^${wpId}\\s*[:\\-]?\\s*`, "i"),
    new RegExp(`^РП\\s*${number}\\s*[:\\-]?\\s*`, "i"),
  ];

  let result = String(title);
  for (const pattern of patterns) {
    result = result.replace(pattern, "");
  }

  return normalizeWhitespace(result) || wpId;
}

export function canonicalWpSessionTitle(wpId, title) {
  return `${wpId}: ${stripWpPrefix(title, wpId)}`;
}

function parseMarkdownTableForWp(markdown, wpNumber) {
  const lines = String(markdown).split(/\r?\n/);

  for (const line of lines) {
    if (!line.startsWith("|")) continue;
    const cells = line.split("|").slice(1, -1).map((cell) => cell.trim());
    if (cells.length < 2) continue;
    if (cells[0] === "#" || cells[0] === "---") continue;

    const first = Number.parseInt(cells[0], 10);
    if (Number.isInteger(first) && first === wpNumber) {
      return {
        wpId: `WP-${wpNumber}`,
        title: cells[1],
      };
    }
  }

  return null;
}

async function readIfExists(filePath) {
  try {
    return await readFile(filePath, "utf8");
  } catch {
    return null;
  }
}

export async function resolveWorkspaceDir(rootDir) {
  return path.resolve(rootDir, "workspaces", "CURRENT_WORKSPACE");
}

export async function findWorkProduct(rootDir, wpId) {
  const wpNumber = extractWpNumber(wpId);
  if (!wpNumber) return null;

  const workspaceDir = await resolveWorkspaceDir(rootDir);
  const sources = [
    {
      name: "MEMORY.md",
      filePath: path.join(workspaceDir, "memory", "MEMORY.md"),
    },
    {
      name: "WP-REGISTRY.md",
      filePath: path.join(workspaceDir, "DS-strategy", "docs", "WP-REGISTRY.md"),
    },
  ];

  for (const source of sources) {
    const markdown = await readIfExists(source.filePath);
    if (!markdown) continue;

    const row = parseMarkdownTableForWp(markdown, wpNumber);
    if (row) {
      return {
        ...row,
        title: normalizeWhitespace(row.title),
        sessionTitle: canonicalWpSessionTitle(row.wpId, row.title),
        source: source.name,
        workspaceDir,
      };
    }
  }

  return null;
}

function titleScore(title, wpId) {
  const normalized = normalizeWhitespace(title).toLowerCase();
  const normalizedWp = wpId.toLowerCase();
  const wpNumber = extractWpNumber(wpId);
  const rp = wpNumber ? `рп${wpNumber}` : null;

  if (normalized.startsWith(`${normalizedWp}:`)) return 500;
  if (normalized === normalizedWp) return 480;
  if (normalized.startsWith(`${normalizedWp} `)) return 470;
  if (new RegExp(`^${normalizedWp}\\b`).test(normalized)) return 430;
  if (rp && new RegExp(`^${rp}\\b`).test(normalized)) return 320;
  if (normalized.includes(normalizedWp)) return 200;
  if (rp && normalized.includes(rp)) return 120;
  return 0;
}

export function rankSessionCandidates(sessions, wpId) {
  return sessions
    .map((session) => ({
      session,
      score: titleScore(session.title ?? "", wpId),
    }))
    .filter((candidate) => candidate.score > 0)
    .sort((left, right) => {
      if (right.score !== left.score) return right.score - left.score;
      return (right.session.time?.updated ?? 0) - (left.session.time?.updated ?? 0);
    });
}

export function chooseSessionCandidate(candidates) {
  if (candidates.length === 0) {
    return { action: "create" };
  }

  const [best, second] = candidates;
  if (best.score < 320) {
    return { action: "create" };
  }

  if (second && second.score === best.score) {
    return {
      action: "ambiguous",
      candidates: candidates.filter((candidate) => candidate.score === best.score),
    };
  }

  return { action: "select", candidate: best };
}
