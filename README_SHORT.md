# Senti Chi Pianta - Quick Start

Versione breve per chi vuole avviare il progetto in pochi minuti.

## Cos'e

App Flutter che unisce:
- sensori pianta (umidita suolo + luce),
- backend cloud su Supabase,
- AI su Fireworks per consigli pratici (acqua, luce, urgenza, ricontrollo).

## Stack

- Flutter (mobile app)
- Supabase (DB + Edge Functions)
- Fireworks (LLM/VLM)

## Setup minimo

1. Installa dipendenze:

```bash
flutter pub get
```

2. Configura Supabase Edge Function `claude_chat` con secrets:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `FIREWORKS_API_KEY`
- `CHAT_SECRET`

3. Deploy funzione AI:

```bash
supabase functions deploy claude_chat --project-ref <PROJECT_REF>
```

4. Avvia app:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY \
  --dart-define=AI_ENDPOINT=https://YOUR_PROJECT.supabase.co/functions/v1/claude_chat \
  --dart-define=CHAT_SECRET=YOUR_CHAT_SECRET
```

## Release su telefono

```bash
flutter run --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY \
  --dart-define=AI_ENDPOINT=https://YOUR_PROJECT.supabase.co/functions/v1/claude_chat \
  --dart-define=CHAT_SECRET=YOUR_CHAT_SECRET
```

## Funzioni principali v2.0

- Chat AI con supporto foto
- Guardrail anti-contraddizioni sensori/consigli
- Storico decisioni AI con outcome (`Migliorata/Uguale/Peggiorata`)
- UX aggiornata su Home, Piante, Storico
- Routine chat meno invasive (dedup + cooldown)

## Ingest sensori (facoltativo, consigliato)

Deploy:

```bash
supabase functions deploy ingest_reading --project-ref <PROJECT_REF>
```

Payload minimo richiesto:
- `plant_id`
- `moisture`
- `lux`

## Comandi utili

```bash
flutter analyze
flutter test
dart format .
```

## Note rapide

- Non committare chiavi reali.
- Se AI non risponde: verifica endpoint + deploy + secrets.
- README completo: `README.md`

