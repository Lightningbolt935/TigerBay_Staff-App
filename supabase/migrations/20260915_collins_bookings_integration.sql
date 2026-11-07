-- =====================================================================
-- Migration: Collins Bookings (DesignMyNight) Integration
-- File:      20260915_collins_bookings_integration.sql
--
-- NON-DESTRUCTIVE: This migration only ALTERs the existing `bookings`
-- table. It does not drop, rename, or replace any existing table,
-- column, or row. All new columns are added as nullable / defaulted
-- so existing rows and existing app code paths keep working.
-- Safe to re-run: every statement is guarded with IF [NOT] EXISTS.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. bookings.user_id -> nullable
--    Collins bookings made on the venue's own web widget / phone / walk-in
--    have no corresponding app user, so this can no longer be NOT NULL.
-- ---------------------------------------------------------------------
alter table public.bookings
  alter column user_id drop not null;

-- ---------------------------------------------------------------------
-- 2. New columns for Collins-sourced bookings
-- ---------------------------------------------------------------------

-- Collins' own booking id (24-char hex string). Unique so an upsert can
-- target it via `onConflict: 'collins_booking_id'`.
alter table public.bookings
  add column if not exists collins_booking_id text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'bookings_collins_booking_id_key'
  ) then
    alter table public.bookings
      add constraint bookings_collins_booking_id_key unique (collins_booking_id);
  end if;
end $$;

-- Human-facing Collins booking reference (kept as text: Collins returns
-- it numeric, but treating it as an opaque reference code is safer than
-- assuming it always fits / stays numeric).
alter table public.bookings
  add column if not exists reference text;

-- Customer contact details as sent by Collins (kept even when we manage
-- to link user_id to an existing profile, since walk-in / non-app guests
-- have no profile row at all).
alter table public.bookings
  add column if not exists customer_name text;

alter table public.bookings
  add column if not exists customer_email text;

alter table public.bookings
  add column if not exists customer_phone text;

-- Table/area Collins assigned the booking to (from `assigned_areas`).
alter table public.bookings
  add column if not exists assigned_table text;

-- Collins booking "type" (e.g. "Carlton Lounge Restaurant").
alter table public.bookings
  add column if not exists booking_type text;

-- Deposit amount normalised to decimal currency units (Collins sends
-- pence/cents as an integer string; the sync function divides by 100
-- before writing here).
alter table public.bookings
  add column if not exists deposit_amount numeric(10,2) default 0.00;

-- Deposit status, e.g. "paid" / "pending" / "refunded".
alter table public.bookings
  add column if not exists deposit_status text;

-- Full raw Collins payload for this booking, for debugging / future
-- fields without further migrations.
alter table public.bookings
  add column if not exists raw_payload jsonb;

-- ---------------------------------------------------------------------
-- 3. Indexes
-- ---------------------------------------------------------------------

-- Composite index for the dashboard's primary query pattern:
-- "bookings for branch X on date Y, ordered by time".
create index if not exists idx_bookings_branch_date_time
  on public.bookings (branch_id, booking_date, booking_time);

-- Speeds up the sync function's profile-matching lookups and any
-- "find this Collins booking" queries (the UNIQUE constraint above
-- already creates a btree index, this is just documented here for
-- clarity — no separate index needed for collins_booking_id).

-- ---------------------------------------------------------------------
-- 4. Row Level Security
-- ---------------------------------------------------------------------
-- Assumptions (adjust to match your actual staff/role model):
--   * `public.profiles` has an `id` matching `auth.uid()`.
--   * There is no dedicated staff/branch-membership table in the schema
--     provided, so staff access below is granted to any authenticated
--     user for now. If/when a `staff_branches` (or similar) table
--     exists, tighten the "staff" policy to join against it instead of
--     granting all authenticated users branch-wide read access.
-- ---------------------------------------------------------------------

alter table public.bookings enable row level security;

-- App users can see their own bookings (their user_id matches auth.uid()).
drop policy if exists "bookings_select_own" on public.bookings;
create policy "bookings_select_own"
  on public.bookings
  for select
  to authenticated
  using (user_id = auth.uid());

-- Staff/authenticated dashboard access: view all bookings for a branch.
-- NOTE: this is intentionally broad because no staff/branch-membership
-- table was supplied. Replace the `true` below with a proper
-- `exists (select 1 from staff_branches sb where sb.user_id = auth.uid()
--           and sb.branch_id = bookings.branch_id)` check once that
-- table exists.
drop policy if exists "bookings_select_staff" on public.bookings;
create policy "bookings_select_staff"
  on public.bookings
  for select
  to authenticated
  using (true);

-- Only the service role (used by the Edge Function) can insert/update
-- Collins-synced rows. Regular authenticated users cannot write directly.
drop policy if exists "bookings_write_service_role" on public.bookings;
create policy "bookings_write_service_role"
  on public.bookings
  for all
  to service_role
  using (true)
  with check (true);

commit;
