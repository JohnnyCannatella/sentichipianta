create table if not exists public.ai_decisions (
  id bigint generated always as identity primary key,
  plant_id uuid not null references public.plants(id) on delete cascade,
  created_at timestamptz not null default now(),
  source text not null default 'fireworks',
  model text,
  sensor_snapshot jsonb not null default '{}'::jsonb,
  recommendation jsonb not null default '{}'::jsonb,
  confidence numeric,
  needs_follow_up boolean not null default false,
  follow_up_due_at timestamptz,
  outcome text
);

alter table public.ai_decisions
  drop constraint if exists ai_decisions_outcome_check;

alter table public.ai_decisions
  add constraint ai_decisions_outcome_check
  check (outcome is null or outcome in ('improved', 'same', 'worse'));

create index if not exists ai_decisions_plant_created_idx
  on public.ai_decisions (plant_id, created_at desc);

create index if not exists ai_decisions_follow_up_idx
  on public.ai_decisions (needs_follow_up, follow_up_due_at);
