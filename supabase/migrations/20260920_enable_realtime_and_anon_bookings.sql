-- =====================================================================
-- Migration: Enable Realtime & Staff Access for Bookings
-- File:      20260920_enable_realtime_and_anon_bookings.sql
-- =====================================================================

begin;

-- 1. Grant SELECT to anon role so the TigerBay Staff App can read
--    customer bookings directly from Supabase.
drop policy if exists "bookings_select_anon" on public.bookings;
create policy "bookings_select_anon"
  on public.bookings
  for select
  to anon
  using (true);

-- Also ensure authenticated users can select
drop policy if exists "bookings_select_staff" on public.bookings;
create policy "bookings_select_staff"
  on public.bookings
  for select
  to authenticated
  using (true);

-- 2. Add bookings to supabase_realtime publication so INSERT / UPDATE / DELETE
--    events are pushed over WebSocket to the staff app in real-time.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables 
    where pubname = 'supabase_realtime' 
      and schemaname = 'public' 
      and tablename = 'bookings'
  ) then
    alter publication supabase_realtime add table public.bookings;
  end if;
end $$;

commit;
