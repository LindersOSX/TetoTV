import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { createServer } from "node:http";
import { Readable, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";

const port = Number(process.env.PORT || 8787);
const selfTest = process.argv.includes("--self-test");
const publicBaseUrl = String(
  process.env.PUBLIC_BASE_URL ||
    process.env.RENDER_EXTERNAL_URL ||
    (selfTest ? "https://auth.example.com" : ""),
).replace(/\/+$/, "");
const ttlMs = 10 * 60 * 1000;
const rateWindowMs = 60 * 1000;
const maxRateLimitEntries = 4096;
const githubReleaseRepository =
  process.env.GITHUB_RELEASE_REPOSITORY || "LindersOSX/TetoTV";
const githubReleaseToken =
  process.env.GITHUB_RELEASE_TOKEN ||
  (selfTest ? "self-test-github-release-token" : "");
const githubReleaseApiVersion = "2022-11-28";
const releaseMetadataTtlMs = 60 * 1000;
const versionedReleaseTtlMs = 24 * 60 * 60 * 1000;
const maxReleaseAssetBytes = 300 * 1024 * 1024;
const maxReleaseNotesLength = 32_000;
// This deployment is intentionally small/private. Move APK delivery to
// object storage/CDN before raising these process-wide safeguards.
const maxConcurrentUpdateDownloads = 4;
const maxUpdateDownloadsPerMinute = 12;
const pairings = new Map();
const codes = new Map();
const sourcePairings = new Map();
const sourceCodes = new Map();
const sourceReceipts = new Map();
const rateLimits = new Map();
let nextRateLimitCleanupAt = 0;
let cachedLatestRelease = null;
let latestReleaseRequest = null;
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

function html(response, status, body, { refreshUrl = "" } = {}) {
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
<title>TetoTV pairing</title>
<style>
body{margin:0;background:#080c16;color:#f5f5fb;font:18px system-ui;display:grid;min-height:100vh;place-items:center}
main{width:min(580px,calc(100% - 40px));background:#131928;border:1px solid #293149;border-radius:24px;padding:32px;box-sizing:border-box}
h1{margin:0 0 12px;font-size:32px}p{color:#b8bfd4;line-height:1.55}
a,button{display:block;width:100%;box-sizing:border-box;border:0;margin-top:24px;padding:16px 20px;border-radius:12px;background:#f5f5fb;color:#111624;text-align:center;text-decoration:none;font:inherit;font-weight:800;cursor:pointer}
input,textarea{display:block;width:100%;box-sizing:border-box;margin-top:22px;padding:16px 18px;border:1px solid #39435f;border-radius:12px;background:#090e1a;color:#f5f5fb;font:700 18px system-ui}
textarea{min-height:150px;resize:vertical;overflow-wrap:anywhere}.code-input{font-size:22px;letter-spacing:3px;text-transform:uppercase}
code{color:#5bd8ec}small{display:block;margin-top:18px;color:#7f879e}
.success{color:#67d49b}.warning{color:#ffd166}.error{color:#ff8798;font-weight:800}.count{font-size:22px;font-weight:800;color:#f5f5fb}
</style><main>${body}</main></html>`);
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

function rateLimited(request, limit = 600, namespace = "global") {
  // Render appends the connection address to X-Forwarded-For. Use the
  // rightmost bounded value so a client-supplied first entry cannot create an
  // unlimited stream of rate-limit buckets.
  const forwarded = String(request.headers["x-forwarded-for"] || "").slice(
    0,
    2048,
  );
  const address = String(
    forwarded
      ? forwarded.split(",").at(-1)
      : request.socket.remoteAddress || "",
  )
    .trim()
    .slice(0, 256);
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

function sourcePairingForm(response, pairing, errorMessage = "") {
  const error = errorMessage
    ? `<p class="error" role="alert">${escapeHtml(errorMessage)}</p>`
    : "";
  return html(
    response,
    errorMessage ? 400 : 200,
    `<h1>Send sources to TetoTV</h1>
     <p>Enter URLs for the TV showing code <code>${escapeHtml(pairing.userCode)}</code>. Use one URL per line, up to eight of each.</p>
     ${error}
     <form method="post" action="/source-pair" autocomplete="off">
       <input type="hidden" name="code" value="${escapeHtml(pairing.userCode)}">
       <textarea name="repository_urls" aria-label="Marketplace repository URLs" placeholder="Marketplace repositories&#10;https://example.com/marketplace.json" maxlength="16391"></textarea>
       <textarea name="manifest_urls" aria-label="Stremio manifest URLs" placeholder="Stremio manifests&#10;https://example.com/addon/manifest.json" maxlength="16391"></textarea>
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
  if (
    repositoryUrls.length > 8 ||
    manifestUrls.length > 8 ||
    repositoryUrls.length + manifestUrls.length === 0 ||
    repositoryUrls.some((value) => !validSubmittedUrl(value)) ||
    manifestUrls.some(
      (value) => !validSubmittedUrl(value, { manifest: true }),
    )
  ) {
    return sourcePairingForm(
      response,
      pairing,
      "Enter up to eight valid public HTTPS URLs per section. Manifest paths must end in /manifest.json, and embedded username/password credentials are not allowed.",
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
    });
    const body = await result.json();
    if (!result.ok || !body.access_token) {
      const detail =
        body.error_description || body.message || body.error || "unknown error";
      throw new Error(
        `AniList token exchange failed (${result.status}: ${String(detail).slice(0, 160)}).`,
      );
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
  });
  const body = await result.json();
  if (!result.ok || !body.access_token) {
    const detail =
      body.error_description || body.message || body.error || "unknown error";
    throw new Error(
      `MyAnimeList token exchange failed (${result.status}: ${String(detail).slice(0, 160)}).`,
    );
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
  const body = await readJson(request);
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
    console.error(`${provider} OAuth callback failed:`, error.message);
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

function githubRepositoryApiPath() {
  if (!repositoryPattern.test(githubReleaseRepository)) {
    throw new UpdateProxyError(503, "updates_not_configured");
  }
  const [owner, repository] = githubReleaseRepository.split("/");
  return `/repos/${encodeURIComponent(owner)}/${encodeURIComponent(repository)}`;
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
  if (
    parsed.origin === "https://api.github.com" &&
    parsed.pathname === `${repositoryPath}/releases/latest`
  ) {
    return new Response(
      JSON.stringify({
        id: 116,
        tag_name: "v1.11.6",
        name: "TetoTV v1.11.6",
        body: "Private release notes",
        draft: false,
        prerelease: false,
        published_at: "2026-08-10T00:00:00Z",
        assets: [
          {
            id: 116001,
            name: "TetoTV-v1.11.6-universal.apk",
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
    parsed.pathname === `${repositoryPath}/releases/assets/116001`
  ) {
    return new Response(null, {
      status: 302,
      headers: {
        Location: "https://release-assets.githubusercontent.com/tetotv/latest.apk?signature=hidden",
      },
    });
  }
  if (
    parsed.origin === "https://release-assets.githubusercontent.com" &&
    parsed.pathname === "/tetotv/latest.apk"
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

async function requestGithubRelease(path) {
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
  return sanitizeLatestRelease(body);
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

async function fetchReleaseByTag(tagName) {
  if (!releaseTagPattern.test(tagName)) {
    throw new UpdateProxyError(404, "update_not_found");
  }
  const now = Date.now();
  const cached = cachedVersionedReleases.get(tagName);
  if (cached?.expiresAt > now) return cached.release;
  if (cached) cachedVersionedReleases.delete(tagName);
  const latest = await fetchLatestRelease();
  if (latest.tagName !== tagName) {
    throw new UpdateProxyError(404, "update_not_found");
  }
  cacheVersionedRelease(latest);
  return latest;
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

async function latestReleaseMetadata(response) {
  const release = await fetchLatestRelease();
  return json(response, 200, publicReleaseMetadata(release));
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
    hostname === "release-assets.githubusercontent.com" ||
    hostname.endsWith(".githubusercontent.com")
  );
}

async function fetchGithubAsset(release, range, signal) {
  let currentUrl = new URL(
    `https://api.github.com${githubRepositoryApiPath()}/releases/assets/${release.asset.id}`,
  );
  let firstRequest = true;
  for (let redirectCount = 0; redirectCount <= 3; redirectCount += 1) {
    let result;
    try {
      result = await githubFetch(currentUrl, {
        headers: {
          ...githubHeaders({
            accept: "application/octet-stream",
            token: firstRequest,
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

async function downloadRelease(request, response, tagName, assetId) {
  const release = await fetchReleaseByTag(tagName);
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
        app_updates: updateProxyConfigured(),
      });
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
      return await latestReleaseMetadata(response);
    }
    const updateDownloadMatch = url.pathname.match(
      /^\/v1\/app-updates\/releases\/(v\d+\.\d+\.\d+)\/assets\/([1-9]\d*)\/universal\.apk$/,
    );
    if (
      (request.method === "GET" || request.method === "HEAD") &&
      updateDownloadMatch
    ) {
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
      return await createPairing(request, response, createMatch[1]);
    }
    const pollMatch = url.pathname.match(
      /^\/v1\/(anilist|myanimelist)\/pairings\/([A-Za-z0-9_-]+)$/,
    );
    if (request.method === "GET" && pollMatch) {
      return pollPairing(request, response, pollMatch[1], pollMatch[2]);
    }
    if (
      request.method === "POST" &&
      url.pathname === "/v1/myanimelist/token/refresh"
    ) {
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
    console.error("Broker request failed:", error.message);
    return json(response, 500, { error: "internal_error" });
  }
  },
);

server.listen(port, async () => {
  console.log(`TetoTV auth broker listening on port ${port}`);
  if (selfTest) {
    try {
      const health = await fetch(`http://127.0.0.1:${port}/health`).then(
        (response) => response.json(),
      );
      const updateMetadataResponse = await fetch(
        `http://127.0.0.1:${port}/v1/app-updates/latest`,
      );
      const updateMetadata = await updateMetadataResponse.json();
      const advertisedUpdateUrl = new URL(updateMetadata.asset.download_url);
      const localUpdateUrl =
        `http://127.0.0.1:${port}${advertisedUpdateUrl.pathname}`;
      // Force the first binary request through the immutable tag lookup rather
      // than relying on metadata's in-memory release object.
      cachedVersionedReleases.clear();
      const updateHead = await fetch(
        localUpdateUrl,
        { method: "HEAD" },
      );
      const updateDownload = await fetch(localUpdateUrl);
      const updateDownloadBody = Buffer.from(
        await updateDownload.arrayBuffer(),
      );
      const updateRange = await fetch(localUpdateUrl, {
        headers: { Range: "bytes=16-31" },
      });
      const updateRangeBody = Buffer.from(await updateRange.arrayBuffer());
      const invalidUpdateRange = await fetch(localUpdateUrl, {
        headers: { Range: "bytes=999999-1000000" },
      });
      const mismatchedIfRange = await fetch(localUpdateUrl, {
        method: "HEAD",
        headers: { Range: "bytes=16-31", "If-Range": '"old-asset"' },
      });
      const wrongAssetDownload = await fetch(
        localUpdateUrl.replace("/assets/116001/", "/assets/116002/"),
      );
      const wrongAssetBody = await wrongAssetDownload.text();
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
      if (
        health.status !== "ok" ||
        health.source_pairing !== true ||
        health.source_pairing_version !== 2 ||
        health.app_updates !== true ||
        updateProxyConfigured({ token: "" }) !== false ||
        updateMetadataResponse.status !== 200 ||
        updateMetadataResponse.headers.get("cache-control") !== "no-store" ||
        updateMetadata.version !== "1.11.6" ||
        updateMetadata.tag_name !== "v1.11.6" ||
        updateMetadata.asset?.name !== "TetoTV-v1.11.6-universal.apk" ||
        updateMetadata.asset?.download_url !==
          "https://auth.example.com/v1/app-updates/releases/v1.11.6/assets/116001/universal.apk" ||
        advertisedUpdateUrl.search ||
        advertisedUpdateUrl.hash ||
        JSON.stringify(updateMetadata).includes(githubReleaseToken) ||
        JSON.stringify(updateMetadata).includes("api.github.com") ||
        updateHead.status !== 200 ||
        updateHead.headers.get("content-length") !== String(selfTestApk.length) ||
        updateHead.headers.get("accept-ranges") !== "bytes" ||
        updateHead.headers.get("etag") !==
          `"asset-116001-${selfTestApk.length}"` ||
        updateDownload.status !== 200 ||
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
        malAuthorize.status !== 302 ||
        malAuthorizeUrl.searchParams.has("redirect_uri") ||
        !malAuthorizeUrl.searchParams.get("code_challenge") ||
        !String(pairing.verification_uri || "").startsWith("https://") ||
        pending.status !== "pending" ||
        !manualPage.includes('name="code"') ||
        sourceWrongContentType.status !== 415 ||
        sourceUnexpectedBody.status !== 400 ||
        sourceMalformedBody.status !== 400 ||
        !/^[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(sourcePairing.user_code) ||
        !/^[A-Za-z0-9_-]{43}$/.test(sourcePairing.device_code) ||
        !sourcePage.includes('name="repository_urls"') ||
        !sourcePage.includes('name="manifest_urls"') ||
        sourcePage.includes(sourcePairing.pairing_id) ||
        sourcePage.includes(sourcePairing.device_code) ||
        sourcePageResponse.headers.get("cache-control") !== "no-store" ||
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
