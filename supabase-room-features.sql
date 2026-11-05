-- Group study room features migration
-- Run once in Supabase SQL Editor after supabase-study-rooms.sql.

alter table public.study_room_members
  add column if not exists show_stats boolean not null default true;

drop policy if exists "Members can update their own stats privacy" on public.study_room_members;
create policy "Members can update their own stats privacy"
on public.study_room_members for update to authenticated
using (user_id = auth.uid() and public.is_study_room_member(room_id))
with check (user_id = auth.uid() and public.is_study_room_member(room_id));

create table if not exists public.study_room_timer (
  room_id uuid primary key references public.study_rooms(id) on delete cascade,
  started_by uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  planned_minutes integer not null default 25 check (planned_minutes between 1 and 240),
  is_running boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.study_room_study_logs (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  minutes integer not null check (minutes between 1 and 1440),
  logged_at timestamptz not null default now()
);

create index if not exists study_room_study_logs_room_date_idx
  on public.study_room_study_logs (room_id, logged_at desc);

create table if not exists public.study_room_challenges (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 80),
  target_hours integer not null check (target_hours between 1 and 500),
  week_start date not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (room_id, week_start)
);

alter table public.study_room_timer enable row level security;
alter table public.study_room_study_logs enable row level security;
alter table public.study_room_challenges enable row level security;

drop policy if exists "Room members can read shared timer" on public.study_room_timer;
create policy "Room members can read shared timer"
on public.study_room_timer for select to authenticated
using (public.is_study_room_member(room_id));

drop policy if exists "Room members can start shared timer" on public.study_room_timer;
create policy "Room members can start shared timer"
on public.study_room_timer for insert to authenticated
with check (public.is_study_room_member(room_id) and started_by = auth.uid());

drop policy if exists "Room members can update shared timer" on public.study_room_timer;
create policy "Room members can update shared timer"
on public.study_room_timer for update to authenticated
using (public.is_study_room_member(room_id))
with check (public.is_study_room_member(room_id));

drop policy if exists "Members can read visible study stats" on public.study_room_study_logs;
create policy "Members can read visible study stats"
on public.study_room_study_logs for select to authenticated
using (
  user_id = auth.uid()
  or (
    public.is_study_room_member(room_id)
    and exists (
      select 1 from public.study_room_members m
      where m.room_id = study_room_study_logs.room_id
        and m.user_id = study_room_study_logs.user_id
        and m.show_stats = true
    )
  )
);

drop policy if exists "Members can add their own study logs" on public.study_room_study_logs;
create policy "Members can add their own study logs"
on public.study_room_study_logs for insert to authenticated
with check (
  user_id = auth.uid()
  and public.is_study_room_member(room_id)
);

drop policy if exists "Members can read room challenges" on public.study_room_challenges;
create policy "Members can read room challenges"
on public.study_room_challenges for select to authenticated
using (public.is_study_room_member(room_id));

drop policy if exists "Members can create room challenges" on public.study_room_challenges;
create policy "Members can create room challenges"
on public.study_room_challenges for insert to authenticated
with check (public.is_study_room_member(room_id) and created_by = auth.uid());

grant select, insert, update on public.study_room_timer to authenticated;
grant select, insert on public.study_room_study_logs to authenticated;
grant select, insert on public.study_room_challenges to authenticated;
grant update (show_stats) on public.study_room_members to authenticated;

-- Enable Realtime for shared timer, study logs and weekly challenges.
do $$
declare
  t text;
begin
  foreach t in array array['study_room_timer','study_room_study_logs','study_room_challenges'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
exception when undefined_object then
  raise notice 'supabase_realtime publication was not found. Enable Realtime for the new room tables in Supabase Dashboard.';
end $$;
