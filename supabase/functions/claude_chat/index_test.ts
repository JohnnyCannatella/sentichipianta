import {
  assert,
  assertMatch,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildConversationalReply } from "./index.ts";

function baseArgs(message: string) {
  return {
    userMessage: message,
    plantName: "Pepe",
    plantType: "peperoncino",
    plantCreatedAt: new Date("2026-02-15T10:00:00Z"),
    hasImages: false,
    summary: "Umidita del substrato al 56.0%.",
    waterDecision: "wait",
    lightDecision: "increase",
    urgency: "medium",
  } as const;
}

Deno.test("intent: sei ancora viva", () => {
  const reply = buildConversationalReply(baseArgs("Sei ancora viva?"));
  assertStringIncludes(reply, "Si, sono viva.");
});

Deno.test("intent: peperoncini gialli", () => {
  const reply = buildConversationalReply(baseArgs("Perche i peperoncini sono gialli?"));
  assertStringIncludes(reply, "Possibili cause dei peperoncini gialli");
  assertStringIncludes(reply, "Se puoi, invia foto ravvicinata");
});

Deno.test("intent: che tipo di pianta sei", () => {
  const reply = buildConversationalReply(baseArgs("Che tipo di pianta sei?"));
  assertStringIncludes(reply, "Sono una pianta di tipo peperoncino.");
});

Deno.test("intent: come tenerti in vita", () => {
  const reply = buildConversationalReply(baseArgs("Come faccio a tenerti in vita?"));
  assertStringIncludes(reply, "Per tenermi bene:");
  assertStringIncludes(reply, "Acqua:");
  assertStringIncludes(reply, "Luce:");
});

Deno.test("intent: quanti giorni in vita", () => {
  const reply = buildConversationalReply(
    baseArgs("Ciao, da quanti giorni sei in vita?"),
  );
  assertMatch(reply, /Sono in vita da circa \d+ giorni\./);
});

Deno.test("intent: patologie parassiti con checklist", () => {
  const reply = buildConversationalReply(baseArgs("Vedo macchie e forse afidi, puo essere un fungo?"));
  assertStringIncludes(reply, "Checklist osservabile:");
  assertStringIncludes(reply, "foglie (fronte/retro)");
  assertStringIncludes(reply, "substrato");
  assert(reply.toLowerCase().includes("parassiti") || reply.toLowerCase().includes("carenza"));
});
