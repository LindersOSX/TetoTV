import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { createServer } from "node:http";

const port = Number(process.env.PORT || 8787);
const selfTest = process.argv.includes("--self-test");
const publicBaseUrl = String(
  process.env.PUBLIC_BASE_URL ||
    process.env.RENDER_EXTERNAL_URL ||
    (selfTest ? "https://auth.example.com" : ""),
).replace(/\/+$/, "");
const ttlMs = 10 * 60 * 1000;
const pairings = new Map();
const codes = new Map();
const rateLimits = new Map();

function providerConfig(provider) {
  if (provider === "anilist") {
    return {
      name: "AniList",
      clientId: process.env.ANILIST_CLIENT_ID || "",
      clientSecret: process.env.ANILIST_CLIENT_SECRET || "",
      authorizeUrl: "https://anilist.co/api/v2/oauth/authorize",
      tokenUrl: "https://anilist.co/api/v2/oauth/token",
    };
  }
  if (provider === "myanimelist") {
    return {
      name: "MyAnimeList",
      clientId: process.env.MAL_CLIENT_ID || "",
      clientSecret: process.env.MAL_CLIENT_SECRET || "",
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

function html(response, status, body) {
  response.writeHead(status, {
    "Content-Type": "text/html; charset=utf-8",
    "Cache-Control": "no-store",
    "Content-Security-Policy":
      "default-src 'none'; style-src 'unsafe-inline'; form-action 'self' https://anilist.co https://myanimelist.net; base-uri 'none'; frame-ancestors 'none'",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
  });
  response.end(`<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>TetoTV pairing</title>
<style>
body{margin:0;background:#080c16;color:#f5f5fb;font:18px system-ui;display:grid;min-height:100vh;place-items:center}
main{width:min(580px,calc(100% - 40px));background:#131928;border:1px solid #293149;border-radius:24px;padding:32px;box-sizing:border-box}
h1{margin:0 0 12px;font-size:32px}p{color:#b8bfd4;line-height:1.55}
a,button{display:block;width:100%;box-sizing:border-box;border:0;margin-top:24px;padding:16px 20px;border-radius:12px;background:#f5f5fb;color:#111624;text-align:center;text-decoration:none;font:inherit;font-weight:800;cursor:pointer}
input{display:block;width:100%;box-sizing:border-box;margin-top:22px;padding:16px 18px;border:1px solid #39435f;border-radius:12px;background:#090e1a;color:#f5f5fb;font:700 22px system-ui;letter-spacing:3px;text-transform:uppercase}
code{color:#5bd8ec}small{display:block;margin-top:18px;color:#7f879e}
</style><main>${body}</main></html>`);
}

const normalizeCode = (value) =>
  String(value || "").trim().toUpperCase();

function rateLimited(request) {
  const key = String(
    request.headers["x-forwarded-for"] || request.socket.remoteAddress || "",
  )
    .split(",")[0]
    .trim();
  const now = Date.now();
  const current = rateLimits.get(key);
  if (!current || now - current.startedAt >= 60_000) {
    rateLimits.set(key, { startedAt: now, count: 1 });
    return false;
  }
  current.count += 1;
  return current.count > 60;
}

function cleanup() {
  const now = Date.now();
  for (const [id, pairing] of pairings) {
    if (pairing.expiresAt <= now) {
      pairings.delete(id);
      codes.delete(pairing.userCode);
    }
  }
}

async function drainBody(request) {
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 16_384) throw new Error("Request body is too large.");
  }
}

async function readJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 16_384) throw new Error("Request body is too large.");
    chunks.push(chunk);
  }
  const value = Buffer.concat(chunks).toString("utf8");
  return value ? JSON.parse(value) : {};
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
       <form method="get" action="/pair">
         <input name="code" aria-label="TV pairing code" placeholder="ABCD-EFGH" maxlength="9" required>
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
  authorize.searchParams.set("redirect_uri", callbackUrl(pairing.provider));
  authorize.searchParams.set("response_type", "code");
  authorize.searchParams.set("state", pairing.state);
  if (pairing.provider === "myanimelist") {
    authorize.searchParams.set("code_challenge", pairing.codeVerifier);
    authorize.searchParams.set("code_challenge_method", "plain");
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
    redirect_uri: callbackUrl(pairing.provider),
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

const server = createServer(async (request, response) => {
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
      });
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
    console.error("Broker request failed:", error.message);
    return json(response, 500, { error: "internal_error" });
  }
});

server.listen(port, async () => {
  console.log(`TetoTV auth broker listening on port ${port}`);
  if (selfTest) {
    try {
      const health = await fetch(`http://127.0.0.1:${port}/health`).then(
        (response) => response.json(),
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
      if (
        health.status !== "ok" ||
        health.callbacks.myanimelist !==
          "https://auth.example.com/oauth/myanimelist/callback" ||
        !/^[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(pairing.user_code) ||
        !/^[A-Z2-9]{4}-[A-Z2-9]{4}$/.test(malPairing.user_code) ||
        !String(pairing.verification_uri || "").startsWith("https://") ||
        pending.status !== "pending" ||
        !manualPage.includes('name="code"')
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
