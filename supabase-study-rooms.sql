-- Study Planner: group study rooms
-- Run this entire script once in Supabase SQL Editor.

create table if not exists public.study_rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  invite_code text not null unique,
  owner_id uuid not null references auth.users(id) on delete cascade,
  goal_hours integer not null default 30 check (goal_hours between 1 and 500),
  visibility text not null default 'private' check (visibility in ('private','invite')),
  created_at timestamptz not null default now()
);

create table if not exists public.study_room_members (
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create table if not exists public.study_room_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.study_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  sender_name text not null default 'کاربر' check (char_length(sender_name) between 1 and 40),
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists study_room_messages_room_created_idx
  on public.study_room_messages (room_id, created_at);

create index if not exists study_room_members_user_idx
  on public.study_room_members (user_id);

alter table public.study_rooms enable row level security;
alter table public.study_room_members enable row level security;
alter table public.study_room_messages enable row level security;

-- Security-definer helper avoids recursive RLS policies on memberships.
create or replace function public.is_study_room_member(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.study_room_members m
    where m.room_id = p_room_id and m.user_id = auth.uid()
  );
$$;

revoke all on function public.is_study_room_member(uuid) from public;
grant execute on function public.is_study_room_member(uuid) to authenticated;

drop policy if exists "Members can read their rooms" on public.study_rooms;
create policy "Members can read their rooms"
on public.study_rooms for select to authenticated
using (owner_id = auth.uid() or public.is_study_room_member(id));

drop policy if exists "Users can create rooms as owner" on public.study_rooms;
create policy "Users can create rooms as owner"
on public.study_rooms for insert to authenticated
with check (owner_id = auth.uid());

drop policy if exists "Owners can update their rooms" on public.study_rooms;
create policy "Owners can update their rooms"
on public.study_rooms for update to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

drop policy if exists "Owners can delete their rooms" on public.study_rooms;
create policy "Owners can delete their rooms"
on public.study_rooms for delete to authenticated
using (owner_id = auth.uid());

drop policy if exists "Members can read room memberships" on public.study_room_members;
create policy "Members can read room memberships"
on public.study_room_members for select to authenticated
using (public.is_study_room_member(room_id));

create or replace function public.is_study_room_owner(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.study_rooms r
    where r.id = p_room_id and r.owner_id = auth.uid()
  );
$$;

revoke all on function public.is_study_room_owner(uuid) from public;
grant execute on function public.is_study_room_owner(uuid) to authenticated;

drop policy if exists "Room owners can add themselves" on public.study_room_members;
create policy "Room owners can add themselves"
on public.study_room_members for insert to authenticated
with check (
  user_id = auth.uid()
  and role = 'owner'
  and public.is_study_room_owner(room_id)
);

drop policy if exists "Members can leave or owners can remove members" on public.study_room_members;
create policy "Members can leave or owners can remove members"
on public.study_room_members for delete to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1 from public.study_rooms r
    where r.id = room_id and r.owner_id = auth.uid()
  )
);

drop policy if exists "Members can read room messages" on public.study_room_messages;
create policy "Members can read room messages"
on public.study_room_messages for select to authenticated
using (public.is_study_room_member(room_id));

drop policy if exists "Members can send their own messages" on public.study_room_messages;
create policy "Members can send their own messages"
on public.study_room_messages for insert to authenticated
with check (
  user_id = auth.uid()
  and public.is_study_room_member(room_id)
  and char_length(body) between 1 and 1000
  and char_length(sender_name) between 1 and 40
);

grant select, insert, update, delete on public.study_rooms to authenticated;
grant select, insert, delete on public.study_room_members to authenticated;
grant select, insert on public.study_room_messages to authenticated;

-- Joining by invite code is performed through this function so invite codes
-- are not exposed through a public room listing.
create or replace function public.join_study_room(p_code text)
returns table (room_id uuid, room_name text, goal_hours integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_room public.study_rooms%rowtype;
begin
  if auth.uid() is null then
    raise exception 'برای پیوستن ابتدا وارد حساب کاربری شو.';
  end if;

  select * into v_room
  from public.study_rooms r
  where upper(r.invite_code) = upper(trim(p_code))
  limit 1;

  if not found then
    raise exception 'کد دعوت معتبر نیست.';
  end if;

  insert into public.study_room_members (room_id, user_id, role)
  values (v_room.id, auth.uid(), case when v_room.owner_id = auth.uid() then 'owner' else 'member' end)
  on conflict (room_id, user_id) do nothing;

  return query select v_room.id, v_room.name, v_room.goal_hours;
end;
$$;

revoke all on function public.join_study_room(text) from public;
grant execute on function public.join_study_room(text) to authenticated;

-- Enable Realtime for room messages (safe to run more than once).
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'study_room_messages'
  ) then
    alter publication supabase_realtime add table public.study_room_messages;
  end if;
exception when undefined_object then
  raise notice 'supabase_realtime publication was not found; enable Realtime for study_room_messages in the Dashboard.';
end $$;
