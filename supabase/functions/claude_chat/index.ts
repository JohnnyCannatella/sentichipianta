// deno-lint-ignore-file no-explicit-any
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

declare global {
  interface ImportMeta {
    main: boolean;
  }
}

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
  const sanitizedBody = sanitizeJsonValue(body) as Record<string, any>;
  return new Response(JSON.stringify(sanitizedBody), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

export async function handleRequest(req: Request) {
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
    const plantId = payload.plant_id ?? null;
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
    const recentConversation = await loadRecentConversation(plantId);
    const messages = buildMessages(userMessage, imageUrls, recentConversation);
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
      "Usa il contesto dei messaggi precedenti per evitare ripetizioni inutili e mantenere coerenza conversazionale. " +
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

    const rawReply = sanitizeText(String(data?.choices?.[0]?.message?.content ?? "").trim());
    const parsed = parseAssistantJson(rawReply);
    const plantContext = await loadPlantContext({
      plantId,
      payloadPlant: payload.plant,
      fallbackName: plantName,
      fallbackType: plantType,
    });
    const safeReply = buildSafeReply({
      parsed,
      rawReply,
      userMessage,
      plantName: plantContext.name,
      plantType: plantContext.type,
      plantCreatedAt: plantContext.createdAt,
      hasImages: imageUrls.length > 0,
      reading,
      thresholds,
      prediction,
    });
    const aiMeta = extractAiMeta(parsed, prediction, safeReply);
    const followUpDueAt = aiMeta.followUpDueAt?.toISOString() ?? null;

    if (plantId != null) {
      const { error: insertError } = await supabase.from("messages").insert([
        {
          plant_id: plantId,
          role: "user",
          content: sanitizeText(userMessage),
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
          raw: sanitizeText(rawReply),
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
}

if (import.meta.main) {
  serve(handleRequest);
}

async function loadPlantContext(args: {
  plantId: string | null;
  payloadPlant: Record<string, any> | null;
  fallbackName: string;
  fallbackType: string;
}) {
  const payloadCreatedAt = parseIsoDate(args.payloadPlant?.created_at);
  const payloadName = String(args.payloadPlant?.name ?? "").trim();
  const payloadType = String(args.payloadPlant?.plant_type ?? "").trim();

  let dbName = "";
  let dbType = "";
  let dbCreatedAt: Date | null = null;

  if (args.plantId) {
    const { data } = await supabase
      .from("plants")
      .select("name, plant_type, created_at")
      .eq("id", args.plantId)
      .limit(1)
      .maybeSingle();
    if (data && typeof data === "object") {
      dbName = String(data.name ?? "").trim();
      dbType = String(data.plant_type ?? "").trim();
      dbCreatedAt = parseIsoDate(data.created_at);
    }
  }

  return {
    name: dbName || payloadName || args.fallbackName,
    type: dbType || payloadType || args.fallbackType || "generic",
    createdAt: dbCreatedAt ?? payloadCreatedAt,
  };
}

async function loadRecentConversation(plantId: string | null) {
  if (!plantId) return [];
  const { data } = await supabase
    .from("messages")
    .select("role, content, created_at")
    .eq("plant_id", plantId)
    .order("created_at", { ascending: false })
    .limit(10);

  const rows = Array.isArray(data) ? data : [];
  return rows
    .reverse()
    .map((row) => {
      const role = String(row.role ?? "").toLowerCase();
      if (role !== "user" && role !== "assistant") return null;
      const normalizedContent = normalizeHistoryContent(String(row.content ?? ""));
      if (!normalizedContent) return null;
      return {
        role,
        content: normalizedContent,
      };
    })
    .filter((item): item is { role: "user" | "assistant"; content: string } =>
      Boolean(item)
    )
    .slice(-8);
}

function parseIsoDate(value: unknown): Date | null {
  if (!value) return null;
  const raw = String(value).trim();
  if (!raw) return null;
  const dt = new Date(raw);
  return Number.isNaN(dt.getTime()) ? null : dt;
}

function sanitizeText(value: string) {
  return value
    .replace(/\r\n/g, "\n")
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, " ")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
}

function sanitizeJsonValue(value: unknown): unknown {
  if (typeof value === "string") return sanitizeText(value);
  if (Array.isArray(value)) return value.map((item) => sanitizeJsonValue(item));
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>).map(([k, v]) => [
        k,
        sanitizeJsonValue(v),
      ]),
    );
  }
  return value;
}

function normalizeHistoryContent(content: string) {
  const sanitized = sanitizeText(content);
  if (!sanitized) return "";

  const lines = sanitized
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  const responseLine = lines.find((line) => line.startsWith("Risposta:"));
  const summaryLine = lines.find((line) => line.startsWith("Riepilogo:"));
  const compact = [responseLine, summaryLine]
    .filter((part): part is string => Boolean(part))
    .join(" ");
  const base = compact || lines.slice(0, 2).join(" ");
  return base.slice(0, 700);
}

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
  userMessage: string;
  plantName: string;
  plantType: string;
  plantCreatedAt: Date | null;
  hasImages: boolean;
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

  const summary = sanitizeText(String(
    args.parsed?.motivation?.summary ?? args.parsed?.summary ?? "",
  ));
  const consistency = sanitizeText(String(args.parsed?.motivation?.sensor_consistency ?? ""));
  const actions = Array.isArray(args.parsed?.actions)
    ? args.parsed.actions
      .map((item: unknown) => {
        if (item && typeof item === "object") {
          const raw = item as Record<string, unknown>;
          const title = sanitizeText(String(raw.title ?? ""));
          const details = sanitizeText(String(raw.details ?? ""));
          const when = sanitizeText(String(raw.when ?? ""));
          return [title, details, when ? `(${when})` : ""]
            .filter((part) => part.length > 0)
            .join(" ");
        }
        return String(item);
      })
      .filter(Boolean)
    : [];
  const questions = Array.isArray(args.parsed?.questions)
    ? args.parsed.questions.map((item: unknown) => sanitizeText(String(item))).filter(Boolean)
      .slice(0, 2)
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
  const conversationalReply = buildConversationalReply({
    userMessage: args.userMessage,
    plantName: args.plantName,
    plantType: args.plantType,
    plantCreatedAt: args.plantCreatedAt,
    hasImages: args.hasImages,
    summary: primarySummary,
    waterDecision,
    lightDecision,
    urgency,
  });

  const bulletActions = (actions.length > 0 ? actions : [waterLine, lightLine]).slice(0, 3);
  const followup = questions.length > 0
    ? `\nDomande utili:\n- ${questions.join("\n- ")}`
    : "";
  const photoHint = needsPhoto
    ? "\nVerifica richiesta: invia foto pianta intera, foglia (fronte/retro) e terriccio."
    : "";

  const composed = [
    `Risposta: ${conversationalReply}`,
    `Decisione: acqua=${waterDecision}, luce=${lightDecision}, urgenza=${urgencyLine}.`,
    `Riepilogo: ${primarySummary}`,
    consistency.length > 0 ? `Coerenza sensori: ${consistency}` : null,
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
  return sanitizeText(composed);
}

function firstSentence(text: string) {
  const normalized = String(text ?? "").trim();
  if (!normalized) {
    return "Situazione aggiornata.";
  }
  const idx = normalized.indexOf(".");
  return idx >= 0 ? normalized.slice(0, idx + 1).trim() : normalized;
}

export function buildConversationalReply(args: {
  userMessage: string;
  plantName: string;
  plantType: string;
  plantCreatedAt: Date | null;
  hasImages: boolean;
  summary: string;
  waterDecision: string;
  lightDecision: string;
  urgency: string;
}) {
  const msg = args.userMessage.toLowerCase().replace(/[^a-z0-9\u00C0-\u024F\s]/gi, " ");
  const statusLine = args.urgency === "high"
    ? "In questo momento richiedo attenzione prioritaria."
    : "In questo momento sono abbastanza stabile.";
  const summaryLine = firstSentence(args.summary);
  const plantName = args.plantName.trim() || "la pianta";

  const isGreeting = containsAny(msg, [
    "ciao",
    "buongiorno",
    "buonasera",
    "hey",
    "salve",
  ]);
  const asksAge = (containsAny(msg, ["quanti giorni", "da quanto tempo", "eta", "età"]) &&
      containsAny(msg, ["vita", "vivi", "sei"])) ||
    containsAny(msg, ["da quanti giorni sei in vita"]);
  const asksNeed = containsAny(msg, [
    "hai bisogno",
    "di cosa hai bisogno",
    "cosa ti serve",
    "serve qualcosa",
  ]);
  const asksCareHow = containsAny(msg, [
    "come faccio a tenerti in vita",
    "come ti tengo in vita",
    "come prendermi cura",
    "come posso curarti",
    "cosa devo fare per tenerti bene",
  ]);
  const asksPlantType = containsAny(msg, [
    "che tipo di pianta",
    "che pianta sei",
    "di che specie sei",
    "che specie sei",
  ]);
  const asksAlive = containsAny(msg, [
    "sei viva",
    "sei ancora viva",
    "stai viva",
    "stai bene",
    "stai morendo",
    "sei messa male",
  ]);
  const asksYellowIssue = containsAny(msg, [
    "peperoncini sono gialli",
    "peperoncini gialli",
    "foglie gialle",
    "frutti gialli",
    "ingiall",
    "gialli",
  ]);
  const asksHealthIssue = containsAny(msg, [
    "macchie",
    "afidi",
    "parassiti",
    "insetti",
    "foglie arricciate",
    "arricciate",
    "carenza",
    "fungo",
    "muffa",
    "malatt",
  ]);

  if (asksAge) {
    if (!args.plantCreatedAt) {
      return `Non ho una data di nascita registrata per ${plantName}, ma ${statusLine.toLowerCase()}`;
    }
    const now = new Date();
    const ms = now.getTime() - args.plantCreatedAt.getTime();
    const days = Math.max(0, Math.floor(ms / (24 * 60 * 60 * 1000)));
    const dayLabel = days === 1 ? "giorno" : "giorni";
    return `Sono in vita da circa ${days} ${dayLabel}. ${statusLine}`;
  }

  if (asksCareHow || asksNeed) {
    const waterNeed = args.waterDecision === "water_now"
      ? "Acqua: oggi serve una irrigazione leggera."
      : args.waterDecision === "wait"
      ? "Acqua: adesso non irrigare."
      : "Acqua: controlla il suolo nelle prossime ore.";
    const lightNeed = args.lightDecision === "increase"
      ? "Luce: aumenta gradualmente l'esposizione."
      : args.lightDecision === "reduce"
      ? "Luce: riduci la luce diretta nelle ore intense."
      : "Luce: mantieni la posizione attuale.";
    const speciesHint = buildSpeciesHint(args.plantType);
    return `${statusLine} Per tenermi bene: ${waterNeed} ${lightNeed}${speciesHint}`;
  }

  if (asksPlantType) {
    const label = plantTypeLabel(args.plantType);
    return `Sono una pianta di tipo ${label}. ${statusLine} ${summaryLine}`;
  }

  if (asksAlive) {
    const visualNote = args.hasImages
      ? " Ho considerato anche la foto che hai inviato."
      : "";
    return `Si, sono viva.${visualNote} ${statusLine} ${summaryLine}`;
  }

  if (asksYellowIssue) {
    const waterHint = args.waterDecision === "water_now"
      ? "Valuta una irrigazione leggera: stress idrico puo favorire ingiallimenti."
      : args.waterDecision === "wait"
      ? "Evita eccessi d'acqua: troppo umido puo contribuire all'ingiallimento."
      : "Controlla l'umidita a 2 cm prima di irrigare.";
    const lightHint = args.lightDecision === "increase"
      ? "Aumenta gradualmente la luce: luce bassa puo rallentare maturazione e colore."
      : args.lightDecision === "reduce"
      ? "Riduci luce diretta intensa: stress da sole puo causare scolorimenti."
      : "Mantieni luce stabile e monitorata.";
    const photoNote = args.hasImages
      ? " Dalla foto posso fare una prima valutazione, ma conferma anche stato foglie e peduncolo."
      : " Se puoi, invia foto ravvicinata di frutti e foglie per distinguere maturazione normale da carenza.";
    return `Possibili cause dei peperoncini gialli: maturazione, stress luce/acqua o carenze nutrizionali lievi. ${waterHint} ${lightHint}${photoNote}`;
  }

  if (asksHealthIssue) {
    const checklist = [
      "foglie (fronte/retro): presenza di puntini, aloni o insetti",
      "fusto/nodi: lesioni, marciumi o muffe",
      "substrato: odore, compattazione e ristagno",
      "diffusione: problema su poche foglie o su tutta la pianta",
    ].join("; ");
    const waterHint = args.waterDecision === "water_now"
      ? "Acqua: fai solo irrigazione leggera e verifica drenaggio."
      : args.waterDecision === "wait"
      ? "Acqua: evita irrigazioni aggiuntive finche non confermi secchezza a 2 cm."
      : "Acqua: prima misura l'umidita a 2 cm e poi decidi.";
    const lightHint = args.lightDecision === "increase"
      ? "Luce: aumenta gradualmente, evitando shock improvvisi."
      : args.lightDecision === "reduce"
      ? "Luce: riduci esposizione diretta nelle ore intense."
      : "Luce: mantieni posizione stabile.";
    const photoHint = args.hasImages
      ? " Ho visto la foto, ma per diagnosi migliore servono anche dettagli ravvicinati di foglie e nodi."
      : " Invia foto ravvicinate di foglie (fronte/retro), fusto e terriccio per una valutazione piu affidabile.";
    return `Capito: potrebbe essere stress, carenza o parassiti, non una sola causa certa al primo passaggio. Checklist osservabile: ${checklist}. ${waterHint} ${lightHint}${photoHint}`;
  }

  if (isGreeting) {
    return `Ciao. ${statusLine} ${summaryLine}`;
  }

  const asksForWater = msg.includes("acqua") ||
    msg.includes("annaff") ||
    msg.includes("irrig");
  if (asksForWater) {
    if (args.waterDecision === "water_now") {
      return "Si, ora conviene una irrigazione leggera e uniforme.";
    }
    if (args.waterDecision === "wait") {
      return "No, adesso non irrigare: il suolo non e ancora in fascia secca.";
    }
    return "Per ora non irrigare subito: ricontrolla il suolo nelle prossime ore.";
  }

  const asksForLight = msg.includes("luce") ||
    msg.includes("sole") ||
    msg.includes("ombra");
  if (asksForLight) {
    if (args.lightDecision === "increase") {
      return "Conviene aumentare gradualmente la luce disponibile.";
    }
    if (args.lightDecision === "reduce") {
      return "Conviene ridurre la luce diretta nelle ore piu intense.";
    }
    return "La luce attuale e adeguata: mantieni la posizione.";
  }

  const asksForInfo = msg.includes("inform") ||
    msg.includes("come stai") ||
    msg.includes("stato") ||
    msg.includes("situazione");
  if (asksForInfo) {
    return `${statusLine} ${summaryLine}`;
  }

  return `${statusLine} ${summaryLine}`;
}

function containsAny(text: string, parts: string[]) {
  return parts.some((part) => text.includes(part));
}

function buildSpeciesHint(plantType: string) {
  const normalized = plantType.trim().toLowerCase();
  if (normalized === "peperoncino") {
    return " Specie: peperoncino, preferisco luce alta stabile e substrato umido ma non saturo.";
  }
  if (normalized === "cactus") {
    return " Specie: cactus, meglio irrigazioni distanziate e molta luce.";
  }
  if (normalized === "sansevieria") {
    return " Specie: sansevieria, tollero bene periodi con poca acqua.";
  }
  if (normalized === "bonsai") {
    return " Specie: bonsai, utile controllo frequente del substrato.";
  }
  return "";
}

function plantTypeLabel(plantType: string) {
  const normalized = plantType.trim().toLowerCase();
  if (normalized === "peperoncino") return "peperoncino";
  if (normalized === "cactus") return "cactus";
  if (normalized === "sansevieria") return "sansevieria";
  if (normalized === "bonsai") return "bonsai";
  return "generica";
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

function buildMessages(
  userMessage: string,
  imageUrls: string[],
  recentConversation: Array<{ role: "user" | "assistant"; content: string }>,
) {
  const historyMessages = recentConversation.map((item) => ({
    role: item.role,
    content: item.content,
  }));

  if (imageUrls.length === 0) {
    return [
      ...historyMessages,
      { role: "user", content: userMessage },
    ];
  }

  return [
    ...historyMessages,
    {
      role: "user",
      content: [
        { type: "text", text: userMessage },
        ...imageUrls.map((url) => ({
          type: "image_url",
          image_url: { url },
        })),
      ],
    },
  ];
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
