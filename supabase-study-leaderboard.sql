-- Study Planner: privacy-respecting public study-time leaderboard
-- Run this script once in Supabase SQL Editor after the user_planner_data table exists.
-- Users appear only after explicitly enabling profile.compareOptIn in their planner profile.

create or replace function public.get_public_study_leaderboard()
returns table (
  display_name text,
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
      nullif(left(btrim(p.data->'profile'->>'compareName'), 24), ''),
      'کاربر'
    ) as display_name,
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
  left join lateral jsonb_array_elements(
    case
      when jsonb_typeof(p.data->'study') = 'array' then p.data->'study'
      else '[]'::jsonb
    end
  ) as entry(value) on true
  where p.data->'profile'->>'compareOptIn' = 'true'
  group by p.user_id, p.data->'profile'->>'compareName'
  order by total_hours desc, display_name asc;
$$;

revoke all on function public.get_public_study_leaderboard() from public;
grant execute on function public.get_public_study_leaderboard() to authenticated;
