// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

type DenoEnvAccessor = { get: (key: string) => string | undefined };
type DenoGlobal = { env: DenoEnvAccessor };

function readEnv(key: string): string {
  const maybeDeno = (globalThis as { Deno?: DenoGlobal }).Deno;
  return maybeDeno?.env.get(key) ?? "";
}

const supabaseUrl = readEnv("SUPABASE_URL");
const serviceRoleKey = readEnv("SUPABASE_SERVICE_ROLE_KEY");
const fireworksApiKey = readEnv("FIREWORKS_API_KEY");
const chatSecret = readEnv("CHAT_SECRET");
const fireworksModel = readEnv("FIREWORKS_MODEL") ||
  "accounts/fireworks/models/qwen2p5-vl-3b-instruct";
const fallbackModel = readEnv("FIREWORKS_FALLBACK_MODEL") ||
  "accounts/fireworks/models/llama-v3p1-8b-instruct";

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-chat-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const maxImages = 4;
const maxDataUrlChars = 2_400_000;

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
  try {
    if (!supabaseUrl || !serviceRoleKey || !fireworksApiKey) {
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

    const userMessage = String(payload.message ?? "").trim();
    if (userMessage.length == 0) {
      return jsonResponse(400, { error: "Missing message" });
    }

    const plantName = String(payload.plant?.name ?? "Senti Chi Pianta");
    const personality = String(
      payload.plant?.personality ??
        "Gentile, poetica, ironica quanto basta. Parla in prima persona.",
    );
    const plantType = String(payload.plant?.plant_type ?? "generic");
    const thresholds = payload.plant?.thresholds ?? {};
    const reading = payload.reading ?? null;
    const readingHistory = Array.isArray(payload.reading_history)
      ? payload.reading_history
      : [];
    const prediction = payload.prediction ?? null;
    const imageUrls = Array.isArray(payload.images)
      ? payload.images.filter((v: unknown) => typeof v === "string")
      : [];

    const imageValidationError = validateImageInputs(imageUrls);
    if (imageValidationError) {
      return jsonResponse(400, { error: imageValidationError });
    }

    const telemetryContext = buildTelemetryContext(
      reading,
      readingHistory,
      prediction,
    );
    const messages = buildMessages(userMessage, imageUrls);
    const guardrails = buildGuardrailContext(reading, thresholds, prediction);
    const plantTypeContext = buildPlantTypeContext(plantType);

    const systemPrompt =
      `Sei l'assistente agronomico della pianta '${plantName}' (tipo: ${plantType}). ` +
      `Contesto utente: ${personality}. ` +
      "Scrivi in italiano tecnico e diretto, senza poesia, senza metafore, senza roleplay. " +
      "Rispondi SOLO in JSON valido con schema: " +
      "{\"decision\":{\"water\":\"water_now|wait|check_soon\",\"light\":\"increase|reduce|ok\",\"urgency\":\"high|medium|low\",\"confidence\":0.0,\"recheck_hours\":12}," +
      "\"motivation\":{\"summary\":\"...\",\"sensor_consistency\":\"...\"}," +
      "\"actions\":[{\"title\":\"...\",\"details\":\"...\",\"when\":\"today|within_24h|monitor\"}]," +
      "\"questions\":[\"...\"],\"needs_photo\":true|false}. " +
      "Massimo 3 actions e massimo 2 questions. " +
      "Non contraddire i sensori: se umidita >= target evita water_now; se umidita <= low evita wait.\n\n" +
      telemetryContext +
      "\n\n" + guardrails +
      "\n\n" + plantTypeContext;

    const modelAttempt = await runFireworks({
      apiKey: fireworksApiKey,
      model: fireworksModel,
      systemPrompt,
      messages,
    });

    let data = modelAttempt.data;
    let resolvedModel = fireworksModel;
    if (!modelAttempt.ok && shouldFallback(modelAttempt.errorText)) {
      const fallbackAttempt = await runFireworks({
        apiKey: fireworksApiKey,
        model: fallbackModel,
        systemPrompt,
        messages,
      });
      if (!fallbackAttempt.ok) {
        return jsonResponse(502, {
          error: "Fireworks error",
          model: fallbackModel,
          detail: fallbackAttempt.errorText,
        });
      }
      resolvedModel = fallbackModel;
      data = fallbackAttempt.data;
    } else if (!modelAttempt.ok) {
      return jsonResponse(502, {
        error: "Fireworks error",
        model: fireworksModel,
        detail: modelAttempt.errorText,
      });
    }

    const rawReply = String(data?.choices?.[0]?.message?.content ?? "").trim();
    const parsed = parseAssistantJson(rawReply);
    const safeReply = buildSafeReply({
      parsed,
      rawReply,
      reading,
      thresholds,
      prediction,
    });
    const aiMeta = extractAiMeta(parsed, prediction, safeReply);
    const followUpDueAt = aiMeta.followUpDueAt?.toISOString() ?? null;

    const plantId = payload.plant_id ?? null;
    if (plantId != null) {
      const { error: insertError } = await supabase.from("messages").insert([
        {
          plant_id: plantId,
          role: "user",
          content: userMessage,
        },
        {
          plant_id: plantId,
          role: "assistant",
          content: safeReply,
        },
      ]);

      if (insertError) {
        return jsonResponse(500, {
          error: "Failed to persist chat messages",
          detail: insertError.message,
          reply: safeReply,
        });
      }

      await supabase.from("ai_decisions").insert({
        plant_id: plantId,
        source: "fireworks",
        model: resolvedModel,
        sensor_snapshot: {
          latest: reading,
          history_points: readingHistory.length,
          prediction,
        },
        recommendation: {
          reply: safeReply,
          raw: rawReply,
        },
        confidence: aiMeta.confidence,
        needs_follow_up: aiMeta.needsFollowUp,
        follow_up_due_at: followUpDueAt,
      });
    }

    return jsonResponse(200, {
      reply: safeReply,
      needs_photo: aiMeta.needsPhoto,
      confidence: aiMeta.confidence,
      needs_follow_up: aiMeta.needsFollowUp,
      follow_up_due_at: followUpDueAt,
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    return jsonResponse(500, {
      error: "Unhandled runtime error",
      detail,
    });
  }
});

async function runFireworks(args: {
  apiKey: string;
  model: string;
  systemPrompt: string;
  messages: any[];
}) {
  const response = await fetch(
    "https://api.fireworks.ai/inference/v1/chat/completions",
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${args.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: args.model,
        temperature: 0.2,
        max_tokens: 520,
        messages: [
          { role: "system", content: args.systemPrompt },
          ...args.messages,
        ],
      }),
    },
  );

  if (!response.ok) {
    return {
      ok: false,
      errorText: await response.text(),
      data: null,
    };
  }

  return {
    ok: true,
    errorText: "",
    data: await response.json(),
  };
}

function shouldFallback(errorText: string) {
  const normalized = errorText.toLowerCase();
  return normalized.includes("not_found") ||
    normalized.includes("not found") ||
    normalized.includes("inaccessible") ||
    normalized.includes("not deployed");
}

function buildGuardrailContext(
  reading: Record<string, any> | null,
  thresholds: Record<string, any> | null,
  prediction: Record<string, any> | null,
) {
  if (!reading) {
    return "Guardrail: manca lettura sensori, quindi evita decisioni definitive su irrigazione.";
  }
  const moisture = Number(reading.moisture);
  const moistureLow = Number(thresholds?.moisture_low ?? 15);
  const moistureOk = Number(thresholds?.moisture_ok ?? 30);
  const lux = Number(reading.lux);
  const luxLow = Number(thresholds?.lux_low ?? 1000);
  const luxHigh = Number(thresholds?.lux_high ?? 18000);
  const predictedAction = String(prediction?.watering_action ?? "");
  const predictedLight = String(prediction?.light_action ?? "");

  return [
    `Guardrail umidita: attuale=${moisture.toFixed(1)} low=${moistureLow.toFixed(1)} ok=${moistureOk.toFixed(1)}.`,
    `Guardrail luce: attuale=${lux.toFixed(0)} low=${luxLow.toFixed(0)} high=${luxHigh.toFixed(0)}.`,
    `Guardrail previsione acqua: ${predictedAction || "n/a"}.`,
    `Guardrail previsione luce: ${predictedLight || "n/a"}.`,
    "Regola hard: se moisture >= moistureOk, evita 'water_now'.",
    "Regola hard: se moisture <= moistureLow, suggerisci irrigazione leggera e verifica.",
    "Regola hard: se lux < luxLow, suggerisci aumento graduale della luce.",
    "Regola hard: se lux > luxHigh, suggerisci riduzione della luce diretta.",
  ].join("\n");
}

function buildPlantTypeContext(plantType: string) {
  if (plantType.toLowerCase() !== "peperoncino") {
    return "Contesto specie: usa regole generiche conservative basate su sensori.";
  }
  return [
    "Contesto specie: peperoncino.",
    "Obiettivo biologico: substrato leggermente umido ma mai saturo; evita ristagni.",
    "Irrigazione peperoncino: se umidita >= target, non irrigare.",
    "Irrigazione peperoncino: se umidita e sotto low, irrigazione leggera e verifica dopo poche ore.",
    "Luce peperoncino: preferisce luce alta stabile; se lux bassa, suggerisci spostamento graduale.",
    "Se la visione suggerisce stress ma il sensore e in range, proponi verifica (substrato a 2cm, drenaggio, foto aggiuntiva) prima di cambiare acqua.",
    "Non usare tono poetico: fraseologia tecnica e concreta.",
  ].join("\n");
}

function parseAssistantJson(rawReply: string) {
  if (!rawReply) return null;
  try {
    return JSON.parse(rawReply);
  } catch (_) {
    const start = rawReply.indexOf("{");
    const end = rawReply.lastIndexOf("}");
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(rawReply.slice(start, end + 1));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

function buildSafeReply(args: {
  parsed: Record<string, any> | null;
  rawReply: string;
  reading: Record<string, any> | null;
  thresholds: Record<string, any> | null;
  prediction: Record<string, any> | null;
}) {
  const moisture = Number(args.reading?.moisture ?? NaN);
  const moistureLow = Number(args.thresholds?.moisture_low ?? 15);
  const moistureOk = Number(args.thresholds?.moisture_ok ?? 30);
  const lux = Number(args.reading?.lux ?? NaN);
  const luxLow = Number(args.thresholds?.lux_low ?? 1000);
  const luxHigh = Number(args.thresholds?.lux_high ?? 18000);
  const predictedAction = String(args.prediction?.watering_action ?? "");
  const predictedLight = String(args.prediction?.light_action ?? "");

  let waterDecision = String(args.parsed?.decision?.water ?? "check_soon");
  let lightDecision = String(args.parsed?.decision?.light ?? "ok");
  let urgency = String(args.parsed?.decision?.urgency ?? "medium").toLowerCase();
  let recheckHours = Number(args.parsed?.decision?.recheck_hours ?? NaN);

  if (!Number.isNaN(moisture) && moisture >= moistureOk && waterDecision === "water_now") {
    waterDecision = "wait";
  }
  if (!Number.isNaN(moisture) && moisture <= moistureLow) {
    waterDecision = "water_now";
  }
  if (
    predictedAction.toLowerCase().includes("non annaffiare") &&
    !Number.isNaN(moisture) &&
    moisture > moistureLow
  ) {
    waterDecision = "wait";
  }
  if (
    predictedAction.toLowerCase().includes("annaffia") &&
    !Number.isNaN(moisture) &&
    moisture < moistureOk
  ) {
    waterDecision = moisture <= moistureLow ? "water_now" : "check_soon";
  }

  if (!Number.isNaN(lux) && lux < luxLow) {
    lightDecision = "increase";
  } else if (!Number.isNaN(lux) && lux > luxHigh) {
    lightDecision = "reduce";
  } else if (!Number.isNaN(lux)) {
    lightDecision = "ok";
  } else if (predictedLight.toLowerCase().includes("aumenta")) {
    lightDecision = "increase";
  } else if (
    predictedLight.toLowerCase().includes("riduci") ||
    predictedLight.toLowerCase().includes("ombra")
  ) {
    lightDecision = "reduce";
  }

  if (!["high", "medium", "low"].includes(urgency)) {
    urgency = "medium";
  }
  if (!Number.isFinite(recheckHours) || recheckHours <= 0) {
    recheckHours = waterDecision === "water_now"
      ? 6
      : waterDecision === "check_soon"
      ? 12
      : 24;
  }
  if (!Number.isNaN(moisture) && moisture <= moistureLow) {
    urgency = "high";
    recheckHours = Math.min(recheckHours, 6);
  }
  if (!Number.isNaN(moisture) && moisture >= moistureOk && waterDecision === "wait") {
    urgency = urgency === "high" ? "high" : "medium";
    recheckHours = Math.max(recheckHours, 18);
  }

  const summary = String(
    args.parsed?.motivation?.summary ?? args.parsed?.summary ?? "",
  ).trim();
  const consistency = String(args.parsed?.motivation?.sensor_consistency ?? "").trim();
  const actions = Array.isArray(args.parsed?.actions)
    ? args.parsed.actions
      .map((item: unknown) => {
        if (item && typeof item === "object") {
          const raw = item as Record<string, unknown>;
          const title = String(raw.title ?? "").trim();
          const details = String(raw.details ?? "").trim();
          const when = String(raw.when ?? "").trim();
          return [title, details, when ? `(${when})` : ""]
            .filter((part) => part.length > 0)
            .join(" ");
        }
        return String(item);
      })
      .filter(Boolean)
    : [];
  const questions = Array.isArray(args.parsed?.questions)
    ? args.parsed.questions.map((item: unknown) => String(item)).filter(Boolean).slice(0, 2)
    : [];
  const parsedNeedsPhoto = Boolean(args.parsed?.needs_photo);
  const confidenceRaw = Number(args.parsed?.decision?.confidence ?? args.prediction?.confidence ?? NaN);
  const confidence = Number.isFinite(confidenceRaw)
    ? Math.max(0, Math.min(1, confidenceRaw))
    : 0.45;
  const sensorConflict = hasSensorConflict({
    moisture,
    moistureLow,
    moistureOk,
    predictedAction,
    lux,
    luxLow,
    luxHigh,
    predictedLight,
  });
  const isBorderlineMoisture = !Number.isNaN(moisture) &&
    moisture > moistureLow &&
    moisture < moistureOk;
  const needsPhoto = parsedNeedsPhoto &&
      (confidence < 0.62 || sensorConflict) ||
    (!Number.isNaN(moisture) &&
      isBorderlineMoisture &&
      sensorConflict &&
      confidence < 0.7) ||
    confidence < 0.5;

  const waterLine = waterDecision === "water_now"
    ? "Annaffia ora con dose leggera e uniforme, evitando ristagni."
    : waterDecision === "wait"
    ? "Non annaffiare adesso: il suolo non risulta in fascia secca."
    : "Controlla il suolo nelle prossime ore prima di decidere l'irrigazione.";
  const lightLine = lightDecision === "increase"
    ? "Aumenta gradualmente la luce disponibile (no cambio brusco)."
    : lightDecision === "reduce"
    ? "Riduci la luce diretta nelle ore più intense."
    : "Mantieni la posizione attuale rispetto alla luce.";
  const urgencyLine = urgency === "high"
    ? "Alta"
    : urgency === "low"
    ? "Bassa"
    : "Media";

  const primarySummary = summary || (!Number.isNaN(moisture)
    ? `Stato attuale: umidita suolo ${moisture.toFixed(1)}%.`
    : "Stato attuale: dati parziali.");

  const bulletActions = (actions.length > 0 ? actions : [waterLine, lightLine]).slice(0, 3);
  const followup = questions.length > 0
    ? `\nDomande utili:\n- ${questions.join("\n- ")}`
    : "";
  const photoHint = needsPhoto
    ? "\nVerifica richiesta: invia foto pianta intera, foglia (fronte/retro) e terriccio."
    : "";

  return [
    `Decisione: acqua=${waterDecision}, luce=${lightDecision}, urgenza=${urgencyLine}.`,
    `Riepilogo: ${primarySummary}`,
    consistency.isNotEmpty ? `Coerenza sensori: ${consistency}` : null,
    "",
    "Azioni:",
    `- Acqua: ${waterLine}`,
    `- Luce: ${lightLine}`,
    ...bulletActions
      .filter((line) => {
        const lower = line.toLowerCase();
        return !lower.includes("acqua:") && !lower.includes("luce:");
      })
      .map((line) => `- ${line}`),
    `- Ricontrollo: tra ${Math.round(recheckHours)} ore.`,
    followup,
    photoHint,
  ].filter((line): line is string => typeof line === "string" && line.length > 0)
    .join("\n");
}

function extractAiMeta(
  parsed: Record<string, any> | null,
  prediction: Record<string, any> | null,
  safeReply: string,
) {
  const decision = parsed?.decision ?? {};
  const parsedConfidence = Number(decision.confidence);
  const predictionConfidence = Number(prediction?.confidence);
  const confidence = !Number.isNaN(parsedConfidence)
    ? parsedConfidence
    : !Number.isNaN(predictionConfidence)
    ? predictionConfidence
    : 0.45;

  const explicitPhotoRequest = Boolean(parsed?.needs_photo);
  const needsPhoto = (explicitPhotoRequest && confidence < 0.62) ||
    safeReply.toLowerCase().includes("invia foto");
  const lowConfidence = confidence < 0.62;
  const needsFollowUp = needsPhoto || lowConfidence || !parsed;

  const urgency = String(decision.urgency ?? decision.priority ?? "medium").toLowerCase();
  const hours = urgency === "high" ? 24 : urgency === "low" ? 72 : 48;
  const followUpDueAt = needsFollowUp
    ? new Date(Date.now() + (hours * 60 * 60 * 1000))
    : null;

  return {
    confidence: Number(confidence.toFixed(3)),
    needsPhoto,
    needsFollowUp,
    followUpDueAt,
  };
}

function hasSensorConflict(args: {
  moisture: number;
  moistureLow: number;
  moistureOk: number;
  predictedAction: string;
  lux: number;
  luxLow: number;
  luxHigh: number;
  predictedLight: string;
}) {
  const waterText = args.predictedAction.toLowerCase();
  const lightText = args.predictedLight.toLowerCase();

  const waterSaysWait = waterText.includes("non annaff");
  const waterSaysNow = waterText.includes("annaffia");
  const moistureClearlyDry = !Number.isNaN(args.moisture) &&
    args.moisture <= args.moistureLow;
  const moistureClearlyWet = !Number.isNaN(args.moisture) &&
    args.moisture >= args.moistureOk;
  const waterConflict = (waterSaysWait && moistureClearlyDry) ||
    (waterSaysNow && moistureClearlyWet);

  const lightSaysIncrease = lightText.includes("aument");
  const lightSaysReduce = lightText.includes("riduc") || lightText.includes("ombra");
  const luxLowConflict = !Number.isNaN(args.lux) &&
    args.lux < args.luxLow &&
    lightSaysReduce;
  const luxHighConflict = !Number.isNaN(args.lux) &&
    args.lux > args.luxHigh &&
    lightSaysIncrease;
  const lightConflict = luxLowConflict || luxHighConflict;

  return waterConflict || lightConflict;
}

function buildTelemetryContext(
  reading: Record<string, any> | null,
  readingHistory: Record<string, any>[],
  prediction: Record<string, any> | null,
): string {
  const latestLine = reading
    ? `Ultima lettura: umidita ${Number(reading.moisture).toFixed(1)}%, luce ${Number(reading.lux).toFixed(0)} lx.`
    : "Ultima lettura: non disponibile.";

  const historyLines = readingHistory
    .slice(-12)
    .map((item) => {
      const moisture = Number(item.moisture);
      const lux = Number(item.lux);
      const when = String(item.created_at ?? "");
      return `- ${when}: umidita ${moisture.toFixed(1)}%, luce ${lux.toFixed(0)} lx`;
    })
    .join("\n");

  const predictionLine = prediction
    ? `Motore predittivo: ${String(prediction.summary ?? "")}; azione acqua: ${String(prediction.watering_action ?? "")}; azione luce: ${String(prediction.light_action ?? "")}; confidenza: ${String(prediction.confidence ?? "n/a")}.`
    : "Motore predittivo: non disponibile.";

  return `${latestLine}\n${predictionLine}\nStorico recente:\n${historyLines}`;
}

function buildMessages(userMessage: string, imageUrls: string[]) {
  if (imageUrls.length === 0) {
    return [{ role: "user", content: userMessage }];
  }

  return [{
    role: "user",
    content: [
      { type: "text", text: userMessage },
      ...imageUrls.map((url) => ({
        type: "image_url",
        image_url: { url },
      })),
    ],
  }];
}

function validateImageInputs(imageUrls: string[]) {
  if (imageUrls.length > maxImages) {
    return `Too many images: max ${maxImages}`;
  }
  for (const url of imageUrls) {
    if (url.length > maxDataUrlChars) {
      return "Image payload too large";
    }
    const isDataUrl = url.startsWith("data:image/");
    const isHttpUrl = url.startsWith("https://");
    if (!isDataUrl && !isHttpUrl) {
      return "Unsupported image format";
    }
  }
  return null;
}
