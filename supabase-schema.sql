-- ============================================================
-- FLIGHTLOG — SUPABASE SCHEMA
-- ============================================================
-- Run this once in your Supabase project's SQL Editor:
-- Dashboard → SQL Editor → New query → paste this whole file → Run.
--
-- ARCHITECTURE NOTE:
-- Flightlog keeps ONE row per user in `app_state`, holding your
-- entire app data (tasks, habits, notifications, focus sessions,
-- templates, history) as a single JSONB blob — the same shape the
-- browser-only version kept in localStorage. This is a deliberate
-- simplification, not an oversight:
--   - One table, one realtime subscription, one sync codepath.
--   - Fully satisfies "same data on phone/laptop/desktop in real time."
--   - Trade-off: sync is last-write-wins on the WHOLE blob, not
--     per-field. Editing the same task on two devices in the same
--     instant means one edit wins, not a merge. Fine for "I closed
--     my laptop and picked up my phone," not built for true
--     simultaneous multi-device editing. If you ever want that,
--     it means decomposing into relational tables — a bigger
--     migration, and not needed for what you asked for.
-- ============================================================

-- Needed for gen_random_uuid() if you later add more tables.
create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- TABLE: app_state
-- ------------------------------------------------------------
create table if not exists public.app_state (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  state       jsonb not null default '{}'::jsonb,
  client_id   text,                      -- id of the browser tab that made the last write, used client-side to ignore its own realtime echo
  updated_at  timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

comment on table public.app_state is 'One row per user. Holds the entire Flightlog app state as JSONB.';

-- ------------------------------------------------------------
-- Keep updated_at accurate even if a client forgets to set it
-- ------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_app_state_updated_at on public.app_state;
create trigger trg_app_state_updated_at
  before update on public.app_state
  for each row
  execute function public.set_updated_at();

-- ------------------------------------------------------------
-- ROW LEVEL SECURITY
-- Every user can only ever see or touch their own row.
-- ------------------------------------------------------------
alter table public.app_state enable row level security;

drop policy if exists "select own state" on public.app_state;
create policy "select own state"
  on public.app_state for select
  using (auth.uid() = user_id);

drop policy if exists "insert own state" on public.app_state;
create policy "insert own state"
  on public.app_state for insert
  with check (auth.uid() = user_id);

drop policy if exists "update own state" on public.app_state;
create policy "update own state"
  on public.app_state for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "delete own state" on public.app_state;
create policy "delete own state"
  on public.app_state for delete
  using (auth.uid() = user_id);

-- ------------------------------------------------------------
-- REALTIME
-- Lets a signed-in client subscribe to changes on their own row
-- (e.g. an edit made on your phone shows up on your laptop live).
-- ------------------------------------------------------------
alter publication supabase_realtime add table public.app_state;

-- ============================================================
-- DONE.
-- Next steps happen in the Supabase dashboard, not SQL:
--
-- 1. Authentication → Providers → make sure "Email" is enabled.
--
-- 2. Authentication → URL Configuration → add the URL you deploy
--    Flightlog to (e.g. https://your-app.vercel.app) under
--    "Redirect URLs". Password-reset links only work for
--    domains on this list.
--
-- 3. (Optional, speeds up testing) Authentication → Providers →
--    Email → toggle OFF "Confirm email" if you don't want to
--    click a confirmation link every time you create a test
--    account. Leave it ON for real use.
-- ============================================================
