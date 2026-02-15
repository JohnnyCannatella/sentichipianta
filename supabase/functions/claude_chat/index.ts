// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const anthropicApiKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const chatSecret = Deno.env.get("CHAT_SECRET") ?? "";
const anthropicModel = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-4-5";

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-chat-secret",
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

  if (!supabaseUrl || !serviceRoleKey || !anthropicApiKey) {
    return jsonResponse(500, { error: "Missing env vars" });
  }

  if (chatSecret.length > 0) {
    const provided = req.headers.get("x-chat-secret");
    if (provided != chatSecret) {
      return jsonResponse(401, { error: "Unauthorized" });
    }
  }

  let payload: Record<string, any>;
  try {
    payload = await req.json();
  } catch (_) {
    return jsonResponse(400, { error: "Invalid JSON" });
  }

  const message = String(payload.message ?? "").trim();
  if (message.length == 0) {
    return jsonResponse(400, { error: "Missing message" });
  }

  const plantName = String(payload.plant?.name ?? "Senti Chi Pianta");
  const personality = String(
    payload.plant?.personality ??
      "Gentile, poetica, ironica quanto basta. Parla in prima persona.",
  );

  const reading = payload.reading ?? null;
  const tempSegment =
    reading && reading.temperature != null
      ? `, temperatura ${reading.temperature}°C`
      : "";
  const readingLine = reading
    ? `Dati sensori: umidita ${reading.moisture}%, luce ${reading.lux} lx${tempSegment}.`
    : "";

  const systemPrompt =
    `Sei la pianta '${plantName}'. ${personality} ` +
    "Rispondi in italiano, breve ma espressivo, mantenendo SEMPRE questa personalita e questo tono. " +
    "Se i dati indicano urgenza, fallo notare con gentilezza. " +
    readingLine;

  const anthropicResponse = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": anthropicApiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: anthropicModel,
      max_tokens: 300,
      system: systemPrompt,
      messages: [{ role: "user", content: message }],
    }),
  });

  if (!anthropicResponse.ok) {
    const text = await anthropicResponse.text();
    return jsonResponse(502, { error: "Anthropic error", detail: text });
  }

  const data = await anthropicResponse.json();
  const reply =
    (data?.content ?? [])
      .map((item: any) => item?.text)
      .filter((text: string | undefined) => !!text)
      .join("\n")
      .trim() || "Non riesco a rispondere in questo momento.";

  const plantId = payload.plant_id ?? null;
  if (plantId != null) {
    const { error: insertError } = await supabase.from("messages").insert([
      {
        plant_id: plantId,
        role: "user",
        content: message,
      },
      {
        plant_id: plantId,
        role: "assistant",
        content: reply,
      },
    ]);

    if (insertError) {
      return jsonResponse(500, {
        error: "Failed to persist chat messages",
        detail: insertError.message,
        reply,
      });
    }
  }

  return jsonResponse(200, { reply });
});
