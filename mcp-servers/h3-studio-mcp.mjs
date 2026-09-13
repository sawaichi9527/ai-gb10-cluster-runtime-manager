#!/usr/bin/env node
// h3-studio-mcp — zero-dependency MCP server for Node1 MiniMax-H3 (vLLM-Omni) video generation.
// Protocol: MCP JSON-RPC 2.0 over stdio. Node >= 20 (needs global fetch).
// Config via env: H3_BASE_URL, H3_API_KEY, H3_OUTPUT_DIR.
// HARD RULE: tool results contain TEXT metadata only — video bytes are streamed to disk, never
// embedded in a tool result (avoids token waste regardless of client model).

import { Readable, Transform } from "node:stream";
import { createWriteStream, mkdirSync } from "node:fs";
import { stat } from "node:fs/promises";
import { createHash, randomUUID } from "node:crypto";
import { setTimeout as sleep } from "node:timers/promises";
import { Buffer } from "node:buffer";
import { join as joinPath } from "node:path";

const BASE = (process.env.H3_BASE_URL || "http://192.168.23.216:8000").replace(/\/+$/, "");
const API_KEY = process.env.H3_API_KEY || "";
const OUT_DIR = process.env.H3_OUTPUT_DIR || "output";
const REQUEST_TIMEOUT_MS = 600_000; // per H3 API call (cold start handled by polling, not this)
const SERVER_NAME = "h3-studio-mcp";

mkdirSync(OUT_DIR, { recursive: true });

// ---------- HTTP helpers ----------

function authHeaders(extra = {}) {
  const h = { ...extra };
  if (API_KEY) h.Authorization = `Bearer ${API_KEY}`;
  return h;
}

async function h3Json(path, init = {}, timeoutMs = REQUEST_TIMEOUT_MS) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${BASE}${path}`, { ...init, headers: authHeaders(init.headers), signal: ctrl.signal });
    if (!res.ok) {
      let bodyText = "";
      try { bodyText = (await res.text()).slice(0, 2000); } catch { /* ignore */ }
      throw new Error(`H3 ${path} -> HTTP ${res.status}: ${bodyText}`);
    }
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

async function* streamPump(res) {
  if (!res.body) throw new Error("no response body");
  let pending = "";
  for await (const chunk of res.body) {
    const text = Buffer.isBuffer(chunk) ? chunk.toString("utf8") : chunk.toString("utf8");
    pending += text;
  }
  if (pending.length) yield pending;
}

// H3 async generation uses multipart/form-data (same fields as /videos/sync).
// Build the body manually so we stay zero-dependency.
function multipartBody(fields) {
  const boundary = `----h3studio${randomUUID().replace(/-/g, "")}`;
  const parts = [];
  for (const [k, v] of Object.entries(fields)) {
    if (v === undefined || v === null) continue;
    parts.push(`--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`);
  }
  parts.push(`--${boundary}--\r\n`);
  return {
    body: Buffer.from(parts.join(""), "utf8"),
    contentType: `multipart/form-data; boundary=${boundary}`,
  };
}

function buildVideoFields(args) {
  const fields = {};
  const map = {
    prompt: "prompt", model: "model", user: "user",
    width: "width", height: "height", num_frames: "num_frames", fps: "fps",
    num_inference_steps: "num_inference_steps", guidance_scale: "guidance_scale",
    guidance_scale_2: "guidance_scale_2", boundary_ratio: "boundary_ratio",
    flow_shift: "flow_shift", true_cfg_scale: "true_cfg_scale", seed: "seed",
    seconds: "seconds", size: "size", negative_prompt: "negative_prompt",
    generate_sound: "generate_sound", sound_duration: "sound_duration",
    enable_frame_interpolation: "enable_frame_interpolation",
    frame_interpolation_exp: "frame_interpolation_exp",
    frame_interpolation_scale: "frame_interpolation_scale",
  };
  for (const [k, v] of Object.entries(map)) {
    if (args[k] !== undefined && args[k] !== null) fields[v] = String(args[k]);
  }
  // extra_params must be a JSON string for t2va audio.
  const ep = {};
  if (args.task) ep.task = args.task;
  if (args.duration !== undefined) ep.duration = args.duration;
  if (args.audio_flow_shift !== undefined) ep.audio_flow_shift = args.audio_flow_shift;
  if (args.generate_audio !== undefined) ep.generate_audio = args.generate_audio;
  if (args.lora !== undefined && args.lora !== null) fields.lora = JSON.stringify(args.lora);
  if (Object.keys(ep).length) fields.extra_params = JSON.stringify(ep);
  return fields;
}

function statusSummary(r) {
  const id = r.id || "?";
  const st = r.status ?? "unknown";
  const out = {
    video_id: id,
    status: st,
    progress: r.progress ?? null,
    created_at: r.created_at ?? null,
    completed_at: r.completed_at ?? null,
    inference_time_s: r.inference_time_s ?? null,
    file_name: r.file_name ?? null,
    media_type: r.media_type ?? null,
    error: r.error ?? null,
  };
  return out;
}

function validateReply(status, fields) {
  return JSON.stringify({ ok: true, status, ...fields });
}

// ---------- MCP scaffolding ----------

const TOOLS = [
  {
    name: "generate_video_async",
    description: "Submit a text-to-video generation job to MiniMax-H3 (async). Returns video_id immediately; poll with get_video_status. Prompt is required. Model defaults to the server's loaded H3 FL2VA model.",
    inputSchema: {
      type: "object",
      properties: {
        prompt: { type: "string", description: "Text prompt describing the video (required)" },
        width: { type: "number", description: "Frame width (default 768)" },
        height: { type: "number", description: "Frame height (default 448)" },
        num_inference_steps: { type: "number", description: "Steps (default 20)" },
        flow_shift: { type: "number", description: "Flow shift (default 12)" },
        seed: { type: "number", description: "Random seed (default 42)" },
        fps: { type: "number", description: "Frames per second (default 24)" },
        task: { type: "string", description: "Task type, e.g. t2va (default t2va)" },
        duration: { type: "number", description: "Video duration in seconds (default 2.0)" },
        audio_flow_shift: { type: "number", description: "Audio flow shift (default 3.0)" },
        generate_audio: { type: "boolean", description: "Whether to generate audio (default true)" },
        negative_prompt: { type: "string" },
        model: { type: "string", description: "Override model id" },
      },
      required: ["prompt"],
    },
  },
  {
    name: "list_video_jobs",
    description: "List video generation jobs known to the H3 server.",
    inputSchema: {
      type: "object",
      properties: {
        limit: { type: "number", description: "Max jobs to return (default 20)" },
      },
    },
  },
  {
    name: "get_video_status",
    description: "Get status of a single video generation job by video_id.",
    inputSchema: {
      type: "object",
      properties: { video_id: { type: "string", description: "Video id returned by generate_video_async" } },
      required: ["video_id"],
    },
  },
  {
    name: "download_video",
    description: "Download a completed video's mp4 bytes to the local H3_OUTPUT_DIR and return local path + size + sha256 (text metadata only, no bytes).",
    inputSchema: {
      type: "object",
      properties: { video_id: { type: "string", description: "Video id" } },
      required: ["video_id"],
    },
  },
  {
    name: "generate_video",
    description: "Convenience: submit + poll to completion + download. Equivalent to generate_video_async then get_video_status until completed then download_video. Returns local file metadata. Note: on opencode the per-tool client timeout (mcp_timeout=180s) may abort this for cold starts; prefer the 3-step flow there.",
    inputSchema: {
      type: "object",
      properties: {
        prompt: { type: "string", description: "Text prompt (required)" },
        width: { type: "number" }, height: { type: "number" },
        num_inference_steps: { type: "number" }, flow_shift: { type: "number" },
        seed: { type: "number" }, fps: { type: "number" },
        task: { type: "string" }, duration: { type: "number" },
        audio_flow_shift: { type: "number" }, generate_audio: { type: "boolean" },
        max_poll_s: { type: "number", description: "Max total poll time in seconds (default 900)" },
        poll_interval_s: { type: "number", description: "Poll interval in seconds (default 10)" },
      },
      required: ["prompt"],
    },
  },
];

// ---------- tool implementations ----------

async function callGenerateVideoAsync(args) {
  if (!args.prompt || !String(args.prompt).trim()) throw new Error("prompt is required");
  const fields = buildVideoFields({
    ...args,
    task: args.task || "t2va",
    duration: args.duration ?? 2.0,
    audio_flow_shift: args.audio_flow_shift ?? 3.0,
    width: args.width ?? 768,
    height: args.height ?? 448,
    num_inference_steps: args.num_inference_steps ?? 20,
    flow_shift: args.flow_shift ?? 12,
    seed: args.seed ?? 42,
    fps: args.fps ?? 24,
  });
  const m = multipartBody(fields);
  const res = await fetch(`${BASE}/v1/videos`, {
    method: "POST",
    headers: authHeaders({ "Content-Type": m.contentType }),
    body: m.body,
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  if (!res.ok) {
    let bodyText = "";
    try { bodyText = (await res.text()).slice(0, 2000); } catch { /* ignore */ }
    throw new Error(`POST /v1/videos -> HTTP ${res.status}: ${bodyText}`);
  }
  const data = await res.json();
  const summary = statusSummary(data);
  summary.submitted_prompt = fields.prompt;
  summary.base_url = BASE;
  return validateReply("submitted", summary);
}

async function callListVideoJobs(args) {
  const r = await h3Json("/v1/videos");
  const data = (r.data || []).slice(0, Number(args.limit ?? 20));
  return validateReply("ok", {
    count: data.length,
    has_more: r.has_more ?? false,
    first_id: r.first_id ?? null,
    last_id: r.last_id ?? null,
    jobs: data.map(statusSummary),
  });
}

async function callGetVideoStatus(args) {
  if (!args.video_id) throw new Error("video_id is required");
  const r = await h3Json(`/v1/videos/${encodeURIComponent(args.video_id)}`);
  return validateReply("ok", statusSummary(r));
}

async function callDownloadVideo(args) {
  if (!args.video_id) throw new Error("video_id is required");
  const vid = encodeURIComponent(args.video_id);

  // sanity: ensure job exists and is completed
  let meta;
  try {
    meta = await h3Json(`/v1/videos/${vid}`);
  } catch (e) {
    throw new Error(`video not found: ${e.message}`);
  }
  if (meta.status !== "completed") {
    throw new Error(`video ${args.video_id} not ready (status=${meta.status}); poll get_video_status first`);
  }

  const res = await fetch(`${BASE}/v1/videos/${vid}/content`, {
    headers: authHeaders(),
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  if (!res.ok) {
    let bodyText = "";
    try { bodyText = (await res.text()).slice(0, 2000); } catch { /* ignore */ }
    throw new Error(`GET /content -> HTTP ${res.status}: ${bodyText}`);
  }
  const ctype = res.headers.get("content-type") || "";
  const isJson = ctype.includes("application/json") || ctype.includes("text/");

  const base = args.video_id.replace(/[^A-Za-z0-9._-]/g, "_");
  const fname = `${base}.mp4`;
  const absPath = joinPath(OUT_DIR, fname);
  const hash = createHash("sha256");
  const hasher = new Transform({
    transform(chunk, _enc, cb) { hash.update(chunk); cb(null, chunk); },
  });
  const w = createWriteStream(absPath);

  const writeStreamChecked = (body) =>
    new Promise((resolve, reject) => {
      const nodeBody = body instanceof Readable ? body : Readable.fromWeb(body);
      nodeBody.pipe(hasher).pipe(w);
      w.on("finish", resolve);
      w.on("error", reject);
      hasher.on("error", reject);
      nodeBody.on("error", reject);
    });

  if (isJson) {
    // Content endpoint may return JSON (e.g., {url:...}) on some builds — resolve and follow.
    const resBuf = Buffer.from(await res.arrayBuffer());
    let parsed;
    try { parsed = JSON.parse(resBuf.toString("utf8")); } catch { parsed = null; }
    let target = parsed?.url;
    if (!target) throw new Error(`content returned JSON without url: ${resBuf.toString("utf8").slice(0,1000)}`);
    let u = target;
    if (/^https?:\/\//i.test(u) === false) u = `${BASE}${u.startsWith("/") ? "" : "/"}${u}`;
    const res2 = await fetch(u, {
      headers: authHeaders(),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    if (!res2.ok) throw new Error(`follow content url -> HTTP ${res2.status}`);
    await writeStreamChecked(res2.body);
  } else {
    // raw mp4 bytes
    await writeStreamChecked(res.body);
  }
  const sha = hash.digest("hex");
  const size = (await stat(absPath)).size;

  return validateReply("downloaded", {
    video_id: args.video_id,
    file_path: absPath,
    size_bytes: size,
    sha256: sha,
    note: "bytes written to disk; not embedded in result",
  });
}

async function callGenerateVideo(args) {
  const submit = await callGenerateVideoAsync(args);
  const videoId = submit.video_id;
  const maxPoll = Number(args.max_poll_s ?? 900);
  const interval = Number(args.poll_interval_s ?? 10);
  const started = Date.now();
  let state = null;
  while (Date.now() - started < maxPoll * 1000) {
    const r = await h3Json(`/v1/videos/${encodeURIComponent(videoId)}`);
    state = statusSummary(r);
    if (state.status === "completed") {
      const dl = await callDownloadVideo({ video_id: videoId });
      dl.video_id = videoId;
      dl.poll_elapsed_s = ((Date.now() - started) / 1000).toFixed(1);
      return validateReply("completed", dl);
    }
    if (state.status === "failed") {
      return validateReply("failed", state);
    }
    await sleep(interval * 1000);
  }
  return validateReply("timeout_polling", {
    video_id: videoId,
    state,
    note: "still queued/in_progress; use get_video_status then download_video",
  });
}

const HANDLERS = {
  generate_video_async: callGenerateVideoAsync,
  list_video_jobs: callListVideoJobs,
  get_video_status: callGetVideoStatus,
  download_video: callDownloadVideo,
  generate_video: callGenerateVideo,
};

// ---------- stdio transport ----------

async function main() {
  const stdin = process.stdin;
  let buf = "";
  const out = (obj) => process.stdout.write(JSON.stringify(obj) + "\n");
  const log = (msg) => process.stderr.write(`[${SERVER_NAME}] ${msg}\n`);

  stdin.on("data", (chunk) => {
    buf += chunk.toString("utf8");
    let idx;
    while ((idx = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, idx).trim();
      buf = buf.slice(idx + 1);
      if (!line) continue;
      let msg;
      try { msg = JSON.parse(line); } catch (e) {
        log(`bad JSON: ${line.slice(0,200)}`);
        continue;
      }
      (async () => {
        if (msg.method === "initialize") {
          out({
            jsonrpc: "2.0",
            id: msg.id,
            result: {
              protocolVersion: msg.params?.protocolVersion || "2025-03-26",
              capabilities: { tools: { listChanged: false } },
              serverInfo: { name: SERVER_NAME, version: "0.1.0" },
            },
          });
          return;
        }
        if (msg.method === "notifications/initialized") return;
        if (msg.method === "ping") { out({ jsonrpc: "2.0", id: msg.id, result: {} }); return; }
        if (msg.method === "tools/list") {
          out({ jsonrpc: "2.0", id: msg.id, result: { tools: TOOLS } });
          return;
        }
        if (msg.method === "tools/call") {
          const name = msg.params?.name;
          const args = msg.params?.arguments || {};
          const handler = HANDLERS[name];
          let result;
          let isError = false;
          try {
            if (!handler) throw new Error(`unknown tool: ${name}`);
            const text = await handler(args);
            result = { content: [{ type: "text", text }] };
          } catch (e) {
            isError = true;
            log(`tool ${name} error: ${e.message}`);
            result = { content: [{ type: "text", text: `ERROR: ${e.message}` }], isError: true };
          }
          out({ jsonrpc: "2.0", id: msg.id, result });
          return;
        }
        // unknown method -> error response
        out({
          jsonrpc: "2.0",
          id: msg.id ?? null,
          error: { code: -32601, message: `method not found: ${msg.method}` },
        });
      })().catch((e) => {
        log(`unhandled: ${e.stack || e.message}`);
        out({ jsonrpc: "2.0", id: msg.id ?? null, error: { code: -32603, message: e.message } });
      });
    }
  });
}

main().catch((e) => {
  process.stderr.write(`[${SERVER_NAME}] fatal: ${e.stack || e.message}\n`);
  process.exit(1);
});