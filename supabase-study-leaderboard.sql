-- Study Planner: unique public usernames + study-time leaderboard
-- Run this entire script in Supabase SQL Editor.

create table if not exists public.user_public_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_public_profiles_username_format
    check (username ~ '^[a-z0-9_]{3,20}$')
);

alter table public.user_public_profiles enable row level security;
revoke all on public.user_public_profiles from anon, authenticated;

create or replace function public.set_my_public_username(p_username text)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_username text := lower(btrim(coalesce(p_username, '')));
begin
  if v_user_id is null then
    raise exception 'authentication required';
  end if;

  if v_username !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'username must be 3-20 lowercase letters, numbers, or underscores';
  end if;

  insert into public.user_public_profiles (user_id, username, updated_at)
  values (v_user_id, v_username, now())
  on conflict (user_id)
  do update set username = excluded.username, updated_at = now();

  return v_username;
exception
  when unique_violation then
    raise exception 'username already taken';
end;
$$;

revoke all on function public.set_my_public_username(text) from public;
grant execute on function public.set_my_public_username(text) to authenticated;

drop function if exists public.get_public_study_leaderboard();

create function public.get_public_study_leaderboard()
returns table (
  display_name text,
  username text,
  compare_name text,
  total_hours numeric,
  session_count bigint
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    coalesce(
      nullif(left(btrim(p.data->'profile'->>'name'), 40), ''),
      'کاربر'
    ) as display_name,
    coalesce(u.username, 'تنظیم‌نشده') as username,
    nullif(left(btrim(p.data->'profile'->>'compareName'), 24), '') as compare_name,
    coalesce(sum(
      case
        when coalesce(entry.value->>'hours', '') ~ '^[0-9]+([.][0-9]+)?$'
          then (entry.value->>'hours')::numeric
        else 0::numeric
      end
    ), 0::numeric) as total_hours,
    count(*) filter (
      where coalesce(entry.value->>'hours', '') ~ '^[0-9]+([.][0-9]+)?$'
        and (entry.value->>'hours')::numeric > 0
    ) as session_count
  from public.user_planner_data as p
  left join public.user_public_profiles as u on u.user_id = p.user_id
  left join lateral jsonb_array_elements(
    case
      when jsonb_typeof(p.data->'study') = 'array' then p.data->'study'
      else '[]'::jsonb
    end
  ) as entry(value) on true
  where coalesce(p.data->'profile'->>'compareOptIn', 'true') <> 'false'
  group by p.user_id, p.data->'profile'->>'name',
           p.data->'profile'->>'compareName', u.username
  order by total_hours desc, display_name asc;
$$;

revoke all on function public.get_public_study_leaderboard() from public;
grant execute on function public.get_public_study_leaderboard() to authenticated;
