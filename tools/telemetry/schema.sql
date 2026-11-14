-- The playtest database (Supabase, free tier): anonymous visits, sessions of players who said yes to
-- sharing play data, and their runs. Run this whole file once in the project's SQL editor; it is safe to
-- run again (everything is "if not exists" or "or replace").
--
-- The game's public key can only call the three functions at the bottom. It cannot read, list, change or
-- delete any row: row level security is on and no policy grants anything. Reading back (tools/telemetry/
-- export.py) uses the project's secret key, kept in the cloud environment's secrets, never in the repo.
--
-- Versioning: rows are never rewritten by a later build. A run row keeps the whole compact record
-- ("record", its own "format" = sim/run_record.gd RECORD_FORMAT) plus summary columns copied out of it
-- for quick queries; "upload_version" is the wrapper's (game/telemetry.gd UPLOAD_VERSION). New summary
-- columns are added with "add column if not exists" and filled from "record".

create table if not exists visits (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  build text,
  screen text,
  language text,
  referrer text,
  seeded boolean
);

create table if not exists sessions (
  session_id uuid primary key,
  player_id uuid not null,
  at timestamptz not null default now(),
  build text,
  version text,
  upload_version int,
  screen text,
  language text
);
create index if not exists sessions_player on sessions (player_id);

create table if not exists runs (
  run_id text primary key,
  player_id uuid not null,
  session_id uuid,
  first_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  uploads int not null default 1,
  upload_version int,
  build text,
  record_format int,
  seed bigint,
  result text,
  round_reached int,
  rounds_to_win int,
  age text,
  traditions jsonb,
  paths jsonb,
  wall_seconds int,
  record jsonb not null
);
create index if not exists runs_player on runs (player_id);
create index if not exists runs_updated on runs (updated_at);

alter table visits enable row level security;
alter table sessions enable row level security;
alter table runs enable row level security;
revoke all on visits, sessions, runs from anon, authenticated;

-- A page load (web/visit.js). No id of any kind.
create or replace function log_visit(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into visits (build, screen, language, referrer, seeded)
  values (left(p->>'build', 64), left(p->>'screen', 16), left(p->>'language', 8),
          left(p->>'referrer', 128), coalesce((p->>'seeded')::boolean, false));
end $$;

-- The game opened for a player who shares play data (game/telemetry.gd start_session).
create or replace function log_session(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into sessions (session_id, player_id, build, version, upload_version, screen, language)
  values ((p->>'session_id')::uuid, (p->>'player_id')::uuid, left(p->>'build', 64), left(p->>'version', 16),
          (p->>'upload_version')::int, left(p->>'screen', 16), left(p->>'language', 8))
  on conflict (session_id) do nothing;
end $$;

-- A run saved (game/telemetry.gd send_run): the first save makes the row, later saves of the same run
-- replace it, and only the player who made it can replace it. Oversized records and floods are refused.
create or replace function save_run(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  rec jsonb := p->'record';
  pid uuid := (p->>'player_id')::uuid;
begin
  if coalesce(p->>'run_id', '') = '' or length(p->>'run_id') > 64 or jsonb_typeof(rec) <> 'object' then
    raise exception 'bad run';
  end if;
  if octet_length(rec::text) > 600000 then
    raise exception 'run too big';
  end if;
  if not exists (select 1 from runs where run_id = p->>'run_id')
     and (select count(*) from runs where player_id = pid and first_at > now() - interval '1 day') >= 100 then
    raise exception 'too many runs today';
  end if;
  insert into runs (run_id, player_id, session_id, upload_version, build, record_format, seed, result,
                    round_reached, rounds_to_win, age, traditions, paths, wall_seconds, record)
  values (p->>'run_id', pid, (p->>'session_id')::uuid, (p->>'upload_version')::int, left(rec->>'build', 64),
          (rec->>'format')::int, (rec->>'seed')::bigint, rec->>'result', (rec->>'round_reached')::int,
          (rec->>'rounds_to_win')::int, rec->>'age', rec->'traditions', rec->'paths',
          (rec->>'wall_seconds')::int, rec)
  on conflict (run_id) do update set
    session_id = excluded.session_id, updated_at = now(), uploads = runs.uploads + 1,
    upload_version = excluded.upload_version, build = excluded.build, record_format = excluded.record_format,
    result = excluded.result, round_reached = excluded.round_reached, age = excluded.age,
    traditions = excluded.traditions, paths = excluded.paths, wall_seconds = excluded.wall_seconds,
    record = excluded.record
  where runs.player_id = excluded.player_id;
end $$;

revoke all on function log_visit(jsonb), log_session(jsonb), save_run(jsonb) from public;
grant execute on function log_visit(jsonb), log_session(jsonb), save_run(jsonb) to anon;

-- A player's data, deleted on request (run by hand in the SQL editor with their id from Settings):
--   delete from runs where player_id = '<id>'; delete from sessions where player_id = '<id>';
