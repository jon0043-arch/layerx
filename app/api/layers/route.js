import { timingSafeEqual } from "node:crypto";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
const json = (body, status = 200) => Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
const configured = () => Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
const safeEquals = (a, b) => {
  const left = Buffer.from(a || "");
  const right = Buffer.from(b || "");
  return left.length === right.length && timingSafeEqual(left, right);
};
const coordinates = (lat, lon) => Number.isFinite(lat) && Number.isFinite(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
const headers = () => ({
  "apikey": process.env.SUPABASE_SERVICE_ROLE_KEY,
  "Authorization": "Bearer " + process.env.SUPABASE_SERVICE_ROLE_KEY,
  "Content-Type": "application/json"
});
const endpoint = () => process.env.SUPABASE_URL.replace(/\/+$/, "") + "/rest/v1/layers";
const distance = (a, b) => {
  const d = Math.PI / 180;
  const x = Math.sin((b.latitude - a.latitude) * d / 2) ** 2 + Math.cos(a.latitude * d) * Math.cos(b.latitude * d) * Math.sin((b.longitude - a.longitude) * d / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
};

export async function GET(request) {
  if (!configured()) return json({ mode: "local", layers: [] });
  const url = new URL(request.url);
  const latitude = Number(url.searchParams.get("lat"));
  const longitude = Number(url.searchParams.get("lon"));
  if (!coordinates(latitude, longitude) || !url.searchParams.has("lat") || !url.searchParams.has("lon")) {
    return json({ error: "Valid lat/lon required." }, 400);
  }
  const radius = 1500;
  const latDelta = radius / 111320;
  const lonDelta = Math.min(180, radius / (111320 * Math.max(0.02, Math.cos(latitude * Math.PI / 180))));
  const params = new URLSearchParams({
    select: "id,title,message,creator,latitude,longitude,created_at",
    status: "eq.public",
    latitude: "gte." + (latitude - latDelta),
    longitude: "gte." + (longitude - lonDelta),
    order: "created_at.desc",
    limit: "200"
  });
  params.append("latitude", "lte." + (latitude + latDelta));
  params.append("longitude", "lte." + (longitude + lonDelta));
  try {
    // PostgREST ANDs repeated query params in most setups; use an explicit and filter instead.
    params.delete("latitude"); params.delete("longitude");
    params.set("and", "(latitude.gte."+(latitude-latDelta)+",latitude.lte."+(latitude+latDelta)+",longitude.gte."+(longitude-lonDelta)+",longitude.lte."+(longitude+lonDelta)+")");
    const response = await fetch(endpoint() + "?" + params, { headers: headers(), cache: "no-store" });
    if (!response.ok) throw new Error("Storage returned " + response.status);
    const rows = await response.json();
    return json({ mode: "live", layers: rows.filter(l => distance({ latitude, longitude }, l) <= radius) });
  } catch (error) {
    console.error("Layer X list failed", error);
    return json({ error: "Shared layer service temporarily unavailable", mode: "local", layers: [] }, 503);
  }
}

export async function POST(request) {
  if (!configured() || !process.env.LAYERX_CREATE_ACCESS_CODE) return json({ error: "Shared publishing is not configured." }, 503);
  if (!safeEquals(request.headers.get("x-layerx-create-code"), process.env.LAYERX_CREATE_ACCESS_CODE)) {
    return json({ error: "Invalid field test publishing code." }, 401);
  }
  let body;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON." }, 400); }
  const { latitude, longitude } = body || {};
  const title = typeof body?.title === "string" ? body.title.trim() : "";
  const message = typeof body?.message === "string" ? body.message.trim() : "";
  const creator = typeof body?.creator === "string" ? body.creator.trim() : "ANONYMOUS";
  if (!coordinates(latitude, longitude) || title.length < 2 || title.length > 60 || message.length < 2 || message.length > 280 || creator.length > 32) {
    return json({ error: "Invalid coordinates or content length." }, 400);
  }
  const row = { title, message, creator: creator || "ANONYMOUS", latitude, longitude, status: "public" };
  try {
    const response = await fetch(endpoint(), {
      method: "POST", headers: { ...headers(), Prefer: "return=representation" },
      body: JSON.stringify(row), cache: "no-store"
    });
    if (!response.ok) throw new Error("Storage returned " + response.status);
    const rows = await response.json();
    return json({ layer: rows[0], mode: "live" }, 201);
  } catch (error) {
    console.error("Layer X creation failed", error);
    return json({ error: "Could not publish to shared storage." }, 503);
  }
}
