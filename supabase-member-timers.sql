-- Per-member study countdown timers
-- Run in Supabase SQL Editor.

create table if not exists public.study_room_member_timers (
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  planned_minutes integer not null default 25 check (planned_minutes between 1 and 240),
  is_running boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

alter table public.study_room_member_timers enable row level security;

drop policy if exists "Members can read own room timer" on public.study_room_member_timers;
create policy "Members can read own room timer"
on public.study_room_member_timers for select to authenticated
using (user_id = auth.uid() and public.is_study_room_member(room_id));

drop policy if exists "Members can create own room timer" on public.study_room_member_timers;
create policy "Members can create own room timer"
on public.study_room_member_timers for insert to authenticated
with check (user_id = auth.uid() and public.is_study_room_member(room_id));

drop policy if exists "Members can update own room timer" on public.study_room_member_timers;
create policy "Members can update own room timer"
on public.study_room_member_timers for update to authenticated
using (user_id = auth.uid() and public.is_study_room_member(room_id))
with check (user_id = auth.uid() and public.is_study_room_member(room_id));

grant select, insert, update on public.study_room_member_timers to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'study_room_member_timers'
  ) then
    alter publication supabase_realtime add table public.study_room_member_timers;
  end if;
exception when undefined_object then
  raise notice 'Enable Realtime for study_room_member_timers in Supabase Dashboard.';
end $$;
