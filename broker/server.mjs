import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { createServer } from "node:http";
import { Readable, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";

const port = Number(process.env.PORT || 8787);
const selfTest = process.argv.includes("--self-test");

function normalizePublicOrigin(value) {
  try {
    const url = new URL(String(value || "").trim());
    if (
      url.protocol !== "https:" ||
      url.username ||
      url.password ||
      url.pathname !== "/" ||
      url.search ||
      url.hash
    ) {
      return "";
    }
    return url.origin;
  } catch {
    return "";
  }
}

function normalizeCrashBotUrl(value) {
  try {
    const url = new URL(String(value || "").trim());
    if (
      url.protocol !== "https:" ||
      url.username ||
      url.password ||
      !url.pathname.startsWith("/") ||
      url.pathname.includes("..") ||
      url.search ||
      url.hash
    ) {
      return "";
    }
    return url.toString();
  } catch {
    return "";
  }
}

const publicBaseUrl = normalizePublicOrigin(
  process.env.PUBLIC_BASE_URL ||
    process.env.RENDER_EXTERNAL_URL ||
    (selfTest ? "https://auth.example.com" : ""),
);
const ttlMs = 10 * 60 * 1000;
const rateWindowMs = 60 * 1000;
const maxRateLimitEntries = 4096;
const maxOAuthPairings = 256;
const oauthUpstreamTimeoutMs = 12_000;
// Render puts its authenticated client address first in X-Forwarded-For.
// A conventional explicitly trusted proxy appends its peer address last.
// Never apply one convention to the other: the remaining entries can be
// client-controlled.
const forwardedForMode = selfTest
  ? "rightmost"
  : process.env.RENDER === "true" || process.env.RENDER_SERVICE_ID
    ? "leftmost"
    : process.env.TRUST_PROXY === "1"
      ? "rightmost"
      : "none";
const githubReleaseRepository =
  process.env.GITHUB_RELEASE_REPOSITORY || "LindersOSX/TetoTV";
// Existing 1.11.x clients only know this broker and compare user-facing
// SemVer. Keep a narrow, anonymous one-way bridge to the public release-only
// repository so they can cross the 1.11.x -> 1.0.x numbering reset. Current
// Public clients read GitHub directly; authenticated requests remain Beta.
const legacyPublicReleaseRepository = "LindersOSX/TetoTV-Releases";
const legacyPublicAliasTag = "v1.11.34";
const legacyPublicAliasVersion = "1.11.34";
const githubReleaseToken =
  process.env.GITHUB_RELEASE_TOKEN ||
  (selfTest ? "self-test-github-release-token" : "");
const selfTestBetaAccessKey = selfTest ? "B".repeat(43) : "";
const betaAccessKeyHashes = parseBetaAccessKeyHashes(
  process.env.BETA_ACCESS_KEY_SHA256_HASHES ||
    (selfTest
      ? createHash("sha256").update(selfTestBetaAccessKey).digest("hex")
      : ""),
);
const githubReleaseApiVersion = "2022-11-28";
const releaseMetadataTtlMs = 60 * 1000;
const versionedReleaseTtlMs = 24 * 60 * 60 * 1000;
const maxReleaseAssetBytes = 300 * 1024 * 1024;
const maxReleaseNotesLength = 32_000;
// This deployment is intentionally small/private. Move APK delivery to
// object storage/CDN before raising these process-wide safeguards.
const maxConcurrentUpdateDownloads = 4;
const maxUpdateDownloadsPerMinute = 12;
const appPresenceTtlMs = 3 * 60 * 1000;
const appPresenceHeartbeatSeconds = 45;
const maxAppPresenceSessions = 10_000;
const crashBotUrl = normalizeCrashBotUrl(
  process.env.CRASH_REPORT_BOT_URL ||
    (selfTest ? "https://bot.example.com/crash-reports" : ""),
);
const crashSharedSecret =
  process.env.CRASH_REPORT_SHARED_SECRET ||
  (selfTest ? "self-test-crash-secret-that-is-long-enough" : "");
const selfTestCrashForwards = [];
const pairings = new Map();
const codes = new Map();
const sourcePairings = new Map();
const sourceCodes = new Map();
const sourceReceipts = new Map();
const appPresenceSessions = new Map();
const rateLimits = new Map();
let nextRateLimitCleanupAt = 0;
let cachedLatestRelease = null;
let latestReleaseRequest = null;
let cachedReleaseHistory = null;
let releaseHistoryRequest = null;
let cachedLegacyPublicRelease = null;
let legacyPublicReleaseRequest = null;
let activeUpdateDownloads = 0;
let updateDownloadWindowStartedAt = 0;
let updateDownloadsInWindow = 0;
const cachedVersionedReleases = new Map();

class RequestInputError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

class UpdateProxyError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

function providerConfig(provider) {
  if (provider === "anilist") {
    return {
      name: "AniList",
      clientId:
        process.env.ANILIST_CLIENT_ID || (selfTest ? "test-anilist-id" : ""),
      clientSecret:
        process.env.ANILIST_CLIENT_SECRET ||
        (selfTest ? "test-anilist-secret" : ""),
      authorizeUrl: "https://anilist.co/api/v2/oauth/authorize",
      tokenUrl: "https://anilist.co/api/v2/oauth/token",
    };
  }
  if (provider === "myanimelist") {
    return {
      name: "MyAnimeList",
      clientId: process.env.MAL_CLIENT_ID || (selfTest ? "test-mal-id" : ""),
      clientSecret:
        process.env.MAL_CLIENT_SECRET || (selfTest ? "test-mal-secret" : ""),
      authorizeUrl: "https://myanimelist.net/v1/oauth2/authorize",
      tokenUrl: "https://myanimelist.net/v1/oauth2/token",
    };
  }
  return null;
}

const callbackUrl = (provider) =>
  `${publicBaseUrl}/oauth/${provider}/callback`;
const randomToken = (bytes = 32) => randomBytes(bytes).toString("base64url");
const digest = (value) => createHash("sha256").update(value).digest();
const safeEqual = (left, right) =>
  timingSafeEqual(digest(left), digest(right));

function newUserCode() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let value = "";
  for (let index = 0; index < 8; index += 1) {
    value += alphabet[randomBytes(1)[0] % alphabet.length];
  }
  return `${value.slice(0, 4)}-${value.slice(4)}`;
}

function json(response, status, value, extraHeaders = {}) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    ...extraHeaders,
  });
  response.end(JSON.stringify(value));
}

function applyGlobalSecurityHeaders(response) {
  response.setHeader("Referrer-Policy", "no-referrer");
  response.setHeader("X-Content-Type-Options", "nosniff");
  response.setHeader("X-Frame-Options", "DENY");
  response.setHeader("Cross-Origin-Resource-Policy", "same-origin");
  response.setHeader(
    "Permissions-Policy",
    "camera=(), microphone=(), geolocation=()",
  );
  if (publicBaseUrl.startsWith("https://")) {
    response.setHeader(
      "Strict-Transport-Security",
      "max-age=31536000",
    );
  }
}

function html(
  response,
  status,
  body,
  { refreshUrl = "", title = "TetoTV pairing" } = {},
) {
  response.writeHead(status, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store",
    "Content-Security-Policy":
      "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Cross-Origin-Resource-Policy": "same-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
  });
  const refresh = refreshUrl
    ? `<meta http-equiv="refresh" content="2;url=${escapeHtml(refreshUrl)}">`
    : "";
  response.end(`<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">${refresh}
<title>${escapeHtml(title)}</title>
<style>
body{margin:0;background:#080c16;color:#f5f5fb;font:18px system-ui;display:grid;min-height:100vh;place-items:center}
main{width:min(580px,calc(100% - 40px));background:#131928;border:1px solid #293149;border-radius:24px;padding:32px;box-sizing:border-box}
h1{margin:0 0 12px;font-size:32px}p{color:#b8bfd4;line-height:1.55}
a,button{display:block;width:100%;box-sizing:border-box;border:0;margin-top:24px;padding:16px 20px;border-radius:12px;background:#f5f5fb;color:#111624;text-align:center;text-decoration:none;font:inherit;font-weight:800;cursor:pointer}
input,textarea{display:block;width:100%;box-sizing:border-box;margin-top:22px;padding:16px 18px;border:1px solid #39435f;border-radius:12px;background:#090e1a;color:#f5f5fb;font:700 18px system-ui}
textarea{min-height:150px;resize:vertical;overflow-wrap:anywhere}.code-input{font-size:22px;letter-spacing:3px;text-transform:uppercase}
code{color:#5bd8ec}small{display:block;margin-top:18px;color:#7f879e}
label{display:block;margin-top:22px;font-weight:800}label+textarea{margin-top:8px}.field-help{margin-top:8px}
.success{color:#67d49b}.warning{color:#ffd166}.error{color:#ff8798;font-weight:800}.count{font-size:22px;font-weight:800;color:#f5f5fb}
</style><main>${body}</main></html>`);
}

function privacyPage(response) {
  return html(
    response,
    200,
    `<h1>TetoTV privacy disclosure</h1>
     <p><small>Effective August 13, 2026</small></p>
     <p>TetoTV is an independent Android application. It has no advertising or analytics SDK, no TetoTV account system, and does not sell personal data.</p>

     <h2>Data kept on the device</h2>
     <p>Account and debrid credentials use Android Keystore-backed secure storage. An optional Jellyfin server address, username, access token, and random app device ID, plus an optional Plex server address, X-Plex-Token, and random client identifier, use the same protected device storage. Jellyfin passwords are used only for sign-in and are not saved. Playback history, resume positions, preferences, tracker-sync entries, installed source definitions, bounded diagnostics, and device playback capabilities remain in app storage until removed in TetoTV, Android app storage is cleared, or the app is uninstalled.</p>
     <p>TetoTV's <strong>Settings &gt; System &gt; Reset TetoTV</strong> action and Android's Clear storage action remove all TetoTV local data. The separate <strong>Clear cache</strong> action removes only temporary files and retains accounts, preferences, sources, and history.</p>

     <h2>Services selected by the user</h2>
     <p>Features the user chooses can send the minimum required requests to AniList, MAL, Kitsu, a selected debrid provider, AniSkip, artwork hosts, and source repositories or extensions the user explicitly installs. Those independent services receive ordinary connection metadata and apply their own terms and privacy policies. TetoTV does not bundle or recommend a streaming-source repository.</p>
     <p>Android's system file picker grants TetoTV read access only to a local video the user selects; TetoTV does not upload that USB or internal-storage video. If the user connects Jellyfin, the entered username and password go directly to that server for sign-in, the password is not saved, and the returned access token is kept in Keystore-backed secure storage. If the user connects Plex, the saved X-Plex-Token goes directly to that server in request headers and is never placed in media or artwork URLs. HTTPS is recommended. HTTP requires a warning and is limited to a numeric private-network address or localhost, where credentials and video traffic are not encrypted. Jellyfin and Plex traffic do not pass through the TetoTV broker.</p>
     <p>When a user explicitly links Discord and enables <strong>Discord Rich Presence</strong>, TetoTV sends Discord the current anime title, episode number, playing or paused state, playback timing, and the public show-artwork URL so Discord can display that activity with the show's thumbnail. USB, internal-storage, Jellyfin, and Plex playback is excluded so private filenames and library titles are not shared. Discord OAuth access and refresh tokens are stored in Android Keystore-backed secure storage. Disabling Rich Presence stops sharing playback activity; unlinking Discord also revokes the connection when possible and deletes the saved tokens from TetoTV. TetoTV never asks for or stores the user's Discord password.</p>
     <p>On Android TV and Fire TV, Discord linking uses Discord's limited-input device authorization directly. TetoTV sends a one-time authorization request to Discord and polls Discord only until the link succeeds, expires, or is canceled. The private device code is kept only in app memory during that attempt; completed access and refresh tokens use the same Android Keystore-backed secure storage described above. The TetoTV broker is not involved in Discord linking.</p>

     <h2>Pairing and update broker</h2>
     <p>OAuth pairing keeps one-time state, a device-code hash, PKCE data, and token material in process memory for at most ten minutes. A successful authenticated device poll deletes the complete pairing immediately.</p>
     <p>Phone-assisted source entry keeps submitted URLs in volatile memory for at most ten minutes after submission. The URLs are deleted when the authenticated app acknowledges local processing or the session expires. A count-only confirmation can remain for at most another ten minutes.</p>
     <p>Rate limiting keeps pseudonymous namespace-and-address hashes for roughly one minute. The update proxy caches sanitized release metadata briefly and streams the signed universal APK without persisting it. The server-only GitHub credential is never sent to the app. Signed builds contain a shared, revocable Beta-channel credential and send it only to the fixed TetoTV update broker; it is not displayed or stored as an editable account secret. Because it is present in the public APK, it is not a confidentiality boundary. The broker stores only configured SHA-256 hashes for access checks and never returns keys or hashes from its health endpoint. A narrow anonymous migration endpoint lets legacy 1.11.x clients download only the latest signed APK from the public 1.x repository.</p>
     <p>The hosting provider may independently process IP addresses, request metadata, opaque pairing or receipt IDs, and OAuth callback parameters in operational access logs. TetoTV does not use this data for advertising or cross-service tracking.</p>

     <h2>Anonymous live activity count</h2>
     <p>Anonymous live counting is disabled by default and requires an explicit choice during first-time setup or in Settings. When enabled, TetoTV creates a random per-launch token that is kept only in app and broker memory. It reports only whether that app session is active or currently playing video. It never reports the show, episode, account, device identifier, stream provider, or URL.</p>
     <p>Sessions expire after about three minutes without a heartbeat and are removed when the app opts out or closes normally. Only aggregate active and streaming counts are public. The hosting provider may process IP addresses for short-lived rate limiting and ordinary access logs.</p>

     <h2>Diagnostics and choices</h2>
     <p><strong>Anonymous crash reporting is disabled by default.</strong> First-time setup and Settings both let the user explicitly enable or disable it. When enabled, unexpected handled app errors and unhandled crashes can be reported. TetoTV sends only the app version/build, crash category, Android version, CPU architecture, TV-or-phone class, time, and a bounded redacted technical error/stack trace. It does not intentionally send the show, episode, account, device or installation identifier, source/provider, URL, credential, playback history, or full diagnostics database.</p>
     <p>A JVM crash is kept locally and sent after the next launch. On Android versions that expose historical process-exit details, native crashes and ANRs can also be recovered after restart. This broker validates and rate-limits the report, adds a random per-incident reference, and forwards it without storing the body to the TetoTV Discord bot. The bot posts it to the designated crash-report channel, where Discord retention and channel permissions apply. Disabling reporting deletes any queued unsent report. Hosting providers and Discord may process ordinary connection and request metadata under their own policies.</p>
     <p>Other diagnostics stay on the device unless the user explicitly copies or shares a report. Users can disconnect services, remove local history and sources, clear Android app storage, or uninstall TetoTV. Removing local history does not modify AniList or MAL.</p>

     <h2>Security, children, and changes</h2>
     <p>Network integrations require HTTPS except an explicitly approved Jellyfin or Plex connection to a numeric private-network address or localhost. User-added endpoints are constrained to their expected network boundary. TetoTV is not directed to children and does not knowingly collect a child's personal information. This disclosure will be updated when material features or hosting practices change.</p>

     <h2>Contact</h2>
     <p>Privacy questions, support requests, and deletion requests can be sent to the TetoTV maintainer through the public <a href="https://discord.gg/juC6k7d4WY">TetoTV Discord community</a>.</p>`,
    { title: "TetoTV privacy disclosure" },
  );
}

const escapeHtml = (value) =>
  String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");

const normalizeCode = (value) =>
  String(value || "").trim().toUpperCase();

function clientAddress(request, mode = forwardedForMode) {
  const rawForwarded = String(request.headers["x-forwarded-for"] || "");
  const boundedForwarded =
    mode === "leftmost"
      ? rawForwarded.slice(0, 2048)
      : rawForwarded.slice(-2048);
  const values = boundedForwarded.split(",");
  return String(
    mode === "leftmost" && boundedForwarded
      ? values.at(0)
      : mode === "rightmost" && boundedForwarded
        ? values.at(-1)
        : request.socket.remoteAddress || "",
  )
    .trim()
    .slice(0, 256);
}

function rateLimited(request, limit = 600, namespace = "global") {
  const address = clientAddress(request);
  const key = createHash("sha256")
    .update(`${namespace}:${address}`)
    .digest("base64url");
  const now = Date.now();
  cleanupRateLimits(now);
  const current = rateLimits.get(key);
  if (!current || now - current.startedAt >= rateWindowMs) {
    // Bound memory even if untrusted forwarding headers contain a stream of
    // unique values. Existing buckets can finish their current window.
    if (!current && rateLimits.size >= maxRateLimitEntries) return true;
    rateLimits.set(key, { startedAt: now, count: 1 });
    return false;
  }
  current.count += 1;
  return current.count > limit;
}

function cleanupRateLimits(now = Date.now()) {
  if (now < nextRateLimitCleanupAt) return;
  nextRateLimitCleanupAt = now + rateWindowMs;
  for (const [key, bucket] of rateLimits) {
    if (now - bucket.startedAt >= rateWindowMs) rateLimits.delete(key);
  }
}

function globallyRateLimitedUpdateDownload(now = Date.now()) {
  if (
    !updateDownloadWindowStartedAt ||
    now - updateDownloadWindowStartedAt >= rateWindowMs
  ) {
    updateDownloadWindowStartedAt = now;
    updateDownloadsInWindow = 1;
    return false;
  }
  updateDownloadsInWindow += 1;
  return updateDownloadsInWindow > maxUpdateDownloadsPerMinute;
}

function cleanup() {
  const now = Date.now();
  cleanupRateLimits(now);
  for (const [id, pairing] of pairings) {
    if (pairing.expiresAt <= now) {
      pairings.delete(id);
      codes.delete(pairing.userCode);
    }
  }
  for (const [id, pairing] of sourcePairings) {
    if (pairing.expiresAt <= now) {
      sourcePairings.delete(id);
      sourceCodes.delete(pairing.userCode);
      if (pairing.receiptToken) sourceReceipts.delete(pairing.receiptToken);
    }
  }
  for (const [tokenHash, session] of appPresenceSessions) {
    if (session.expiresAt <= now) appPresenceSessions.delete(tokenHash);
  }
}

function presenceTokenHash(value) {
  return digest(value).toString("base64url");
}

function bearerToken(request) {
  const authorization = String(request.headers.authorization || "");
  const match = authorization.match(/^Bearer ([A-Za-z0-9_-]{32,128})$/);
  return match?.[1] || "";
}

async function createAppPresenceSession(request, response) {
  await drainBody(request);
  cleanup();
  if (appPresenceSessions.size >= maxAppPresenceSessions) {
    return json(
      response,
      503,
      { error: "presence_capacity_reached" },
      { "Retry-After": "60" },
    );
  }
  const token = randomToken(32);
  appPresenceSessions.set(presenceTokenHash(token), {
    state: "active",
    expiresAt: Date.now() + appPresenceTtlMs,
  });
  return json(response, 201, {
    session_token: token,
    expires_in: Math.floor(appPresenceTtlMs / 1000),
    heartbeat_interval: appPresenceHeartbeatSeconds,
  });
}

async function updateAppPresenceSession(request, response) {
  const token = bearerToken(request);
  if (!token) return json(response, 401, { error: "invalid_session" });
  const body = await readJson(request, { requireBody: true });
  if (
    !body ||
    typeof body !== "object" ||
    Array.isArray(body) ||
    Object.keys(body).length !== 1 ||
    (body.state !== "active" && body.state !== "streaming")
  ) {
    throw new RequestInputError(400, "Invalid presence state.");
  }
  cleanup();
  const session = appPresenceSessions.get(presenceTokenHash(token));
  if (!session) return json(response, 401, { error: "invalid_session" });
  session.state = body.state;
  session.expiresAt = Date.now() + appPresenceTtlMs;
  response.writeHead(204, { "Cache-Control": "no-store" });
  response.end();
}

async function closeAppPresenceSession(request, response) {
  await drainBody(request);
  const token = bearerToken(request);
  if (!token) return json(response, 401, { error: "invalid_session" });
  appPresenceSessions.delete(presenceTokenHash(token));
  response.writeHead(204, { "Cache-Control": "no-store" });
  response.end();
}

function appPresenceSummary(response) {
  cleanup();
  let streaming = 0;
  for (const session of appPresenceSessions.values()) {
    if (session.state === "streaming") streaming += 1;
  }
  return json(response, 200, {
    active: appPresenceSessions.size,
    streaming,
    ttl_seconds: Math.floor(appPresenceTtlMs / 1000),
  });
}

function crashReportingConfigured() {
  return Boolean(crashBotUrl) && crashSharedSecret.length >= 32;
}

function sanitizeCrashText(value, maximum) {
  let output = String(value || "")
    .replace(/https?:\/\/[^\s"']+/gi, "[URL]")
    .replace(/magnet:\?[^\s"']+/gi, "[MAGNET]")
    .replace(
      /\b(?![A-Za-z]:[\\/])[A-Za-z][A-Za-z0-9+.-]{0,31}:(?![0-9\s])[^\s"'<>]+/gi,
      "[URI]",
    )
    .replace(
      /(^|[\s"'(=\[])(?:[A-Za-z]:[\\/]|\\\\[^\\/\s"'<>]+[\\/])[^\r\n"'<>]*/gm,
      "$1[PATH]",
    )
    .replace(
      /(^|[\s"'(=\[])\/(?!\/)[^\r\n"'<>]*/gm,
      "$1[PATH]",
    )
    .replace(/bearer\s+[^\s,;"']+/gi, "Bearer [REDACTED]")
    .replace(/\b(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]+\b/gi, "[REDACTED]")
    .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, "[REDACTED]")
    .replace(/(?:authorization|access[_ -]?token|refresh[_ -]?token|token|api[_ -]?key|client[_ -]?secret|password)\s*[:=]\s*[^\s,;"']+/gi, "[REDACTED]")
    .replace(/\b[a-fA-F0-9]{40,}\b/g, "[REDACTED]")
    .replace(/@(everyone|here)/gi, "$1")
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "")
    .trim();
  if (output.length > maximum) output = output.slice(0, maximum);
  return output;
}

function validateCrashReport(value) {
  const expectedKeys = [
    "abi",
    "android_sdk",
    "app_version",
    "build_number",
    "device_class",
    "event_id",
    "kind",
    "message",
    "occurred_at",
    "schema_version",
    "stack",
  ];
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.keys(value).sort().join("|") !== expectedKeys.join("|") ||
    value.schema_version !== 1 ||
    typeof value.event_id !== "string" ||
    !/^[A-Za-z0-9_-]{8,100}$/.test(value.event_id) ||
    !["flutter", "platform", "native", "java", "anr"].includes(value.kind) ||
    typeof value.message !== "string" ||
    value.message.length < 1 ||
    value.message.length > 500 ||
    typeof value.stack !== "string" ||
    value.stack.length > 4_000 ||
    typeof value.app_version !== "string" ||
    !/^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$/.test(value.app_version) ||
    !Number.isSafeInteger(value.build_number) ||
    value.build_number < 1 ||
    value.build_number > 999_999_999 ||
    !Number.isSafeInteger(value.android_sdk) ||
    value.android_sdk < 24 ||
    value.android_sdk > 99 ||
    !["arm64-v8a", "armeabi-v7a", "x86_64", "x86", "unknown"].includes(value.abi) ||
    !["tv", "phone"].includes(value.device_class)
  ) {
    throw new RequestInputError(400, "Invalid anonymous crash report.");
  }
  const occurredAt = Date.parse(value.occurred_at);
  const now = Date.now();
  if (
    !Number.isFinite(occurredAt) ||
    occurredAt < now - 30 * 24 * 60 * 60 * 1000 ||
    occurredAt > now + 10 * 60 * 1000
  ) {
    throw new RequestInputError(400, "Invalid anonymous crash timestamp.");
  }
  return {
    schema_version: 1,
    incident_id: createHmac("sha256", crashSharedSecret)
      .update(value.event_id)
      .digest("base64url")
      .slice(0, 20),
    kind: value.kind,
    message: sanitizeCrashText(value.message, 500),
    stack: sanitizeCrashText(value.stack, 4_000),
    occurred_at: new Date(occurredAt).toISOString(),
    app_version: value.app_version,
    build_number: value.build_number,
    android_sdk: value.android_sdk,
    abi: value.abi,
    device_class: value.device_class,
  };
}

async function forwardCrashReport(report) {
  const body = JSON.stringify(report);
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = `sha256=${createHmac("sha256", crashSharedSecret)
    .update(`${timestamp}.${body}`)
    .digest("hex")}`;
  if (selfTest) {
    selfTestCrashForwards.push({ body, timestamp, signature });
    const expected = `sha256=${createHmac("sha256", crashSharedSecret)
      .update(`${timestamp}.${body}`)
      .digest("hex")}`;
    if (!safeEqual(signature, expected)) throw new Error("Crash HMAC mismatch.");
    return;
  }
  const upstream = await fetch(crashBotUrl, {
    method: "POST",
    redirect: "manual",
    signal: AbortSignal.timeout(8_000),
    headers: {
      "Content-Type": "application/json",
      "X-TetoTV-Timestamp": timestamp,
      "X-TetoTV-Signature": signature,
    },
    body,
  });
  if (upstream.status !== 202) throw new Error("Crash bot rejected report.");
  await upstream.body?.cancel();
}

async function receiveCrashReport(request, response) {
  if (!crashReportingConfigured()) {
    await drainBody(request);
    return json(
      response,
      503,
      { error: "crash_reporting_unavailable" },
      { "Retry-After": "300" },
    );
  }
  const report = validateCrashReport(
    await readJson(request, { requireBody: true }),
  );
  await forwardCrashReport(report);
  return json(response, 202, { status: "accepted" });
}

async function drainBody(request) {
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 16_384) {
      throw new RequestInputError(413, "Request body is too large.");
    }
  }
}

async function readJson(request, { requireBody = false } = {}) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 16_384) {
      throw new RequestInputError(413, "Request body is too large.");
    }
    chunks.push(chunk);
  }
  const value = Buffer.concat(chunks).toString("utf8");
  if (requireBody && !value.trim()) {
    throw new RequestInputError(400, "Expected a JSON object.");
  }
  return value ? JSON.parse(value) : {};
}

async function readForm(request) {
  const contentType = String(request.headers["content-type"] || "")
    .split(";", 1)[0]
    .trim()
    .toLowerCase();
  if (contentType !== "application/x-www-form-urlencoded") {
    throw new RequestInputError(415, "Expected a form submission.");
  }
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 131_072) {
      throw new RequestInputError(413, "Request body is too large.");
    }
    chunks.push(chunk);
  }
  return new URLSearchParams(Buffer.concat(chunks).toString("utf8"));
}

function validSubmittedUrl(value, { manifest = false } = {}) {
  if (
    typeof value !== "string" ||
    value.length < 10 ||
    value.length > 2048 ||
    /[\u0000-\u001f\u007f]/.test(value)
  ) {
    return false;
  }
  try {
    const url = new URL(value);
    const structurallySafe =
      url.protocol === "https:" &&
      Boolean(url.hostname) &&
      !url.username &&
      !url.password;
    return (
      structurallySafe &&
      (!manifest || url.pathname.toLowerCase().endsWith("/manifest.json"))
    );
  } catch {
    return false;
  }
}

function sourcePairingValidationError(repositoryUrls, manifestUrls) {
  if (repositoryUrls.length > 8) {
    return "The Marketplace repositories field accepts up to eight URLs.";
  }
  if (manifestUrls.length > 8) {
    return "The Torrent source manifests field accepts up to eight URLs.";
  }
  if (repositoryUrls.length + manifestUrls.length === 0) {
    return "Enter at least one Marketplace repository or Torrent source manifest URL.";
  }
  if (repositoryUrls.some((value) => !validSubmittedUrl(value))) {
    return "Every Marketplace repository entry must be a valid public HTTPS URL without embedded username/password credentials.";
  }
  if (manifestUrls.some((value) => !validSubmittedUrl(value))) {
    return "Every Torrent source manifest entry must be a valid public HTTPS URL without embedded username/password credentials.";
  }
  const marketplaceUrlInManifestField = manifestUrls.some((value) => {
    try {
      return new URL(value).pathname
        .toLowerCase()
        .endsWith("/marketplace.json");
    } catch {
      return false;
    }
  });
  if (marketplaceUrlInManifestField) {
    return "A marketplace.json URL was entered under Torrent source manifests. Move it to Marketplace repositories. Torrent source manifest URLs must end in /manifest.json.";
  }
  if (
    manifestUrls.some(
      (value) => !validSubmittedUrl(value, { manifest: true }),
    )
  ) {
    return "Every URL under Torrent source manifests must end in /manifest.json. Marketplace repository URLs belong in the Marketplace repositories field.";
  }
  return "";
}

async function createSourcePairing(request, response) {
  if (!publicBaseUrl.startsWith("https://")) {
    return json(response, 503, {
      error: "PUBLIC_BASE_URL must be an externally reachable HTTPS origin.",
    });
  }
  const contentType = String(request.headers["content-type"] || "")
    .split(";", 1)[0]
    .trim()
    .toLowerCase();
  if (contentType !== "application/json") {
    throw new RequestInputError(415, "Expected a JSON request.");
  }
  const body = await readJson(request, { requireBody: true });
  if (
    !body ||
    Array.isArray(body) ||
    typeof body !== "object" ||
    Object.keys(body).length !== 0
  ) {
    return json(response, 400, { error: "invalid_request" });
  }
  cleanup();
  if (sourcePairings.size >= 256) {
    return json(response, 503, { error: "pairing_capacity_reached" });
  }
  let userCode;
  do userCode = newUserCode();
  while (sourceCodes.has(userCode));
  const pairingId = randomToken(18);
  const deviceCode = randomToken(32);
  const expiresAt = Date.now() + ttlMs;
  sourcePairings.set(pairingId, {
    userCode,
    deviceHash: digest(deviceCode),
    expiresAt,
    status: "pending",
    submitted: null,
    result: null,
    receiptToken: null,
  });
  sourceCodes.set(userCode, pairingId);
  return json(response, 201, {
    pairing_id: pairingId,
    device_code: deviceCode,
    user_code: userCode,
    verification_uri: `${publicBaseUrl}/source-pair`,
    verification_uri_complete: `${publicBaseUrl}/source-pair?code=${encodeURIComponent(userCode)}`,
    expires_at: new Date(expiresAt).toISOString(),
    interval: 3,
  });
}

function pollSourcePairing(request, response, pairingId) {
  cleanup();
  const pairing = sourcePairings.get(pairingId);
  if (!pairing) return json(response, 404, { status: "expired" });
  const authorization = String(request.headers.authorization || "");
  const deviceCode = authorization.startsWith("Pairing ")
    ? authorization.slice("Pairing ".length)
    : "";
  const suppliedHash = digest(deviceCode);
  if (!deviceCode || !timingSafeEqual(suppliedHash, pairing.deviceHash)) {
    return json(response, 401, { error: "invalid_device_code" });
  }
  if (
    (pairing.status !== "submitted" && pairing.status !== "delivered") ||
    !pairing.submitted
  ) {
    return json(response, 200, {
      status:
        pairing.status === "completed" || pairing.status === "failed"
          ? pairing.status
          : "pending",
    });
  }
  const submitted = pairing.submitted;
  pairing.status = "delivered";
  // The device may retrieve this authenticated payload again after a network
  // interruption. URLs are cleared only after the app acknowledges that local
  // persistence finished; the human code can never retrieve this response.
  return json(response, 200, {
    status: "submitted",
    repository_urls: submitted.repositoryUrls,
    manifest_urls: submitted.manifestUrls,
  });
}

async function completeSourcePairing(request, response, pairingId) {
  cleanup();
  const pairing = sourcePairings.get(pairingId);
  if (!pairing) return json(response, 404, { status: "expired" });
  const authorization = String(request.headers.authorization || "");
  const deviceCode = authorization.startsWith("Pairing ")
    ? authorization.slice("Pairing ".length)
    : "";
  if (!deviceCode || !timingSafeEqual(digest(deviceCode), pairing.deviceHash)) {
    return json(response, 401, { error: "invalid_device_code" });
  }
  const body = await readJson(request, { requireBody: true });
  if (
    !body ||
    Array.isArray(body) ||
    typeof body !== "object" ||
    Object.keys(body).sort().join(",") !==
      "manifests_saved,rejected_count,repositories_saved"
  ) {
    return json(response, 400, { error: "invalid_completion" });
  }
  if (pairing.status === "completed" || pairing.status === "failed") {
    response.writeHead(204, {
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    });
    return response.end();
  }
  if (pairing.status !== "delivered" || !pairing.submitted) {
    return json(response, 409, { error: "submission_not_ready" });
  }
  const repositoriesSaved = body.repositories_saved;
  const manifestsSaved = body.manifests_saved;
  const rejectedCount = body.rejected_count;
  const repositoryCount = pairing.submitted.repositoryUrls.length;
  const manifestCount = pairing.submitted.manifestUrls.length;
  const submittedCount = repositoryCount + manifestCount;
  if (
    !Number.isSafeInteger(repositoriesSaved) ||
    !Number.isSafeInteger(manifestsSaved) ||
    !Number.isSafeInteger(rejectedCount) ||
    repositoriesSaved < 0 ||
    repositoriesSaved > repositoryCount ||
    manifestsSaved < 0 ||
    manifestsSaved > manifestCount ||
    rejectedCount < 0 ||
    rejectedCount > submittedCount ||
    repositoriesSaved + manifestsSaved + rejectedCount !== submittedCount
  ) {
    return json(response, 400, { error: "invalid_completion" });
  }

  pairing.result = {
    repositoriesSaved,
    manifestsSaved,
    rejectedCount,
  };
  pairing.status =
    repositoriesSaved + manifestsSaved > 0 ? "completed" : "failed";
  pairing.expiresAt = Date.now() + ttlMs;
  // Clear all submitted URLs immediately after the authenticated device says
  // persistence finished. The retained receipt contains counts only.
  pairing.submitted = null;
  response.writeHead(204, {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  response.end();
}

function sourceReceiptPage(response, receiptToken) {
  cleanup();
  const pairingId = sourceReceipts.get(receiptToken);
  const pairing = pairingId ? sourcePairings.get(pairingId) : null;
  if (!pairing || pairing.receiptToken !== receiptToken) {
    return html(
      response,
      404,
      "<h1>Confirmation expired</h1><p>Check TetoTV for the saved result.</p>",
    );
  }
  if (pairing.status === "completed" && pairing.result) {
    const { repositoriesSaved, manifestsSaved, rejectedCount } =
      pairing.result;
    return html(
      response,
      200,
      `<h1 class="success">Saved in TetoTV</h1>
       <p class="count">${repositoriesSaved} marketplace ${repositoriesSaved === 1 ? "repository" : "repositories"} and ${manifestsSaved} torrent ${manifestsSaved === 1 ? "manifest" : "manifests"} saved.</p>
       ${rejectedCount ? `<p class="warning">${rejectedCount} ${rejectedCount === 1 ? "item was" : "items were"} rejected. Review TetoTV for details.</p>` : ""}
       <p>You can close this page.</p>`,
    );
  }
  if (pairing.status === "failed" && pairing.result) {
    return html(
      response,
      200,
      `<h1 class="warning">TetoTV could not save these sources</h1>
       <p>${pairing.result.rejectedCount} ${pairing.result.rejectedCount === 1 ? "item was" : "items were"} rejected. Review TetoTV for details, then create a new code to retry.</p>`,
    );
  }
  return html(
    response,
    200,
    `<h1>Sent to TetoTV</h1>
     <p>Your URLs were submitted securely. Keep TetoTV open while it validates and saves them.</p>
     <p><small>Waiting for the app's saved confirmation…</small></p>`,
    { refreshUrl: `/source-pair/status/${receiptToken}` },
  );
}

function cancelSourcePairing(request, response, pairingId) {
  cleanup();
  const pairing = sourcePairings.get(pairingId);
  if (!pairing) return json(response, 404, { status: "expired" });
  const authorization = String(request.headers.authorization || "");
  const deviceCode = authorization.startsWith("Pairing ")
    ? authorization.slice("Pairing ".length)
    : "";
  if (
    !deviceCode ||
    !timingSafeEqual(digest(deviceCode), pairing.deviceHash)
  ) {
    return json(response, 401, { error: "invalid_device_code" });
  }
  sourcePairings.delete(pairingId);
  sourceCodes.delete(pairing.userCode);
  if (pairing.receiptToken) sourceReceipts.delete(pairing.receiptToken);
  response.writeHead(204, {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  response.end();
}

function sourcePairingForm(
  response,
  pairing,
  errorMessage = "",
  { repositoryUrls = [], manifestUrls = [] } = {},
) {
  const error = errorMessage
    ? `<p class="error" role="alert">${escapeHtml(errorMessage)}</p>`
    : "";
  const repositoryValue = escapeHtml(repositoryUrls.join("\n"));
  const manifestValue = escapeHtml(manifestUrls.join("\n"));
  return html(
    response,
    errorMessage ? 400 : 200,
    `<h1>Send sources to TetoTV</h1>
     <p>Enter URLs for the TV showing code <code>${escapeHtml(pairing.userCode)}</code>. Use one URL per line, up to eight of each.</p>
     ${error}
     <form method="post" action="/source-pair" autocomplete="off">
       <input type="hidden" name="code" value="${escapeHtml(pairing.userCode)}">
       <label for="repository-urls">Marketplace repositories</label>
       <textarea id="repository-urls" name="repository_urls" aria-label="Marketplace repository URLs" placeholder="https://example.com/marketplace.json" maxlength="16391">${repositoryValue}</textarea>
       <small class="field-help">Repository catalogs, commonly ending in marketplace.json.</small>
       <label for="manifest-urls">Torrent source manifests</label>
       <textarea id="manifest-urls" name="manifest_urls" aria-label="Torrent source manifest URLs" placeholder="https://example.com/addon/manifest.json" maxlength="16391">${manifestValue}</textarea>
       <small class="field-help">Individual torrent-source add-ons. Each URL must end in /manifest.json.</small>
       <button type="submit">Send securely</button>
     </form>
     <small>TetoTV never uploads saved account tokens. Submitted URLs are encrypted in transit, held in memory until this device confirms the local save, then deleted.</small>`,
  );
}

function sourcePairingPage(response, url) {
  cleanup();
  const userCode = normalizeCode(url.searchParams.get("code"));
  const pairingId = sourceCodes.get(userCode);
  const pairing = pairingId ? sourcePairings.get(pairingId) : null;
  if (!userCode) {
    return html(
      response,
      200,
      `<h1>Send a URL to TetoTV</h1>
       <p>Enter the code shown on your TV.</p>
       <form method="get" action="/source-pair" autocomplete="off">
         <input class="code-input" name="code" aria-label="TV pairing code" placeholder="ABCD-EFGH" maxlength="9" required>
         <button type="submit">Continue securely</button>
       </form>
       <small>This page cannot read saved TetoTV secrets; it only accepts URLs you explicitly submit.</small>`,
    );
  }
  if (!pairing) {
    return html(
      response,
      404,
      "<h1>Pairing expired</h1><p>Return to TetoTV and create a new code.</p>",
    );
  }
  if (pairing.status !== "pending") {
    return html(
      response,
      409,
      "<h1>Already sent</h1><p>Use the original confirmation page or check TetoTV for the saved result.</p>",
    );
  }
  return sourcePairingForm(response, pairing);
}

async function submitSourcePairing(request, response) {
  cleanup();
  const form = await readForm(request);
  const userCode = normalizeCode(form.get("code"));
  const pairingId = sourceCodes.get(userCode);
  const pairing = pairingId ? sourcePairings.get(pairingId) : null;
  if (!pairing) {
    return html(
      response,
      404,
      "<h1>Pairing expired</h1><p>Return to TetoTV and create a new code.</p>",
    );
  }
  if (pairing.status !== "pending") {
    return html(
      response,
      409,
      "<h1>Already sent</h1><p>This one-time code has already accepted a submission. Use the original confirmation page or check TetoTV.</p>",
    );
  }
  const lines = (name) =>
    String(form.get(name) || "")
      .split(/\r?\n/)
      .map((value) => value.trim())
      .filter(Boolean);
  const repositoryUrls = lines("repository_urls");
  const manifestUrls = lines("manifest_urls");
  const validationError = sourcePairingValidationError(
    repositoryUrls,
    manifestUrls,
  );
  if (validationError) {
    return sourcePairingForm(
      response,
      pairing,
      validationError,
      { repositoryUrls, manifestUrls },
    );
  }
  pairing.submitted = {
    repositoryUrls: [...new Set(repositoryUrls)],
    manifestUrls: [...new Set(manifestUrls)],
  };
  pairing.status = "submitted";
  // Give the device a full bounded processing window even when the user
  // submits near the end of the original code-entry period.
  pairing.expiresAt = Date.now() + ttlMs;
  pairing.receiptToken = randomToken(18);
  sourceReceipts.set(pairing.receiptToken, pairingId);
  return sourceReceiptPage(response, pairing.receiptToken);
}

async function createPairing(request, response, provider) {
  if (!providerConfig(provider)) {
    return json(response, 404, { error: "unknown_provider" });
  }
  if (!publicBaseUrl.startsWith("https://")) {
    return json(response, 503, {
      error: "PUBLIC_BASE_URL must be an externally reachable HTTPS origin.",
    });
  }
  await drainBody(request);
  cleanup();
  if (pairings.size >= maxOAuthPairings) {
    return json(response, 503, { error: "pairing_capacity_reached" });
  }
  let userCode;
  do userCode = newUserCode();
  while (codes.has(userCode));
  const pairingId = randomToken(18);
  const deviceCode = randomToken(32);
  const expiresAt = Date.now() + ttlMs;
  pairings.set(pairingId, {
    provider,
    userCode,
    deviceHash: digest(deviceCode),
    expiresAt,
    status: "pending",
    tokenSet: null,
    state: null,
    codeVerifier: null,
  });
  codes.set(userCode, pairingId);
  return json(response, 201, {
    pairing_id: pairingId,
    device_code: deviceCode,
    user_code: userCode,
    verification_uri: `${publicBaseUrl}/pair`,
    verification_uri_complete: `${publicBaseUrl}/pair?code=${encodeURIComponent(userCode)}`,
    expires_at: new Date(expiresAt).toISOString(),
    interval: 5,
  });
}

function pollPairing(request, response, provider, pairingId) {
  cleanup();
  const pairing = pairings.get(pairingId);
  if (!pairing || pairing.provider !== provider) {
    return json(response, 404, { status: "expired" });
  }
  const authorization = String(request.headers.authorization || "");
  const deviceCode = authorization.startsWith("Pairing ")
    ? authorization.slice("Pairing ".length)
    : "";
  if (!deviceCode || !timingSafeEqual(digest(deviceCode), pairing.deviceHash)) {
    return json(response, 401, { error: "invalid_device_code" });
  }
  if (pairing.status !== "authorized") {
    return json(response, 200, { status: "pending" });
  }
  const tokenSet = pairing.tokenSet;
  pairings.delete(pairingId);
  codes.delete(pairing.userCode);
  return json(response, 200, {
    status: "authorized",
    access_token: tokenSet.accessToken,
    ...(tokenSet.refreshToken
      ? { refresh_token: tokenSet.refreshToken }
      : {}),
    ...(tokenSet.expiresAt ? { expires_at: tokenSet.expiresAt } : {}),
  });
}

function pairingPage(response, url) {
  cleanup();
  const userCode = normalizeCode(url.searchParams.get("code"));
  const pairingId = codes.get(userCode);
  const pairing = pairingId ? pairings.get(pairingId) : null;
  if (!userCode) {
    return html(
      response,
      200,
      `<h1>Connect TetoTV</h1>
       <p>Enter the code shown on your TV.</p>
       <form method="get" action="/pair" autocomplete="off">
         <input class="code-input" name="code" aria-label="TV pairing code" placeholder="ABCD-EFGH" maxlength="9" required>
         <button type="submit">Continue securely</button>
       </form>
       <small>No TetoTV password is entered on this page.</small>`,
    );
  }
  if (!pairing) {
    return html(
      response,
      404,
      "<h1>Pairing expired</h1><p>Return to TetoTV and create a new code.</p>",
    );
  }
  const config = providerConfig(pairing.provider);
  return html(
    response,
    200,
    `<h1>Connect ${config.name}</h1>
     <p>Confirm that your TV shows code <code>${pairing.userCode}</code>, then continue to ${config.name}.</p>
     <a href="/authorize?code=${encodeURIComponent(pairing.userCode)}">Continue securely</a>
     <small>The token is delivered once to the TV holding the private device code.</small>`,
  );
}

function startAuthorization(response, url) {
  cleanup();
  const userCode = normalizeCode(url.searchParams.get("code"));
  const pairingId = codes.get(userCode);
  const pairing = pairingId ? pairings.get(pairingId) : null;
  if (!pairing) {
    return html(
      response,
      404,
      "<h1>Pairing expired</h1><p>Create a new code on the TV.</p>",
    );
  }
  const config = providerConfig(pairing.provider);
  if (
    !config.clientId ||
    !config.clientSecret
  ) {
    return html(
      response,
      503,
      "<h1>Provider not configured</h1><p>The app owner must add the OAuth client credentials.</p>",
    );
  }
  pairing.state = randomToken(32);
  pairing.codeVerifier = randomToken(64);
  const authorize = new URL(config.authorizeUrl);
  authorize.searchParams.set("client_id", config.clientId);
  authorize.searchParams.set("response_type", "code");
  authorize.searchParams.set("state", pairing.state);
  if (pairing.provider === "myanimelist") {
    // MAL binds the callback to the API client registration. Supplying a
    // redirect_uri on this endpoint makes an otherwise valid client fail with
    // `401 invalid_client` instead of showing the login page.
    authorize.searchParams.set("code_challenge", pairing.codeVerifier);
    authorize.searchParams.set("code_challenge_method", "plain");
  } else {
    authorize.searchParams.set("redirect_uri", callbackUrl(pairing.provider));
  }
  response.writeHead(302, {
    Location: authorize.toString(),
    "Cache-Control": "no-store",
    "Referrer-Policy": "no-referrer",
  });
  response.end();
}

async function exchangeCode(pairing, code) {
  const config = providerConfig(pairing.provider);
  if (pairing.provider === "anilist") {
    const result = await fetch(config.tokenUrl, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        grant_type: "authorization_code",
        client_id: config.clientId,
        client_secret: config.clientSecret,
        redirect_uri: callbackUrl(pairing.provider),
        code,
      }),
      redirect: "error",
      signal: AbortSignal.timeout(oauthUpstreamTimeoutMs),
    });
    const body = await result.json();
    if (!result.ok || !body.access_token) {
      throw new Error(`AniList token exchange failed (${result.status}).`);
    }
    return {
      accessToken: body.access_token,
      refreshToken: body.refresh_token || null,
      expiresAt: body.expires_in
        ? new Date(Date.now() + Number(body.expires_in) * 1000).toISOString()
        : null,
    };
  }

  const form = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: config.clientId,
    code,
    code_verifier: pairing.codeVerifier,
  });
  if (config.clientSecret) form.set("client_secret", config.clientSecret);
  const result = await fetch(config.tokenUrl, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: form,
    redirect: "error",
    signal: AbortSignal.timeout(oauthUpstreamTimeoutMs),
  });
  const body = await result.json();
  if (!result.ok || !body.access_token) {
    throw new Error(`MyAnimeList token exchange failed (${result.status}).`);
  }
  return {
    accessToken: body.access_token,
    refreshToken: body.refresh_token || null,
    expiresAt: body.expires_in
      ? new Date(Date.now() + Number(body.expires_in) * 1000).toISOString()
      : null,
  };
}

async function refreshMyAnimeListToken(request, response) {
  const config = providerConfig("myanimelist");
  if (!config.clientId || !config.clientSecret) {
    return json(response, 503, { error: "provider_not_configured" });
  }
  const body = await readJson(request, { requireBody: true });
  if (
    !body ||
    Array.isArray(body) ||
    typeof body !== "object" ||
    Object.keys(body).sort().join(",") !== "refresh_token"
  ) {
    return json(response, 400, { error: "invalid_refresh_token" });
  }
  const refreshToken = String(body.refresh_token || "");
  if (refreshToken.length < 20 || refreshToken.length > 4096) {
    return json(response, 400, { error: "invalid_refresh_token" });
  }
  const form = new URLSearchParams({
    grant_type: "refresh_token",
    client_id: config.clientId,
    refresh_token: refreshToken,
  });
  if (config.clientSecret) form.set("client_secret", config.clientSecret);
  const result = await fetch(config.tokenUrl, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: form,
    redirect: "error",
    signal: AbortSignal.timeout(oauthUpstreamTimeoutMs),
  });
  const tokenBody = await result.json();
  if (!result.ok || !tokenBody.access_token) {
    return json(response, 401, { error: "refresh_failed" });
  }
  return json(response, 200, {
    access_token: tokenBody.access_token,
    ...(tokenBody.refresh_token
      ? { refresh_token: tokenBody.refresh_token }
      : {}),
    ...(tokenBody.expires_in
      ? {
          expires_at: new Date(
            Date.now() + Number(tokenBody.expires_in) * 1000,
          ).toISOString(),
        }
      : {}),
  });
}

async function oauthCallback(response, url, provider) {
  cleanup();
  const state = String(url.searchParams.get("state") || "");
  const code = String(url.searchParams.get("code") || "");
  const pairing = [...pairings.values()].find(
    (value) =>
      value.provider === provider &&
      value.status === "pending" &&
      value.state &&
      safeEqual(value.state, state),
  );
  if (!pairing || !code) {
    return html(
      response,
      400,
      "<h1>Invalid callback</h1><p>Return to the TV and try again.</p>",
    );
  }
  try {
    // Claim this state before contacting the provider so concurrent callback
    // replays cannot fan one authorization code out into many token requests.
    pairing.status = "exchanging";
    pairing.tokenSet = await exchangeCode(pairing, code);
    pairing.status = "authorized";
    pairing.state = null;
    pairing.codeVerifier = null;
    return html(
      response,
      200,
      `<h1>Connected</h1><p>${providerConfig(provider).name} is linked. You can return to TetoTV.</p>`,
    );
  } catch (error) {
    pairing.status = "pending";
    // Provider responses can echo authorization codes or other sensitive
    // request details. Keep production logs useful without recording them.
    console.error(`${provider} OAuth callback failed (${error?.name || "Error"}).`);
    return html(
      response,
      502,
      "<h1>Connection failed</h1><p>Return to the TV and try again.</p>",
    );
  }
}

const releaseTagPattern = /^v(\d+\.\d+\.\d+)$/;
const repositoryPattern = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const allowedApkContentTypes = new Set([
  "application/octet-stream",
  "application/vnd.android.package-archive",
  "application/zip",
]);
const selfTestApk = selfTest ? Buffer.alloc(65_536, 0x5a) : null;
const selfTestGithubRequests = [];

function updateProxyConfigured({
  baseUrl = publicBaseUrl,
  repository = githubReleaseRepository,
  token = githubReleaseToken,
} = {}) {
  return (
    baseUrl.startsWith("https://") &&
    repositoryPattern.test(repository) &&
    token.length >= 20
  );
}

function parseBetaAccessKeyHashes(value) {
  return [...new Set(String(value || "").toLowerCase().split(/[\s,]+/))]
    .filter((candidate) => /^[0-9a-f]{64}$/.test(candidate))
    .slice(0, 32)
    .map((candidate) => Buffer.from(candidate, "hex"));
}

function betaUpdatesConfigured({
  updatesConfigured = updateProxyConfigured(),
  hashes = betaAccessKeyHashes,
} = {}) {
  return updatesConfigured && hashes.length > 0;
}

function betaUpdateAuthorized(request, hashes = betaAccessKeyHashes) {
  const authorization = String(request.headers.authorization || "");
  const match = authorization.match(/^Beta ([A-Za-z0-9_-]{32,128})$/);
  const candidate = digest(match?.[1] || "");
  let matched = 0;
  for (const expected of hashes) {
    matched |= timingSafeEqual(candidate, expected) ? 1 : 0;
  }
  return match !== null && hashes.length > 0 && matched === 1;
}

function betaAccessError(request, response, status, error, extraHeaders = {}) {
  if (request.method !== "HEAD") {
    return json(response, status, { error }, extraHeaders);
  }
  response.writeHead(status, {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    ...extraHeaders,
  });
  response.end();
}

function requireBetaUpdateAccess(request, response) {
  if (!betaUpdatesConfigured()) {
    betaAccessError(request, response, 503, "beta_updates_not_configured");
    return false;
  }
  if (betaUpdateAuthorized(request)) return true;
  if (rateLimited(request, 8, "beta-update-auth")) {
    betaAccessError(request, response, 429, "rate_limited", {
      "Retry-After": "60",
    });
    return false;
  }
  betaAccessError(request, response, 401, "beta_access_required", {
    "WWW-Authenticate": 'Beta realm="TetoTV Beta Updates"',
  });
  return false;
}

function githubRepositoryApiPath() {
  if (!repositoryPattern.test(githubReleaseRepository)) {
    throw new UpdateProxyError(503, "updates_not_configured");
  }
  const [owner, repository] = githubReleaseRepository.split("/");
  return `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}`;
}

function repositoryApiPath(repository) {
  if (!repositoryPattern.test(repository)) {
    throw new UpdateProxyError(503, "updates_not_configured");
  }
  const [owner, name] = repository.split("/");
  return `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(name)}`;
}

function githubHeaders({ accept = "application/vnd.github+json", token = true } = {}) {
  return {
    Accept: accept,
    "User-Agent": "TetoTV-update-broker",
    "X-GitHub-Api-Version": githubReleaseApiVersion,
    ...(token ? { Authorization: `Bearer ${githubReleaseToken}` } : {}),
  };
}

function cleanText(value, maximumLength) {
  return String(value || "")
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "")
    .slice(0, maximumLength);
}

function sanitizeLatestRelease(value) {
  if (!value || typeof value !== "object" || value.draft || value.prerelease) {
    throw new UpdateProxyError(502, "invalid_release_metadata");
  }
  const tagName = String(value.tag_name || "");
  const tagMatch = tagName.match(releaseTagPattern);
  if (!tagMatch) {
    throw new UpdateProxyError(502, "invalid_release_metadata");
  }
  const expectedAssetName = `TetoTV-${tagName}-universal.apk`;
  const matchingAssets = Array.isArray(value.assets)
    ? value.assets.filter((asset) => asset?.name === expectedAssetName)
    : [];
  if (matchingAssets.length !== 1) {
    throw new UpdateProxyError(502, "invalid_release_asset");
  }
  const asset = matchingAssets[0];
  const releaseId = Number(value.id);
  const assetId = Number(asset.id);
  const size = Number(asset.size);
  if (
    !Number.isSafeInteger(releaseId) ||
    releaseId <= 0 ||
    !Number.isSafeInteger(assetId) ||
    assetId <= 0 ||
    asset.state !== "uploaded" ||
    !Number.isSafeInteger(size) ||
    size < 65_536 ||
    size > maxReleaseAssetBytes
  ) {
    throw new UpdateProxyError(502, "invalid_release_asset");
  }
  const publishedAt = new Date(value.published_at || "");
  if (!Number.isFinite(publishedAt.getTime())) {
    throw new UpdateProxyError(502, "invalid_release_metadata");
  }
  const digestValue = String(asset.digest || "").toLowerCase();
  const digestValueIsValid = /^sha256:[0-9a-f]{64}$/.test(digestValue);
  return {
    releaseId,
    version: tagMatch[1],
    tagName,
    name: cleanText(value.name || `TetoTV ${tagName}`, 160),
    releaseNotes: cleanText(value.body, maxReleaseNotesLength),
    publishedAt: publishedAt.toISOString(),
    asset: {
      id: assetId,
      name: expectedAssetName,
      size,
      contentType: "application/vnd.android.package-archive",
      ...(digestValueIsValid ? { digest: digestValue } : {}),
    },
  };
}

async function selfTestGithubFetch(url, options = {}) {
  const parsed = new URL(url);
  const authorization = new Headers(options.headers).get("authorization");
  selfTestGithubRequests.push({
    hostname: parsed.hostname,
    pathname: parsed.pathname,
    authorization,
  });
  const repositoryPath = githubRepositoryApiPath();
  const publicRepositoryPath = repositoryApiPath(legacyPublicReleaseRepository);
  if (
    parsed.origin === "https://api.github.com" &&
    parsed.pathname === `${publicRepositoryPath}/releases/latest`
  ) {
    return new Response(
      JSON.stringify({
        id: 117,
        tag_name: "v1.0.0",
        name: "TetoTV 1.0.0",
        body: "Public migration release notes",
        draft: false,
        prerelease: false,
        published_at: "2026-08-13T00:00:00Z",
        assets: [
          {
            id: 117001,
            name: "TetoTV-v1.0.0-universal.apk",
            state: "uploaded",
            size: selfTestApk.length,
            content_type: "application/vnd.android.package-archive",
            digest:
              "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          },
        ],
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
  if (
    parsed.origin === "https://api.github.com" &&
    parsed.pathname === `${repositoryPath}/releases` &&
    parsed.searchParams.get("per_page") === "20" &&
    parsed.searchParams.get("page") === "1"
  ) {
    return new Response(
      JSON.stringify([
        {
          id: 116,
          tag_name: "v2.0.1",
          name: "TetoTV 2.0.1 Beta",
          body: "Current private release notes",
          draft: false,
          prerelease: false,
          published_at: "2026-08-13T02:00:00Z",
          assets: [
            {
              id: 116001,
              name: "TetoTV-v2.0.1-universal.apk",
              state: "uploaded",
              size: selfTestApk.length,
              content_type: "application/octet-stream",
              digest:
                "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            },
          ],
        },
        {
          id: 115,
          tag_name: "v2.0.0",
          name: "TetoTV 2.0.0 Beta",
          body: "Previous private release notes",
          draft: false,
          prerelease: false,
          published_at: "2026-08-13T01:00:00Z",
          assets: [
            {
              id: 115001,
              name: "TetoTV-v2.0.0-universal.apk",
              state: "uploaded",
              size: selfTestApk.length,
              content_type: "application/octet-stream",
              digest:
                "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
            },
          ],
        },
        {
          id: 114,
          tag_name: "v1.11.33",
          name: "Legacy Beta",
          body: "Must not be exposed in the v2 history.",
          draft: false,
          prerelease: false,
          published_at: "2026-08-12T01:00:00Z",
          assets: [],
        },
      ]),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
  if (
    parsed.origin === "https://api.github.com" &&
    (parsed.pathname === `${repositoryPath}/releases/tags/v2.0.0` ||
      parsed.pathname === `${repositoryPath}/releases/tags/v2.0.1`)
  ) {
    const previous = parsed.pathname.endsWith("/v2.0.0");
    return new Response(
      JSON.stringify({
        id: previous ? 115 : 116,
        tag_name: previous ? "v2.0.0" : "v2.0.1",
        name: previous ? "TetoTV 2.0.0 Beta" : "TetoTV 2.0.1 Beta",
        body: previous
          ? "Previous private release notes"
          : "Current private release notes",
        draft: false,
        prerelease: false,
        published_at: previous
          ? "2026-08-13T01:00:00Z"
          : "2026-08-13T02:00:00Z",
        assets: [
          {
            id: previous ? 115001 : 116001,
            name: previous
              ? "TetoTV-v2.0.0-universal.apk"
              : "TetoTV-v2.0.1-universal.apk",
            state: "uploaded",
            size: selfTestApk.length,
            content_type: "application/octet-stream",
            digest: previous
              ? "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
              : "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          },
        ],
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
  if (
    parsed.origin === "https://api.github.com" &&
    parsed.pathname === `${repositoryPath}/releases/latest`
  ) {
    return new Response(
      JSON.stringify({
        id: 116,
        tag_name: "v2.0.1",
        name: "TetoTV 2.0.1 Beta",
        body: "Private release notes",
        draft: false,
        prerelease: false,
        published_at: "2026-08-10T00:00:00Z",
        assets: [
          {
            id: 116001,
            name: "TetoTV-v2.0.1-universal.apk",
            state: "uploaded",
            size: selfTestApk.length,
            content_type: "application/octet-stream",
            digest:
              "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          },
        ],
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
  if (
    parsed.origin === "https://api.github.com" &&
    (parsed.pathname === `${repositoryPath}/releases/assets/116001` ||
      parsed.pathname === `${repositoryPath}/releases/assets/115001`)
  ) {
    return new Response(null, {
      status: 302,
      headers: {
        Location:
          parsed.pathname.endsWith("/115001")
            ? "https://release-assets.githubusercontent.com/tetotv/previous.apk?signature=hidden"
            : "https://release-assets.githubusercontent.com/tetotv/latest.apk?signature=hidden",
      },
    });
  }
  if (
    parsed.origin === "https://api.github.com" &&
    parsed.pathname === `${publicRepositoryPath}/releases/assets/117001`
  ) {
    return new Response(null, {
      status: 302,
      headers: {
        Location:
          "https://release-assets.githubusercontent.com/tetotv/public.apk?signature=hidden",
      },
    });
  }
  if (
    parsed.origin === "https://release-assets.githubusercontent.com" &&
    (parsed.pathname === "/tetotv/latest.apk" ||
      parsed.pathname === "/tetotv/previous.apk" ||
      parsed.pathname === "/tetotv/public.apk")
  ) {
    const requestedRange = new Headers(options.headers).get("range");
    const parsedRange = requestedRange
      ? parseSingleRange(requestedRange, selfTestApk.length)
      : null;
    if (requestedRange && !parsedRange) {
      return new Response(null, { status: 416 });
    }
    const start = parsedRange?.start ?? 0;
    const end = parsedRange?.end ?? selfTestApk.length - 1;
    const body = selfTestApk.subarray(start, end + 1);
    return new Response(body, {
      status: parsedRange ? 206 : 200,
      headers: {
        "Content-Type": "application/octet-stream",
        "Content-Length": String(body.length),
        ...(parsedRange
          ? {
              "Content-Range": `bytes ${start}-${end}/${selfTestApk.length}`,
            }
          : {}),
      },
    });
  }
  throw new Error("Unexpected mocked GitHub request.");
}

const githubFetch = selfTest ? selfTestGithubFetch : fetch;

async function requestGithubJson(path) {
  if (!updateProxyConfigured()) {
    throw new UpdateProxyError(503, "updates_not_configured");
  }
  let result;
  try {
    result = await githubFetch(
      `https://api.github.com${githubRepositoryApiPath()}${path}`,
      {
        headers: githubHeaders(),
        redirect: "error",
        signal: AbortSignal.timeout(10_000),
      },
    );
  } catch {
    throw new UpdateProxyError(502, "update_service_unavailable");
  }
  if (result.status === 404) {
    throw new UpdateProxyError(404, "update_not_found");
  }
  if (!result.ok) {
    throw new UpdateProxyError(502, "update_service_unavailable");
  }
  let body;
  try {
    body = await result.json();
  } catch {
    throw new UpdateProxyError(502, "invalid_release_metadata");
  }
  return body;
}

async function requestGithubRelease(path) {
  return sanitizeLatestRelease(await requestGithubJson(path));
}

async function requestGithubReleaseHistory() {
  const body = await requestGithubJson("/releases?per_page=20&page=1");
  if (!Array.isArray(body)) {
    throw new UpdateProxyError(502, "invalid_release_metadata");
  }
  const releases = body
    .filter(
      (value) =>
        value &&
        typeof value === "object" &&
        !value.draft &&
        !value.prerelease &&
        /^v2\.\d+\.\d+$/.test(String(value.tag_name || "")),
    )
    .map(sanitizeLatestRelease);
  if (releases.length === 0) {
    throw new UpdateProxyError(404, "update_not_found");
  }
  return releases;
}

async function requestLegacyPublicRelease() {
  let result;
  try {
    result = await githubFetch(
      `https://api.github.com${repositoryApiPath(legacyPublicReleaseRepository)}` +
        "/releases/latest",
      {
        headers: githubHeaders({ token: false }),
        redirect: "error",
        signal: AbortSignal.timeout(10_000),
      },
    );
  } catch {
    throw new UpdateProxyError(502, "update_service_unavailable");
  }
  if (result.status === 404) {
    throw new UpdateProxyError(404, "update_not_found");
  }
  if (!result.ok) {
    throw new UpdateProxyError(502, "update_service_unavailable");
  }
  let body;
  try {
    body = await result.json();
  } catch {
    throw new UpdateProxyError(502, "invalid_release_metadata");
  }
  const release = sanitizeLatestRelease(body);
  if (!/^1\.\d+\.\d+$/.test(release.version)) {
    throw new UpdateProxyError(502, "invalid_release_metadata");
  }
  return release;
}

async function fetchLegacyPublicRelease() {
  const now = Date.now();
  if (cachedLegacyPublicRelease?.expiresAt > now) {
    return cachedLegacyPublicRelease.release;
  }
  if (legacyPublicReleaseRequest) return legacyPublicReleaseRequest;
  legacyPublicReleaseRequest = (async () => {
    const release = await requestLegacyPublicRelease();
    cachedLegacyPublicRelease = {
      release,
      expiresAt: Date.now() + releaseMetadataTtlMs,
    };
    return release;
  })();
  try {
    return await legacyPublicReleaseRequest;
  } finally {
    legacyPublicReleaseRequest = null;
  }
}

function cacheVersionedRelease(release, now = Date.now()) {
  for (const [tag, cached] of cachedVersionedReleases) {
    if (cached.expiresAt <= now) cachedVersionedReleases.delete(tag);
  }
  while (cachedVersionedReleases.size >= 32) {
    cachedVersionedReleases.delete(cachedVersionedReleases.keys().next().value);
  }
  cachedVersionedReleases.set(release.tagName, {
    release,
    expiresAt: now + versionedReleaseTtlMs,
  });
}

async function fetchLatestRelease() {
  const now = Date.now();
  if (cachedLatestRelease?.expiresAt > now) {
    return cachedLatestRelease.release;
  }
  if (latestReleaseRequest) return latestReleaseRequest;
  latestReleaseRequest = (async () => {
    const release = await requestGithubRelease("/releases/latest");
    const receivedAt = Date.now();
    cachedLatestRelease = {
      release,
      expiresAt: receivedAt + releaseMetadataTtlMs,
    };
    cacheVersionedRelease(release, receivedAt);
    return release;
  })();
  try {
    return await latestReleaseRequest;
  } finally {
    latestReleaseRequest = null;
  }
}

async function fetchReleaseHistory() {
  const now = Date.now();
  if (cachedReleaseHistory?.expiresAt > now) {
    return cachedReleaseHistory.releases;
  }
  if (releaseHistoryRequest) return releaseHistoryRequest;
  releaseHistoryRequest = (async () => {
    const releases = await requestGithubReleaseHistory();
    const receivedAt = Date.now();
    for (const release of releases) cacheVersionedRelease(release, receivedAt);
    cachedReleaseHistory = {
      releases,
      expiresAt: receivedAt + releaseMetadataTtlMs,
    };
    return releases;
  })();
  try {
    return await releaseHistoryRequest;
  } finally {
    releaseHistoryRequest = null;
  }
}

async function fetchReleaseByTag(tagName) {
  if (!/^v2\.\d+\.\d+$/.test(tagName)) {
    throw new UpdateProxyError(404, "update_not_found");
  }
  const now = Date.now();
  const cached = cachedVersionedReleases.get(tagName);
  if (cached?.expiresAt > now) return cached.release;
  if (cached) cachedVersionedReleases.delete(tagName);
  const release = await requestGithubRelease(
    `/releases/tags/${encodeURIComponent(tagName)}`,
  );
  if (release.tagName !== tagName) {
    throw new UpdateProxyError(404, "update_not_found");
  }
  cacheVersionedRelease(release);
  return release;
}

function publicReleaseMetadata(release) {
  return {
    version: release.version,
    tag_name: release.tagName,
    name: release.name,
    release_notes: release.releaseNotes,
    published_at: release.publishedAt,
    asset: {
      name: release.asset.name,
      size: release.asset.size,
      content_type: release.asset.contentType,
      download_url:
        `${publicBaseUrl}/v1/app-updates/releases/${release.tagName}` +
        `/assets/${release.asset.id}/universal.apk`,
      ...(release.asset.digest ? { digest: release.asset.digest } : {}),
    },
  };
}

function legacyPublicReleaseMetadata(release) {
  return {
    version: legacyPublicAliasVersion,
    tag_name: legacyPublicAliasTag,
    name: "TetoTV Public migration",
    release_notes:
      "One-time migration from legacy TetoTV 1.11.x to the Public release channel.",
    published_at: release.publishedAt,
    asset: {
      name: `TetoTV-${legacyPublicAliasTag}-universal.apk`,
      size: release.asset.size,
      content_type: release.asset.contentType,
      download_url:
        `${publicBaseUrl}/v1/app-updates/releases/${legacyPublicAliasTag}` +
        `/assets/${release.asset.id}/universal.apk`,
      ...(release.asset.digest ? { digest: release.asset.digest } : {}),
    },
  };
}

async function latestReleaseMetadata(response) {
  const release = await fetchLatestRelease();
  return json(response, 200, publicReleaseMetadata(release));
}

async function releaseHistoryMetadata(response) {
  const releases = await fetchReleaseHistory();
  return json(response, 200, {
    releases: releases.map(publicReleaseMetadata),
  });
}

async function legacyPublicReleaseMetadataResponse(response) {
  const release = await fetchLegacyPublicRelease();
  return json(response, 200, legacyPublicReleaseMetadata(release));
}

function parseSingleRange(value, size) {
  const match = String(value || "").match(/^bytes=(\d*)-(\d*)$/);
  if (!match || (!match[1] && !match[2])) return null;
  let start;
  let end;
  if (!match[1]) {
    const suffixLength = Number(match[2]);
    if (!Number.isSafeInteger(suffixLength) || suffixLength <= 0) return null;
    start = Math.max(0, size - suffixLength);
    end = size - 1;
  } else {
    start = Number(match[1]);
    end = match[2] ? Number(match[2]) : size - 1;
    if (
      !Number.isSafeInteger(start) ||
      !Number.isSafeInteger(end) ||
      start < 0 ||
      start >= size ||
      end < start
    ) {
      return null;
    }
    end = Math.min(end, size - 1);
  }
  return { start, end, header: `bytes=${start}-${end}` };
}

function allowedGithubDownloadUrl(url) {
  if (url.protocol !== "https:" || url.username || url.password) return false;
  const hostname = url.hostname.toLowerCase();
  return (
    hostname === "github.com" ||
    hostname === "objects.githubusercontent.com" ||
    hostname === "release-assets.githubusercontent.com"
  );
}

async function fetchGithubAsset(
  release,
  range,
  signal,
  repository = githubReleaseRepository,
  includeToken = true,
) {
  let currentUrl = new URL(
    `https://api.github.com${repositoryApiPath(repository)}/releases/assets/${release.asset.id}`,
  );
  let firstRequest = true;
  for (let redirectCount = 0; redirectCount <= 3; redirectCount += 1) {
    let result;
    try {
      result = await githubFetch(currentUrl, {
        headers: {
          ...githubHeaders({
            accept: "application/octet-stream",
            token: firstRequest && includeToken,
          }),
          ...(range ? { Range: range.header } : {}),
        },
        redirect: "manual",
        signal,
      });
    } catch {
      throw new UpdateProxyError(502, "update_download_unavailable");
    }
    if ([301, 302, 303, 307, 308].includes(result.status)) {
      if (redirectCount >= 3) {
        throw new UpdateProxyError(502, "update_download_unavailable");
      }
      const location = result.headers.get("location");
      let redirected;
      try {
        redirected = new URL(location || "", currentUrl);
      } catch {
        throw new UpdateProxyError(502, "update_download_unavailable");
      }
      if (!allowedGithubDownloadUrl(redirected)) {
        throw new UpdateProxyError(502, "update_download_unavailable");
      }
      currentUrl = redirected;
      firstRequest = false;
      continue;
    }
    const expectedStatus = range ? 206 : 200;
    if (result.status !== expectedStatus || !result.body) {
      throw new UpdateProxyError(502, "update_download_unavailable");
    }
    return result;
  }
  throw new UpdateProxyError(502, "update_download_unavailable");
}

function apkHeaders(release, range = null) {
  const length = range
    ? range.end - range.start + 1
    : release.asset.size;
  return {
    "Content-Type": "application/vnd.android.package-archive",
    "Content-Length": String(length),
    "Content-Disposition": `attachment; filename="${release.asset.name}"`,
    ETag: `"asset-${release.asset.id}-${release.asset.size}"`,
    "Accept-Ranges": "bytes",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Cross-Origin-Resource-Policy": "same-origin",
    ...(range
      ? {
          "Content-Range": `bytes ${range.start}-${range.end}/${release.asset.size}`,
        }
      : {}),
  };
}

async function downloadRelease(
  request,
  response,
  tagName,
  assetId,
  { legacyPublic = false } = {},
) {
  const release = legacyPublic
    ? await fetchLegacyPublicRelease()
    : await fetchReleaseByTag(tagName);
  if (release.asset.id !== assetId) {
    throw new UpdateProxyError(404, "update_not_found");
  }
  const etag = `"asset-${release.asset.id}-${release.asset.size}"`;
  const rangeHeader =
    request.headers["if-range"] && request.headers["if-range"] !== etag
      ? null
      : request.headers.range;
  const range = rangeHeader
    ? parseSingleRange(rangeHeader, release.asset.size)
    : null;
  if (rangeHeader && !range) {
    response.writeHead(416, {
      "Content-Range": `bytes */${release.asset.size}`,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    });
    return response.end();
  }
  if (request.method === "HEAD") {
    response.writeHead(range ? 206 : 200, apkHeaders(release, range));
    return response.end();
  }

  const abortController = new AbortController();
  const timeout = setTimeout(() => abortController.abort(), 20 * 60 * 1000);
  timeout.unref?.();
  request.once("aborted", () => abortController.abort());
  const abortOnDisconnect = () => {
    if (!response.writableFinished) abortController.abort();
  };
  response.once("close", abortOnDisconnect);
  try {
    const upstream = await fetchGithubAsset(
      release,
      range,
      abortController.signal,
      legacyPublic ? legacyPublicReleaseRepository : githubReleaseRepository,
      !legacyPublic,
    );
    const contentType = String(upstream.headers.get("content-type") || "")
      .split(";", 1)[0]
      .trim()
      .toLowerCase();
    if (!allowedApkContentTypes.has(contentType)) {
      throw new UpdateProxyError(502, "invalid_release_asset");
    }
    const expectedLength = range
      ? range.end - range.start + 1
      : release.asset.size;
    const upstreamLength = Number(upstream.headers.get("content-length"));
    if (
      upstream.headers.has("content-length") &&
      (!Number.isSafeInteger(upstreamLength) || upstreamLength !== expectedLength)
    ) {
      throw new UpdateProxyError(502, "invalid_release_asset");
    }
    if (range) {
      const expectedContentRange =
        `bytes ${range.start}-${range.end}/${release.asset.size}`;
      if (upstream.headers.get("content-range") !== expectedContentRange) {
        throw new UpdateProxyError(502, "invalid_release_asset");
      }
    }

    response.writeHead(range ? 206 : 200, apkHeaders(release, range));
    let received = 0;
    const enforceLength = new Transform({
      transform(chunk, _encoding, callback) {
        received += chunk.length;
        if (received > expectedLength) {
          callback(new Error("Upstream asset exceeded its declared size."));
        } else {
          callback(null, chunk);
        }
      },
      flush(callback) {
        callback(
          received === expectedLength
            ? null
            : new Error("Upstream asset ended before its declared size."),
        );
      },
    });
    try {
      await pipeline(Readable.fromWeb(upstream.body), enforceLength, response);
    } catch {
      response.destroy();
    }
  } finally {
    clearTimeout(timeout);
    response.off("close", abortOnDisconnect);
  }
}

const server = createServer(
  {
    maxHeaderSize: 16_384,
    headersTimeout: 10_000,
    requestTimeout: 20_000,
  },
  async (request, response) => {
  applyGlobalSecurityHeaders(response);
  try {
    if (rateLimited(request)) {
      return json(
        response,
        429,
        { error: "rate_limited" },
        { "Retry-After": "60" },
      );
    }
    const url = new URL(
      request.url || "/",
      publicBaseUrl || "http://localhost",
    );
    if (request.method === "GET" && url.pathname === "/health") {
      return json(response, 200, {
        status: "ok",
        privacy_policy: true,
        privacy_policy_url: `${publicBaseUrl}/privacy`,
        providers: {
          anilist:
            Boolean(process.env.ANILIST_CLIENT_ID) &&
            Boolean(process.env.ANILIST_CLIENT_SECRET),
          myanimelist:
            Boolean(process.env.MAL_CLIENT_ID) &&
            Boolean(process.env.MAL_CLIENT_SECRET),
        },
        callbacks: {
          anilist: callbackUrl("anilist"),
          myanimelist: callbackUrl("myanimelist"),
        },
        source_pairing: true,
        source_pairing_version: 2,
        app_presence: true,
        crash_reporting: crashReportingConfigured(),
        beta_updates_configured: betaUpdatesConfigured(),
      });
    }
    if (request.method === "GET" && url.pathname === "/privacy") {
      return privacyPage(response);
    }
    if (
      request.method === "POST" &&
      url.pathname === "/v1/app-presence/sessions"
    ) {
      if (rateLimited(request, 10, "presence-create")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return await createAppPresenceSession(request, response);
    }
    if (
      request.method === "PUT" &&
      url.pathname === "/v1/app-presence/sessions/current"
    ) {
      if (rateLimited(request, 10, "presence-heartbeat")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return await updateAppPresenceSession(request, response);
    }
    if (
      request.method === "DELETE" &&
      url.pathname === "/v1/app-presence/sessions/current"
    ) {
      if (rateLimited(request, 10, "presence-close")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return await closeAppPresenceSession(request, response);
    }
    if (
      request.method === "GET" &&
      url.pathname === "/v1/app-presence/summary"
    ) {
      if (rateLimited(request, 60, "presence-summary")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return appPresenceSummary(response);
    }
    if (request.method === "POST" && url.pathname === "/v1/crash-reports") {
      if (rateLimited(request, 4, "anonymous-crash-report")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return await receiveCrashReport(request, response);
    }
    if (
      request.method === "GET" &&
      url.pathname === "/v1/app-updates/latest"
    ) {
      if (rateLimited(request, 60, "update-metadata")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      if (!request.headers.authorization) {
        return await legacyPublicReleaseMetadataResponse(response);
      }
      if (!requireBetaUpdateAccess(request, response)) return;
      return await latestReleaseMetadata(response);
    }
    if (
      request.method === "GET" &&
      url.pathname === "/v1/app-updates/releases"
    ) {
      if (!requireBetaUpdateAccess(request, response)) return;
      if (rateLimited(request, 30, "update-history")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return await releaseHistoryMetadata(response);
    }
    const updateDownloadMatch = url.pathname.match(
      /^\/v1\/app-updates\/releases\/(v\d+\.\d+\.\d+)\/assets\/([1-9]\d*)\/universal\.apk$/,
    );
    if (
      (request.method === "GET" || request.method === "HEAD") &&
      updateDownloadMatch
    ) {
      const isLegacyPublicRequest =
        !request.headers.authorization &&
        updateDownloadMatch[1] === legacyPublicAliasTag;
      if (isLegacyPublicRequest) {
        if (
          request.method === "GET" &&
          rateLimited(request, 4, "legacy-update-download")
        ) {
          return json(
            response,
            429,
            { error: "rate_limited" },
            { "Retry-After": "60" },
          );
        }
        const legacyRelease = await fetchLegacyPublicRelease();
        const assetId = Number(updateDownloadMatch[2]);
        if (legacyRelease.asset.id !== assetId) {
          return json(response, 404, { error: "update_not_found" });
        }
        if (request.method === "GET") {
          if (globallyRateLimitedUpdateDownload()) {
            return json(
              response,
              429,
              { error: "rate_limited" },
              { "Retry-After": "60" },
            );
          }
          if (activeUpdateDownloads >= maxConcurrentUpdateDownloads) {
            return json(
              response,
              503,
              { error: "update_download_busy" },
              { "Retry-After": "10" },
            );
          }
          activeUpdateDownloads += 1;
          try {
            return await downloadRelease(
              request,
              response,
              legacyPublicAliasTag,
              assetId,
              { legacyPublic: true },
            );
          } finally {
            activeUpdateDownloads -= 1;
          }
        }
        return await downloadRelease(
          request,
          response,
          legacyPublicAliasTag,
          assetId,
          { legacyPublic: true },
        );
      }
      if (!requireBetaUpdateAccess(request, response)) return;
      if (
        request.method === "GET" &&
        rateLimited(request, 4, "update-download")
      ) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      const assetId = Number(updateDownloadMatch[2]);
      if (!Number.isSafeInteger(assetId)) {
        return json(response, 404, { error: "update_not_found" });
      }
      if (request.method === "GET") {
        if (globallyRateLimitedUpdateDownload()) {
          return json(
            response,
            429,
            { error: "rate_limited" },
            { "Retry-After": "60" },
          );
        }
        if (activeUpdateDownloads >= maxConcurrentUpdateDownloads) {
          return json(
            response,
            503,
            { error: "update_download_busy" },
            { "Retry-After": "10" },
          );
        }
        activeUpdateDownloads += 1;
        try {
          return await downloadRelease(
            request,
            response,
            updateDownloadMatch[1],
            assetId,
          );
        } finally {
          activeUpdateDownloads -= 1;
        }
      }
      return await downloadRelease(
        request,
        response,
        updateDownloadMatch[1],
        assetId,
      );
    }
    if (request.method === "POST" && url.pathname === "/v1/source-pairings") {
      if (rateLimited(request, 5, "source-create")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return await createSourcePairing(request, response);
    }
    const sourceCompleteMatch = url.pathname.match(
      /^\/v1\/source-pairings\/([A-Za-z0-9_-]+)\/complete$/,
    );
    if (request.method === "POST" && sourceCompleteMatch) {
      if (rateLimited(request, 30, "source-complete")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return await completeSourcePairing(
        request,
        response,
        sourceCompleteMatch[1],
      );
    }
    const sourcePollMatch = url.pathname.match(
      /^\/v1\/source-pairings\/([A-Za-z0-9_-]+)$/,
    );
    if (request.method === "GET" && sourcePollMatch) {
      if (rateLimited(request, 240, "source-poll")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return pollSourcePairing(request, response, sourcePollMatch[1]);
    }
    if (request.method === "DELETE" && sourcePollMatch) {
      if (rateLimited(request, 30, "source-cancel")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return cancelSourcePairing(request, response, sourcePollMatch[1]);
    }
    if (request.method === "GET" && url.pathname === "/source-pair") {
      return sourcePairingPage(response, url);
    }
    const sourceReceiptMatch = url.pathname.match(
      /^\/source-pair\/status\/([A-Za-z0-9_-]{20,80})$/,
    );
    if (request.method === "GET" && sourceReceiptMatch) {
      return sourceReceiptPage(response, sourceReceiptMatch[1]);
    }
    if (request.method === "POST" && url.pathname === "/source-pair") {
      if (rateLimited(request, 10, "source-submit")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return await submitSourcePairing(request, response);
    }
    const createMatch = url.pathname.match(
      /^\/v1\/(anilist|myanimelist)\/pairings$/,
    );
    if (request.method === "POST" && createMatch) {
      if (rateLimited(request, 5, "oauth-create")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return await createPairing(request, response, createMatch[1]);
    }
    const pollMatch = url.pathname.match(
      /^\/v1\/(anilist|myanimelist)\/pairings\/([A-Za-z0-9_-]+)$/,
    );
    if (request.method === "GET" && pollMatch) {
      if (rateLimited(request, 180, "oauth-poll")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return pollPairing(request, response, pollMatch[1], pollMatch[2]);
    }
    if (
      request.method === "POST" &&
      url.pathname === "/v1/myanimelist/token/refresh"
    ) {
      if (rateLimited(request, 10, "oauth-refresh")) {
        return json(
          response,
          429,
          { error: "rate_limited" },
          { "Retry-After": "60" },
        );
      }
      return await refreshMyAnimeListToken(request, response);
    }
    if (request.method === "GET" && url.pathname === "/pair") {
      return pairingPage(response, url);
    }
    if (request.method === "GET" && url.pathname === "/authorize") {
      return startAuthorization(response, url);
    }
    const callbackMatch = url.pathname.match(
      /^\/oauth\/(anilist|myanimelist)\/callback$/,
    );
    if (request.method === "GET" && callbackMatch) {
      return await oauthCallback(response, url, callbackMatch[1]);
    }
    return json(response, 404, { error: "not_found" });
  } catch (error) {
    if (error instanceof UpdateProxyError) {
      return json(response, error.status, { error: error.code });
    }
    if (error instanceof RequestInputError) {
      return json(response, error.status, { error: "invalid_request" });
    }
    if (error instanceof SyntaxError) {
      return json(response, 400, { error: "invalid_json" });
    }
    // Never write request bodies, URLs, OAuth codes, or provider response
    // details to production logs. The error class is sufficient for alerting.
    console.error(`Broker request failed (${error?.name || "Error"}).`);
    return json(response, 500, { error: "internal_error" });
  }
  },
);

server.listen(port, async () => {
  console.log(`TetoTV auth broker listening on port ${port}`);
  if (selfTest) {
    try {
      const healthResponse = await fetch(`http://127.0.0.1:${port}/health`);
      const health = await healthResponse.json();
      const privacyResponse = await fetch(`http://127.0.0.1:${port}/privacy`);
      const privacyBody = await privacyResponse.text();
      const presenceCreateResponse = await fetch(
        `http://127.0.0.1:${port}/v1/app-presence/sessions`,
        { method: "POST" },
      );
      const presenceSession = await presenceCreateResponse.json();
      const presenceBefore = await fetch(
        `http://127.0.0.1:${port}/v1/app-presence/summary`,
      ).then((response) => response.json());
      const presenceHeartbeatResponse = await fetch(
        `http://127.0.0.1:${port}/v1/app-presence/sessions/current`,
        {
          method: "PUT",
          headers: {
            Authorization: `Bearer ${presenceSession.session_token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ state: "streaming" }),
        },
      );
      const presenceAfter = await fetch(
        `http://127.0.0.1:${port}/v1/app-presence/summary`,
      ).then((response) => response.json());
      const invalidPresenceResponse = await fetch(
        `http://127.0.0.1:${port}/v1/app-presence/sessions/current`,
        {
          method: "PUT",
          headers: {
            Authorization: `Bearer ${"x".repeat(43)}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ state: "active" }),
        },
      );
      const presenceCloseResponse = await fetch(
        `http://127.0.0.1:${port}/v1/app-presence/sessions/current`,
        {
          method: "DELETE",
          headers: {
            Authorization: `Bearer ${presenceSession.session_token}`,
          },
        },
      );
      const presenceClosed = await fetch(
        `http://127.0.0.1:${port}/v1/app-presence/summary`,
      ).then((response) => response.json());
      const crashReportResponse = await fetch(
        `http://127.0.0.1:${port}/v1/crash-reports`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            schema_version: 1,
            event_id: "self-test-event-123456",
            kind: "native",
            message:
              "Decoder failed at https://signed.example/private " +
              "content://media.documents/document/video%3Aprivate-show.mkv " +
              `${"a".repeat(64)}\n` +
              "/storage/emulated/0/Private Show Episode 7.mkv",
            stack:
              "Bearer never-forward-this-token token=also-private\n" +
              "C:\\Users\\Viewer\\Videos\\Private Episode 8.mkv\n" +
              "at dev.animetv.anime_tv.player.Media3PlayerActivity.onDestroy" +
              "(Media3PlayerActivity.kt:169)",
            occurred_at: new Date().toISOString(),
            app_version: "1.11.27",
            build_number: 340001,
            android_sdk: 36,
            abi: "arm64-v8a",
            device_class: "tv",
          }),
        },
      );
      const crashReportBody = await crashReportResponse.json();
      const betaAuthorization = {
        Authorization: `Beta ${selfTestBetaAccessKey}`,
      };
      const anonymousUpdateMetadataResponse = await fetch(
        `http://127.0.0.1:${port}/v1/app-updates/latest`,
      );
      const legacyUpdateMetadata = await anonymousUpdateMetadataResponse.json();
      const legacyAdvertisedUrl = new URL(
        legacyUpdateMetadata.asset.download_url,
      );
      const localLegacyUpdateUrl =
        `http://127.0.0.1:${port}${legacyAdvertisedUrl.pathname}`;
      const legacyUpdateHead = await fetch(localLegacyUpdateUrl, {
        method: "HEAD",
      });
      const legacyUpdateDownload = await fetch(localLegacyUpdateUrl);
      const legacyUpdateDownloadBody = Buffer.from(
        await legacyUpdateDownload.arrayBuffer(),
      );
      const legacyUpdateRange = await fetch(localLegacyUpdateUrl, {
        headers: { Range: "bytes=16-31" },
      });
      const legacyUpdateRangeBody = Buffer.from(
        await legacyUpdateRange.arrayBuffer(),
      );
      const invalidUpdateMetadataResponse = await fetch(
        `http://127.0.0.1:${port}/v1/app-updates/latest`,
        { headers: { Authorization: `Beta ${"C".repeat(43)}` } },
      );
      const betaAuthRateResponses = [];
      for (let index = 0; index < 9; index += 1) {
        betaAuthRateResponses.push(
          await fetch(
            `http://127.0.0.1:${port}/v1/app-updates/latest`,
            {
              headers: {
                Authorization: `Beta ${"D".repeat(43)}`,
                "X-Forwarded-For": "self-test-beta-auth-rate",
              },
            },
          ),
        );
      }
      const updateMetadataResponse = await fetch(
        `http://127.0.0.1:${port}/v1/app-updates/latest`,
        { headers: betaAuthorization },
      );
      const updateMetadata = await updateMetadataResponse.json();
      const updateHistoryResponse = await fetch(
        `http://127.0.0.1:${port}/v1/app-updates/releases`,
        { headers: betaAuthorization },
      );
      const updateHistory = await updateHistoryResponse.json();
      const advertisedUpdateUrl = new URL(updateMetadata.asset.download_url);
      const localUpdateUrl =
        `http://127.0.0.1:${port}${advertisedUpdateUrl.pathname}`;
      // Force the first binary request through the immutable tag lookup rather
      // than relying on metadata's in-memory release object.
      cachedVersionedReleases.clear();
      const anonymousUpdateHead = await fetch(localUpdateUrl, {
        method: "HEAD",
      });
      const updateHead = await fetch(
        localUpdateUrl,
        { method: "HEAD", headers: betaAuthorization },
      );
      const anonymousUpdateDownload = await fetch(localUpdateUrl);
      const updateDownload = await fetch(localUpdateUrl, {
        headers: betaAuthorization,
      });
      const updateDownloadBody = Buffer.from(
        await updateDownload.arrayBuffer(),
      );
      const updateRange = await fetch(localUpdateUrl, {
        headers: { ...betaAuthorization, Range: "bytes=16-31" },
      });
      const updateRangeBody = Buffer.from(await updateRange.arrayBuffer());
      const invalidUpdateRange = await fetch(localUpdateUrl, {
        headers: {
          ...betaAuthorization,
          Range: "bytes=999999-1000000",
        },
      });
      const mismatchedIfRange = await fetch(localUpdateUrl, {
        method: "HEAD",
        headers: {
          ...betaAuthorization,
          Range: "bytes=16-31",
          "If-Range": '"old-asset"',
        },
      });
      const wrongAssetDownload = await fetch(
        localUpdateUrl.replace("/assets/116001/", "/assets/116002/"),
        { headers: betaAuthorization },
      );
      const wrongAssetBody = await wrongAssetDownload.text();
      const previousUpdateUrl = new URL(
        updateHistory.releases?.[1]?.asset?.download_url || "https://invalid/",
      );
      cachedVersionedReleases.clear();
      const previousUpdateDownload = await fetch(
        `http://127.0.0.1:${port}${previousUpdateUrl.pathname}`,
        {
          headers: {
            ...betaAuthorization,
            "X-Forwarded-For": "self-test-beta-history-download",
          },
        },
      );
      const previousUpdateDownloadBody = Buffer.from(
        await previousUpdateDownload.arrayBuffer(),
      );
      const pairing = await fetch(
        `http://127.0.0.1:${port}/v1/anilist/pairings`,
        { method: "POST" },
      ).then((response) => response.json());
      const pending = await fetch(
        `http://127.0.0.1:${port}/v1/anilist/pairings/${pairing.pairing_id}`,
        {
          headers: {
            Authorization: `Pairing ${pairing.device_code}`,
          },
        },
      ).then((response) => response.json());
      const manualPage = await fetch(
        `http://127.0.0.1:${port}/pair`,
      ).then((response) => response.text());
      const malPairing = await fetch(
        `http://127.0.0.1:${port}/v1/myanimelist/pairings`,
        { method: "POST" },
      ).then((response) => response.json());
      const oauthRateResponses = await Promise.all(
        Array.from({ length: 6 }, () =>
          fetch(`http://127.0.0.1:${port}/v1/anilist/pairings`, {
            method: "POST",
            headers: { "X-Forwarded-For": "self-test-oauth-create-rate" },
          }),
        ),
      );
      const oversizedForwardedRateResponses = [];
      for (let index = 0; index < 6; index += 1) {
        oversizedForwardedRateResponses.push(
          await fetch(`http://127.0.0.1:${port}/v1/anilist/pairings`, {
            method: "POST",
            headers: {
              "X-Forwarded-For":
                `${String(index).repeat(3_000)}, 203.0.113.10`,
            },
          }),
        );
      }
      const oauthRefreshRateResponses = [];
      for (let index = 0; index < 11; index += 1) {
        oauthRefreshRateResponses.push(
          await fetch(
            `http://127.0.0.1:${port}/v1/myanimelist/token/refresh`,
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                "X-Forwarded-For": "self-test-oauth-refresh-rate",
              },
              body: JSON.stringify({ refresh_token: "short" }),
            },
          ),
        );
      }
      const capacityIds = [];
      while (pairings.size < maxOAuthPairings) {
        const id = `self-test-capacity-${capacityIds.length}`;
        const userCode = `CAP-${capacityIds.length}`;
        capacityIds.push(id);
        pairings.set(id, {
          provider: "anilist",
          userCode,
          deviceHash: digest("self-test"),
          expiresAt: Date.now() + ttlMs,
          status: "pending",
          tokenSet: null,
          state: null,
          codeVerifier: null,
        });
        codes.set(userCode, id);
      }
      const oauthCapacityResponse = await fetch(
        `http://127.0.0.1:${port}/v1/anilist/pairings`,
        {
          method: "POST",
          headers: { "X-Forwarded-For": "self-test-oauth-capacity" },
        },
      );
      for (const id of capacityIds) {
        const pairing = pairings.get(id);
        if (pairing) codes.delete(pairing.userCode);
        pairings.delete(id);
      }
      const malAuthorize = await fetch(
        `http://127.0.0.1:${port}/authorize?code=${encodeURIComponent(malPairing.user_code)}`,
        { redirect: "manual" },
      );
      const malAuthorizeUrl = new URL(malAuthorize.headers.get("location"));
      const sourceWrongContentType = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings`,
        { method: "POST", body: "{}" },
      );
      const sourceUnexpectedBody = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: '{"unexpected":true}',
        },
      );
      const sourceMalformedBody = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Forwarded-For": "untrusted, self-test-malformed",
          },
          body: "{bad",
        },
      );
      const misplacedMarketplaceUrl =
        "https://raw.githubusercontent.com/example/project/refs/heads/main/marketplace.json";
      const misplacedMarketplacePairing = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Forwarded-For": "self-test-misplaced-marketplace",
          },
          body: "{}",
        },
      ).then((response) => response.json());
      const misplacedMarketplaceResponse = await fetch(
        `http://127.0.0.1:${port}/source-pair`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded",
            "X-Forwarded-For": "self-test-misplaced-marketplace",
          },
          body: new URLSearchParams({
            code: misplacedMarketplacePairing.user_code,
            manifest_urls: misplacedMarketplaceUrl,
          }),
        },
      );
      const misplacedMarketplacePage =
        await misplacedMarketplaceResponse.text();
      const sourcePairing = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: "{}",
        },
      ).then((response) => response.json());
      const sourcePageResponse = await fetch(
        `http://127.0.0.1:${port}/source-pair?code=${encodeURIComponent(sourcePairing.user_code)}`,
      );
      const sourcePage = await sourcePageResponse.text();
      const sourceForm = (repositoryUrl) =>
        new URLSearchParams({
          code: sourcePairing.user_code,
          repository_urls: repositoryUrl,
          manifest_urls: "https://example.com/addon/manifest.json",
        });
      const parallelSubmissions = await Promise.all([
        fetch(`http://127.0.0.1:${port}/source-pair`, {
          method: "POST",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: sourceForm("https://example.com/first.json"),
        }),
        fetch(`http://127.0.0.1:${port}/source-pair`, {
          method: "POST",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: sourceForm("https://example.com/second.json"),
        }),
      ]);
      const sourceSubmitSuccess = parallelSubmissions.find(
        (value) => value.status === 200,
      );
      if (!sourceSubmitSuccess) {
        throw new Error("Source submission did not return a confirmation.");
      }
      const sourceSubmitPage = await sourceSubmitSuccess.text();
      const sourceReceiptPath = sourceSubmitPage.match(
        /\/source-pair\/status\/[A-Za-z0-9_-]{20,80}/,
      )?.[0];
      if (!sourceReceiptPath) {
        throw new Error("Source submission did not issue a receipt.");
      }
      const sourcePostSubmitExpiresAt = sourcePairings.get(
        sourcePairing.pairing_id,
      )?.expiresAt;
      const sourceWaitingPage = await fetch(
        `http://127.0.0.1:${port}${sourceReceiptPath}`,
      ).then((response) => response.text());
      const sourceUnauthorized = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings/${sourcePairing.pairing_id}`,
        { headers: { Authorization: "Pairing wrong-device-code" } },
      );
      const sourcePollUrl =
        `http://127.0.0.1:${port}/v1/source-pairings/${sourcePairing.pairing_id}`;
      const parallelDevicePolls = await Promise.all([
        fetch(sourcePollUrl, {
          headers: {
            Authorization: `Pairing ${sourcePairing.device_code}`,
          },
        }),
        fetch(sourcePollUrl, {
          headers: {
            Authorization: `Pairing ${sourcePairing.device_code}`,
          },
        }),
      ]);
      if (parallelDevicePolls.some((value) => value.status !== 200)) {
        throw new Error("Authenticated source redelivery was not idempotent.");
      }
      const [sourceResult, sourceRedelivery] = await Promise.all(
        parallelDevicePolls.map((value) => value.json()),
      );
      const sourceCompleteUrl = `${sourcePollUrl}/complete`;
      const completionHeaders = {
        Authorization: `Pairing ${sourcePairing.device_code}`,
        "Content-Type": "application/json",
      };
      const invalidSourceCompletion = await fetch(sourceCompleteUrl, {
        method: "POST",
        headers: completionHeaders,
        body: JSON.stringify({
          repositories_saved: 2,
          manifests_saved: 1,
          rejected_count: 0,
        }),
      });
      const sourceRetryAfterBadAck = await fetch(sourcePollUrl, {
        headers: {
          Authorization: `Pairing ${sourcePairing.device_code}`,
        },
      }).then((response) => response.json());
      const sourceCompletion = await fetch(sourceCompleteUrl, {
        method: "POST",
        headers: completionHeaders,
        body: JSON.stringify({
          repositories_saved: 1,
          manifests_saved: 1,
          rejected_count: 0,
        }),
      });
      const sourceCompletionReplay = await fetch(sourceCompleteUrl, {
        method: "POST",
        headers: completionHeaders,
        body: JSON.stringify({
          repositories_saved: 1,
          manifests_saved: 1,
          rejected_count: 0,
        }),
      });
      const sourceCompletedPage = await fetch(
        `http://127.0.0.1:${port}${sourceReceiptPath}`,
      ).then((response) => response.text());
      const sourceCompletedPoll = await fetch(sourcePollUrl, {
        headers: {
          Authorization: `Pairing ${sourcePairing.device_code}`,
        },
      }).then((response) => response.json());
      const failedSourcePairing = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Forwarded-For": "self-test-failed-receipt",
          },
          body: "{}",
        },
      ).then((response) => response.json());
      const failedSourceSubmitPage = await fetch(
        `http://127.0.0.1:${port}/source-pair`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded",
            "X-Forwarded-For": "self-test-failed-receipt",
          },
          body: new URLSearchParams({
            code: failedSourcePairing.user_code,
            repository_urls: "https://rejected.example/catalog.json",
          }),
        },
      ).then((response) => response.text());
      const failedSourceReceiptPath = failedSourceSubmitPage.match(
        /\/source-pair\/status\/[A-Za-z0-9_-]{20,80}/,
      )?.[0];
      const failedSourcePollUrl =
        `http://127.0.0.1:${port}/v1/source-pairings/${failedSourcePairing.pairing_id}`;
      await fetch(failedSourcePollUrl, {
        headers: {
          Authorization: `Pairing ${failedSourcePairing.device_code}`,
          "X-Forwarded-For": "self-test-failed-receipt",
        },
      });
      const failedSourceCompletion = await fetch(
        `${failedSourcePollUrl}/complete`,
        {
          method: "POST",
          headers: {
            Authorization: `Pairing ${failedSourcePairing.device_code}`,
            "Content-Type": "application/json",
            "X-Forwarded-For": "self-test-failed-receipt",
          },
          body: JSON.stringify({
            repositories_saved: 0,
            manifests_saved: 0,
            rejected_count: 1,
          }),
        },
      );
      const failedSourceReceiptPage = failedSourceReceiptPath
        ? await fetch(
            `http://127.0.0.1:${port}${failedSourceReceiptPath}`,
          ).then((response) => response.text())
        : "";
      const oversizedSourceForm = await fetch(
        `http://127.0.0.1:${port}/source-pair`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/x-www-form-urlencoded",
          },
          body: `code=ABCD-EFGH&repository_urls=${"a".repeat(131_073)}`,
        },
      );
      const expiringSourcePairing = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: "{}",
        },
      ).then((response) => response.json());
      sourcePairings.get(expiringSourcePairing.pairing_id).expiresAt = 0;
      const expiredSourcePoll = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings/${expiringSourcePairing.pairing_id}`,
        {
          headers: {
            Authorization: `Pairing ${expiringSourcePairing.device_code}`,
          },
        },
      );
      const cancellableSourcePairing = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: "{}",
        },
      ).then((response) => response.json());
      const cancelSourceResponse = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings/${cancellableSourcePairing.pairing_id}`,
        {
          method: "DELETE",
          headers: {
            Authorization: `Pairing ${cancellableSourcePairing.device_code}`,
          },
        },
      );
      const cancelledSourcePoll = await fetch(
        `http://127.0.0.1:${port}/v1/source-pairings/${cancellableSourcePairing.pairing_id}`,
        {
          headers: {
            Authorization: `Pairing ${cancellableSourcePairing.device_code}`,
          },
        },
      );
      const oauthExchangeRedirectPolicies =
        exchangeCode
          .toString()
          .match(/redirect:\s*["']error["']/g)?.length ?? 0;
      const oauthRefreshRedirectPolicies =
        refreshMyAnimeListToken
          .toString()
          .match(/redirect:\s*["']error["']/g)?.length ?? 0;
      if (
        health.status !== "ok" ||
        normalizePublicOrigin("https://example.com/path") !== "" ||
        normalizePublicOrigin("http://example.com") !== "" ||
        clientAddress(
          {
            headers: {
              "x-forwarded-for":
                `203.0.113.11, ${"9".repeat(3_000)}`,
            },
            socket: { remoteAddress: "127.0.0.1" },
          },
          "leftmost",
        ) !== "203.0.113.11" ||
        healthResponse.headers.get("strict-transport-security") !==
          "max-age=31536000" ||
        health.privacy_policy !== true ||
        health.privacy_policy_url !== "https://auth.example.com/privacy" ||
        privacyResponse.status !== 200 ||
        !privacyResponse.headers
          .get("content-type")
          ?.startsWith("text/html; charset=utf-8") ||
        privacyResponse.headers.get("cache-control") !== "no-store" ||
        privacyResponse.headers.get("strict-transport-security") !==
          "max-age=31536000" ||
        !privacyResponse.headers
          .get("content-security-policy")
          ?.includes("default-src 'none'") ||
        !privacyBody.includes("TetoTV privacy disclosure") ||
        !privacyBody.includes("at most ten minutes") ||
        !privacyBody.includes("Effective August 13, 2026") ||
        !privacyBody.includes("Android's system file picker") ||
        !privacyBody.includes("Jellyfin and Plex traffic do not pass through") ||
        !privacyBody.includes("X-Plex-Token") ||
        !privacyBody.includes("random app device ID") ||
        !privacyBody.includes("random client identifier") ||
        !privacyBody.includes("private filenames and library titles are not shared") ||
        !privacyBody.includes("Reset TetoTV") ||
        !privacyBody.includes("Clear cache") ||
        !privacyBody.includes("Discord Rich Presence") ||
        !privacyBody.includes("limited-input device authorization directly") ||
        !privacyBody.includes("broker is not involved in Discord linking") ||
        !privacyBody.includes("disabled by default") ||
        !privacyBody.includes("https://discord.gg/juC6k7d4WY") ||
        !privacyBody.includes("Anonymous live activity count") ||
        !privacyBody.includes("Anonymous crash reporting is disabled by default") ||
        !privacyBody.includes("unexpected handled app errors") ||
        !privacyBody.includes("designated crash-report channel") ||
        !privacyBody.includes("shared, revocable Beta-channel credential") ||
        !privacyBody.includes("legacy 1.11.x clients") ||
        !privacyBody.includes("SHA-256 hashes for access checks") ||
        privacyBody.includes(githubReleaseToken) ||
        privacyBody.includes(selfTestBetaAccessKey) ||
        JSON.stringify(health).includes(selfTestBetaAccessKey) ||
        JSON.stringify(health).includes(
          createHash("sha256").update(selfTestBetaAccessKey).digest("hex"),
        ) ||
        health.source_pairing !== true ||
        health.source_pairing_version !== 2 ||
        health.app_presence !== true ||
        health.crash_reporting !== true ||
        crashReportResponse.status !== 202 ||
        crashReportBody.status !== "accepted" ||
        selfTestCrashForwards.length !== 1 ||
        selfTestCrashForwards[0].body.includes("signed.example") ||
        selfTestCrashForwards[0].body.includes("never-forward-this-token") ||
        selfTestCrashForwards[0].body.includes("also-private") ||
        selfTestCrashForwards[0].body.includes("private-show") ||
        selfTestCrashForwards[0].body.includes("document/video") ||
        selfTestCrashForwards[0].body.includes("Private Show Episode 7.mkv") ||
        selfTestCrashForwards[0].body.includes("Private Episode 8.mkv") ||
        selfTestCrashForwards[0].body.includes("a".repeat(40)) ||
        !selfTestCrashForwards[0].body.includes("[URL]") ||
        !selfTestCrashForwards[0].body.includes("[URI]") ||
        !selfTestCrashForwards[0].body.includes("[PATH]") ||
        !selfTestCrashForwards[0].body.includes(
          "dev.animetv.anime_tv.player.Media3PlayerActivity.onDestroy" +
            "(Media3PlayerActivity.kt:169)",
        ) ||
        !selfTestCrashForwards[0].signature.startsWith("sha256=") ||
        presenceCreateResponse.status !== 201 ||
        !/^[A-Za-z0-9_-]{43}$/.test(presenceSession.session_token) ||
        presenceSession.heartbeat_interval !== 45 ||
        presenceBefore.active !== 1 ||
        presenceBefore.streaming !== 0 ||
        presenceHeartbeatResponse.status !== 204 ||
        presenceAfter.active !== 1 ||
        presenceAfter.streaming !== 1 ||
        invalidPresenceResponse.status !== 401 ||
        presenceCloseResponse.status !== 204 ||
        presenceClosed.active !== 0 ||
        presenceClosed.streaming !== 0 ||
        health.beta_updates_configured !== true ||
        Object.hasOwn(health, "app_updates") ||
        updateProxyConfigured({ token: "" }) !== false ||
        betaUpdatesConfigured({ hashes: [] }) !== false ||
        anonymousUpdateMetadataResponse.status !== 200 ||
        anonymousUpdateMetadataResponse.headers.get("cache-control") !==
          "no-store" ||
        legacyUpdateMetadata.version !== legacyPublicAliasVersion ||
        legacyUpdateMetadata.tag_name !== legacyPublicAliasTag ||
        legacyUpdateMetadata.asset?.name !==
          `TetoTV-${legacyPublicAliasTag}-universal.apk` ||
        legacyUpdateMetadata.asset?.download_url !==
          `https://auth.example.com/v1/app-updates/releases/${legacyPublicAliasTag}/assets/117001/universal.apk` ||
        legacyAdvertisedUrl.search ||
        legacyAdvertisedUrl.hash ||
        legacyUpdateHead.status !== 200 ||
        legacyUpdateHead.headers.get("content-length") !==
          String(selfTestApk.length) ||
        legacyUpdateDownload.status !== 200 ||
        legacyUpdateDownloadBody.length !== selfTestApk.length ||
        legacyUpdateRange.status !== 206 ||
        legacyUpdateRange.headers.get("content-range") !==
          `bytes 16-31/${selfTestApk.length}` ||
        legacyUpdateRangeBody.length !== 16 ||
        invalidUpdateMetadataResponse.status !== 401 ||
        betaAuthRateResponses.slice(0, 8).some(
          (response) => response.status !== 401,
        ) ||
        betaAuthRateResponses.at(-1)?.status !== 429 ||
        updateMetadataResponse.status !== 200 ||
        updateMetadataResponse.headers.get("cache-control") !== "no-store" ||
        updateMetadataResponse.headers.get("strict-transport-security") !==
          "max-age=31536000" ||
        updateMetadata.version !== "2.0.1" ||
        updateMetadata.tag_name !== "v2.0.1" ||
        updateMetadata.asset?.name !== "TetoTV-v2.0.1-universal.apk" ||
        updateMetadata.asset?.download_url !==
          "https://auth.example.com/v1/app-updates/releases/v2.0.1/assets/116001/universal.apk" ||
        updateHistoryResponse.status !== 200 ||
        !Array.isArray(updateHistory.releases) ||
        updateHistory.releases.length !== 2 ||
        updateHistory.releases[0]?.version !== "2.0.1" ||
        updateHistory.releases[1]?.version !== "2.0.0" ||
        updateHistory.releases.some(
          (release) => !/^2\.\d+\.\d+$/.test(String(release.version || "")),
        ) ||
        previousUpdateUrl.search ||
        previousUpdateUrl.hash ||
        previousUpdateDownload.status !== 200 ||
        previousUpdateDownloadBody.length !== selfTestApk.length ||
        advertisedUpdateUrl.search ||
        advertisedUpdateUrl.hash ||
        JSON.stringify(updateMetadata).includes(githubReleaseToken) ||
        JSON.stringify(updateMetadata).includes("api.github.com") ||
        updateHead.status !== 200 ||
        updateHead.headers.get("content-length") !== String(selfTestApk.length) ||
        updateHead.headers.get("accept-ranges") !== "bytes" ||
        updateHead.headers.get("etag") !==
          `"asset-116001-${selfTestApk.length}"` ||
        anonymousUpdateHead.status !== 401 ||
        anonymousUpdateHead.headers.has("content-length") ||
        anonymousUpdateDownload.status !== 401 ||
        updateDownload.status !== 200 ||
        updateDownload.headers.get("strict-transport-security") !==
          "max-age=31536000" ||
        updateDownload.headers.get("content-type") !==
          "application/vnd.android.package-archive" ||
        updateDownloadBody.length !== selfTestApk.length ||
        updateRange.status !== 206 ||
        updateRange.headers.get("content-range") !==
          `bytes 16-31/${selfTestApk.length}` ||
        updateRangeBody.length !== 16 ||
        invalidUpdateRange.status !== 416 ||
        mismatchedIfRange.status !== 200 ||
        mismatchedIfRange.headers.has("content-range") ||
        wrongAssetDownload.status !== 404 ||
        wrongAssetBody.includes(githubReleaseToken) ||
        wrongAssetBody.includes("api.github.com") ||
        !selfTestGithubRequests.some(
          (entry) =>
            entry.hostname === "api.github.com" &&
            entry.pathname.endsWith("/releases/latest") &&
            entry.authorization === `Bearer ${githubReleaseToken}`,
        ) ||
        !selfTestGithubRequests.some(
          (entry) =>
            entry.hostname === "api.github.com" &&
            entry.pathname ===
              `${repositoryApiPath(legacyPublicReleaseRepository)}/releases/latest` &&
            entry.authorization === null,
        ) ||
        !selfTestGithubRequests.some(
          (entry) =>
            entry.hostname === "api.github.com" &&
            entry.pathname.endsWith("/releases/assets/116001") &&
            entry.authorization === `Bearer ${githubReleaseToken}`,
        ) ||
        !selfTestGithubRequests.some(
          (entry) =>
            entry.hostname === "release-assets.githubusercontent.com" &&
            entry.authorization === null,
        ) ||
        health.callbacks.myanimelist !==
          "https://auth.example.com/oauth/myanimelist/callback" ||
        !/^[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(pairing.user_code) ||
        !/^[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(malPairing.user_code) ||
        oauthExchangeRedirectPolicies !== 2 ||
        oauthRefreshRedirectPolicies !== 1 ||
        oauthRateResponses
          .map((value) => value.status)
          .sort()
          .join(",") !== "201,201,201,201,201,429" ||
        oversizedForwardedRateResponses
          .map((value) => value.status)
          .join(",") !== "201,201,201,201,201,429" ||
        oauthRefreshRateResponses
          .slice(0, 10)
          .some((value) => value.status !== 400) ||
        oauthRefreshRateResponses.at(-1)?.status !== 429 ||
        oauthCapacityResponse.status !== 503 ||
        malAuthorize.status !== 302 ||
        malAuthorizeUrl.searchParams.has("redirect_uri") ||
        !malAuthorizeUrl.searchParams.get("code_challenge") ||
        !String(pairing.verification_uri || "").startsWith("https://") ||
        pending.status !== "pending" ||
        !manualPage.includes('name="code"') ||
        sourceWrongContentType.status !== 415 ||
        sourceUnexpectedBody.status !== 400 ||
        sourceMalformedBody.status !== 400 ||
        misplacedMarketplaceResponse.status !== 400 ||
        !misplacedMarketplacePage.includes(
          "A marketplace.json URL was entered under Torrent source manifests.",
        ) ||
        !misplacedMarketplacePage.includes(
          "Move it to Marketplace repositories.",
        ) ||
        !misplacedMarketplacePage.includes(misplacedMarketplaceUrl) ||
        validSubmittedUrl(misplacedMarketplaceUrl, { manifest: true }) ||
        sourcePairingValidationError([misplacedMarketplaceUrl], []) !== "" ||
        !/^[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(sourcePairing.user_code) ||
        !/^[A-Za-z0-9_-]{43}$/.test(sourcePairing.device_code) ||
        !sourcePage.includes('name="repository_urls"') ||
        !sourcePage.includes('name="manifest_urls"') ||
        sourcePage.includes(sourcePairing.pairing_id) ||
        sourcePage.includes(sourcePairing.device_code) ||
        sourcePageResponse.headers.get("cache-control") !== "no-store" ||
        sourcePageResponse.headers.get("strict-transport-security") !==
          "max-age=31536000" ||
        !String(sourcePageResponse.headers.get("content-security-policy")).includes(
          "default-src 'none'",
        ) ||
        parallelSubmissions.map((value) => value.status).sort().join(",") !==
          "200,409" ||
        !sourceSubmitPage.includes("Sent to TetoTV") ||
        !sourceSubmitPage.includes("Waiting for the app's saved confirmation") ||
        !sourcePostSubmitExpiresAt ||
        sourcePostSubmitExpiresAt < Date.now() + ttlMs - 5_000 ||
        sourceSubmitPage.includes(sourcePairing.device_code) ||
        sourceWaitingPage.includes("https://example.com") ||
        sourceWaitingPage.includes(sourcePairing.device_code) ||
        sourceUnauthorized.status !== 401 ||
        sourceResult.status !== "submitted" ||
        sourceResult.repository_urls.length !== 1 ||
        sourceResult.manifest_urls[0] !==
          "https://example.com/addon/manifest.json" ||
        sourceRedelivery.status !== "submitted" ||
        sourceRedelivery.repository_urls[0] !==
          sourceResult.repository_urls[0] ||
        invalidSourceCompletion.status !== 400 ||
        sourceRetryAfterBadAck.status !== "submitted" ||
        sourceCompletion.status !== 204 ||
        sourceCompletionReplay.status !== 204 ||
        sourceCompletedPoll.status !== "completed" ||
        Object.hasOwn(sourceCompletedPoll, "repository_urls") ||
        Object.hasOwn(sourceCompletedPoll, "manifest_urls") ||
        !sourceCompletedPage.includes("Saved in TetoTV") ||
        !sourceCompletedPage.includes("1 marketplace repository") ||
        !sourceCompletedPage.includes("1 torrent manifest") ||
        sourceCompletedPage.includes("https://example.com") ||
        sourceCompletedPage.includes(sourcePairing.device_code) ||
        !failedSourceReceiptPath ||
        failedSourceCompletion.status !== 204 ||
        !failedSourceReceiptPage.includes(
          "TetoTV could not save these sources",
        ) ||
        failedSourceReceiptPage.includes("rejected.example") ||
        failedSourceReceiptPage.includes(failedSourcePairing.device_code) ||
        oversizedSourceForm.status !== 413 ||
        expiredSourcePoll.status !== 404 ||
        cancelSourceResponse.status !== 204 ||
        cancelledSourcePoll.status !== 404
      ) {
        throw new Error("Broker self-test response validation failed.");
      }
      console.log("Broker self-test passed.");
      server.close();
    } catch (error) {
      console.error("Broker self-test failed:", error.message);
      server.close(() => {
        process.exitCode = 1;
      });
    }
  }
});
