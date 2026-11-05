-- Store each member's public display name for the study-room member list.
-- Run once in Supabase SQL Editor.

alter table public.study_room_members
  add column if not exists display_name text;

drop policy if exists "Members can update their own stats privacy" on public.study_room_members;
create policy "Members can update their own stats privacy"
on public.study_room_members for update to authenticated
using (user_id = auth.uid() and public.is_study_room_member(room_id))
with check (user_id = auth.uid() and public.is_study_room_member(room_id));

grant update (display_name) on public.study_room_members to authenticated;
