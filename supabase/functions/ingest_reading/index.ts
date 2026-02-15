// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ingestSecret = Deno.env.get("INGEST_SECRET") ?? "";

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-ingest-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, any>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(500, { error: "Missing Supabase env vars" });
  }

  if (ingestSecret.length > 0) {
    const provided = req.headers.get("x-ingest-secret");
    if (provided != ingestSecret) {
      return jsonResponse(401, { error: "Unauthorized" });
    }
  }

  let payload: Record<string, any>;
  try {
    payload = await req.json();
  } catch (_) {
    return jsonResponse(400, { error: "Invalid JSON" });
  }

  finalPlantId(payload);

  const moisture = Number(payload.moisture);
  const lux = Number(payload.lux);
  const temperature = payload.temperature == null
    ? null
    : Number(payload.temperature);
  const createdAt = payload.created_at ? String(payload.created_at) : null;
  const plantId = payload.plant_id ? String(payload.plant_id) : null;

  if (Number.isNaN(moisture) || Number.isNaN(lux)) {
    return jsonResponse(400, { error: "moisture and lux must be numbers" });
  }
  if (temperature != null && Number.isNaN(temperature)) {
    return jsonResponse(400, { error: "temperature must be a number" });
  }

  if (!plantId || plantId.length == 0) {
    return jsonResponse(400, { error: "plant_id is required" });
  }

  const insertPayload: Record<string, any> = {
    moisture,
    lux,
  };
  if (temperature != null) insertPayload.temperature = temperature;
  if (createdAt) insertPayload.created_at = createdAt;
  insertPayload.plant_id = plantId;

  const { data, error } = await supabase
    .from("readings")
    .insert(insertPayload)
    .select("id, created_at");

  if (error) {
    return jsonResponse(500, { error: error.message });
  }

  return jsonResponse(200, { ok: true, data });
});

function finalPlantId(payload: Record<string, any>) {
  if (payload.plant_id == null) {
    return;
  }
  const value = String(payload.plant_id).trim();
  if (value.length == 0) {
    delete payload.plant_id;
  }
}
