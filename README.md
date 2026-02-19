# Senti Chi Pianta - v2.0

Per una guida rapida (1 pagina): vedi `README_SHORT.md`.

App Flutter per monitorare e assistere la cura delle piante con:
- sensori reali (umidita suolo + luce),
- chat AI in cloud,
- analisi immagini on-demand,
- storico decisioni AI con feedback.

Questo README e pensato per chi vuole capire e replicare il progetto end-to-end.

## 1. Cosa fa il progetto

`Senti Chi Pianta` unisce IoT + AI:
- legge i dati dal terreno (umidita) e dalla luce ambientale,
- salva le letture su Supabase,
- usa un motore AI (Fireworks) per suggerire azioni pratiche,
- supporta foto in chat per verifiche visive,
- traccia gli esiti delle decisioni AI (migliorata/uguale/peggiorata).

Focus v2.0:
- meno "chat poetica",
- piu raccomandazioni operative,
- guardrail per evitare consigli incoerenti con i sensori.

## 2. Stack tecnologico

- Frontend mobile: `Flutter` (Dart)
- Backend AI/API: `Supabase Edge Functions` (Deno/TypeScript)
- Database e realtime: `Supabase Postgres`
- AI engine: `Fireworks` (chat completions)
- Notifiche locali: `flutter_local_notifications`
- Foto chat: `image_picker`

## 3. Struttura progetto

- `lib/`: app Flutter (UI, dominio, repository, servizi)
- `supabase/functions/claude_chat/`: funzione AI chat
- `supabase/functions/ingest_reading/`: endpoint ingest sensori
- `supabase/migrations/`: migrazioni DB
- `test/`: test unitari/widget
- `Progetto Pianta - ARDUINO.ino`: sketch Arduino di riferimento

## 4. Prerequisiti

- Flutter SDK (consigliato canale stable)
- Xcode (per iOS)
- Supabase CLI
- Account Supabase
- Account Fireworks con API key
- Sensori (attualmente supportati nel flusso):
  - BH1750 (luce)
  - Soil Moisture sensor (umidita suolo)

## 5. Configurazione cloud (Supabase + Fireworks)

### 5.1 Edge Functions

Funzioni usate:
- `claude_chat` (motore AI)
- `ingest_reading` (ingest dati sensori)

File importanti:
- `/Users/johnnycannatella/WebstormProjects/sentichipianta/supabase/functions/claude_chat/index.ts`
- `/Users/johnnycannatella/WebstormProjects/sentichipianta/supabase/functions/ingest_reading/index.ts`
- `/Users/johnnycannatella/WebstormProjects/sentichipianta/supabase/config.toml`

`config.toml` contiene:
- `verify_jwt = false` per `claude_chat` (si usa `x-chat-secret`).

### 5.2 Secrets da impostare su Supabase

Per `claude_chat`:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `FIREWORKS_API_KEY`
- `CHAT_SECRET`
- opzionali:
  - `FIREWORKS_MODEL`
  - `FIREWORKS_FALLBACK_MODEL`

Per `ingest_reading`:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `INGEST_SECRET` (opzionale ma consigliato)

### 5.3 Deploy funzione AI

```bash
supabase functions deploy claude_chat --project-ref <TUO_PROJECT_REF>
```

### 5.4 Deploy ingest sensori

```bash
supabase functions deploy ingest_reading --project-ref <TUO_PROJECT_REF>
```

## 6. Configurazione database

Migrazioni attuali:
- `/Users/johnnycannatella/WebstormProjects/sentichipianta/supabase/migrations/20260207_add_plant_type.sql`
- `/Users/johnnycannatella/WebstormProjects/sentichipianta/supabase/migrations/20260217_add_ai_decisions.sql`

Tabelle chiave usate dall'app:
- `plants`
- `readings`
- `messages`
- `ai_decisions`

`ai_decisions` salva:
- snapshot sensori,
- raccomandazione AI,
- confidenza,
- follow-up,
- outcome (`improved|same|worse`).

## 7. Avvio app in locale

Installa dipendenze:

```bash
flutter pub get
```

Avvio debug:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY \
  --dart-define=AI_ENDPOINT=https://YOUR_PROJECT.supabase.co/functions/v1/claude_chat \
  --dart-define=CHAT_SECRET=YOUR_CHAT_SECRET
```

Note:
- La variabile corretta per endpoint AI e `AI_ENDPOINT` (vedi `lib/config/app_config.dart`).
- Se vuoi scegliere device specifico: aggiungi `-d <device_id>`.

## 8. Build release su telefono

Esempio:

```bash
flutter run --release \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY \
  --dart-define=AI_ENDPOINT=https://YOUR_PROJECT.supabase.co/functions/v1/claude_chat \
  --dart-define=CHAT_SECRET=YOUR_CHAT_SECRET
```

## 9. Ingest sensori (Arduino -> Supabase)

La funzione `ingest_reading` accetta `POST` JSON con:
- `plant_id` (obbligatorio)
- `moisture` (obbligatorio, numero)
- `lux` (obbligatorio, numero)
- `temperature` (opzionale)
- `created_at` (opzionale)

Header consigliato:
- `x-ingest-secret: YOUR_INGEST_SECRET`

Esempio `curl`:

```bash
curl -X POST "https://YOUR_PROJECT.supabase.co/functions/v1/ingest_reading" \
  -H "Content-Type: application/json" \
  -H "x-ingest-secret: YOUR_INGEST_SECRET" \
  -d '{
    "plant_id": "UUID_PIANTA",
    "moisture": 49,
    "lux": 14500
  }'
```

## 10. UX e logica AI introdotte nella v2.0

- Chat con allegati foto (camera/galleria)
- Richiesta foto piu selettiva (solo quando utile)
- Decisioni AI rese operative:
  - acqua,
  - luce,
  - urgenza,
  - tempo di ricontrollo
- Guardrail hard server-side per evitare contraddizioni sensori/consigli
- Storico decisioni AI con outcome loop
- Schermate `Home`, `Piante` e `Storico` rese coerenti a livello UX/UI
- Routine chat meno invasive (dedup/cooldown)

## 11. Comandi utili sviluppo

Analisi statica:

```bash
flutter analyze
```

Test:

```bash
flutter test
```

Format:

```bash
dart format .
```

## 12. Troubleshooting rapido

### Errore locale data (intl)
Messaggio tipico:
`LocaleDataException: Locale data has not been initialized`

Gia gestito in `main.dart` con:
- `initializeDateFormatting('it_IT')`

### AI non risponde
Controlla:
- `AI_ENDPOINT` nei `--dart-define`
- deploy function `claude_chat`
- secrets in Supabase (`FIREWORKS_API_KEY`, `CHAT_SECRET`, ecc.)

### Messaggi "non sincronizzati"
La UI mostra banner solo quando ci sono messaggi utente non persistiti.
Usa `Riprova sync` o verifica connessione/network policy.

## 13. Sicurezza

- Non committare chiavi reali nel repository.
- Usa placeholders nei file pubblici.
- Mantieni `SERVICE_ROLE_KEY`, `FIREWORKS_API_KEY`, `CHAT_SECRET`, `INGEST_SECRET` solo su variabili ambiente cloud.

## 14. Roadmap suggerita

- calibrazione guidata sensore umidita (secco/reale, bagnato/reale)
- policy specie-specifiche avanzate (es. peperoncino)
- automazioni intelligenti piu spinte
- dashboard metriche performance AI (precisione vs outcome storico)

---

Se usi questo progetto per contenuti (YouTube/Substack), il consiglio e mostrare il flusso completo:
1) sensore -> 2) cloud -> 3) AI -> 4) decisione -> 5) outcome.
