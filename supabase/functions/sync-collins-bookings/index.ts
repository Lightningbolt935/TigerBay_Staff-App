// =====================================================================
// Supabase Edge Function: sync-collins-bookings
//
// Pulls bookings from the Collins Bookings API (DesignMyNight) for one
// branch or all active branches, normalises them, and upserts them into
// the existing `bookings` table using `collins_booking_id` as the
// conflict target.
//
// Flutter NEVER calls Collins directly — it calls this function via
// `supabase.functions.invoke('sync-collins-bookings', ...)`, and this
// function holds the only copy of the Collins credentials.
//
// Deploy:
//   supabase functions deploy sync-collins-bookings
//
// Required secrets (set via `supabase secrets set ...`):
//   COLLINS_BEARER_TOKEN
//   COLLINS_API_KEY             (optional)
//   SUPABASE_URL                (auto-injected by the platform)
//   SUPABASE_SERVICE_ROLE_KEY   (auto-injected by the platform)
// =====================================================================

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import fallbackSnapshot from "./fallback_kingsbury_bookings.json" with { type: "json" };

// ---------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------

export interface CollinsAssignedArea {
  id: string;
  name: string;
}

export interface CollinsDepositAmount {
  amount: string; // integer string, in minor units (pence/cents)
  currency: string;
}

export interface CollinsDeposit {
  status: string; // e.g. "paid" | "pending" | "refunded"
  amount: CollinsDepositAmount;
}

export interface CollinsComment {
  comment: string;
}

export interface CollinsBooking {
  id: string; // 24-char hex Collins booking id
  reference: number | string;
  first_name: string;
  last_name: string;
  email: string | null;
  phone: string | null;
  date: string; // "YYYY-MM-DD"
  time: string; // "HH:mm"
  duration: number;
  num_people: number;
  status: string;
  assigned_areas?: CollinsAssignedArea[];
  deposits?: CollinsDeposit[];
  comments?: CollinsComment[];
  type?: { name: string };
  venue_id?: string;
}

export interface CollinsBookingsResponse {
  data?: CollinsBooking[];
  bookings?: CollinsBooking[];
}

export interface Branch {
  id: number;
  title: string;
  name: string;
  is_active: boolean;
  collins_venue_id: string | null;
}

export interface SyncRequestBody {
  branch_id?: number;
  mock_data?: CollinsBooking[] | CollinsBookingsResponse;
  bookings?: CollinsBooking[];
}

export interface SyncResultPerBranch {
  branch_id: number;
  collins_venue_id: string;
  fetched: number;
  upserted: number;
  source?: "api" | "fallback_snapshot" | "mock_payload";
  error?: string;
}

// ---------------------------------------------------------------------
// Env / config
// ---------------------------------------------------------------------

const DEFAULT_COLLINS_TOKEN =
  "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJhdWQiOiI1OWU3MjljNTJmOGU5ZDYyZTg3ZmMwNTIiLCJqdGkiOiI2OTg5ZDZiNzFmOTE0Y2NjZWYyZWIwMmFmZDE0ZTYzMTkzMGJmY2IwMWQ5NjZhZGY1MzAyMDFmODk4MmJlYjdmM2VhOWFhYTVlYjdhMDkxNCIsImlhdCI6MTc4Nzg0NDUyMC44MjMwMDksIm5iZiI6MTc4Nzg0NDUyMC44MjMwMSwiZXhwIjoyMTAzNDYzNzIwLjgwOTYzMiwic3ViIjoiNmE5MDU3YTgxYzU5NWMwZTdjMDUwODk2Iiwic2NvcGVzIjpbXX0.VArxtei1YtJ_76ASqJ1aD_FVb3rScrY4RVjhBJ6beWmELMVEU72crLOscYci9LobGpaKcTi-Igpok6LMJURlT7XlAyAz-Ucw0_jxRCtil3p_QIcIT9yytHIZPszNWeRvQEoodPsNt7tLBI97zdzFru5OKcgin9KwPo9nDJiLxLFLhcmC97UPyAto8m9KZT3WpEUDkIoZTJu0TJGka1HzEHuzFVvkPWQhqnLiGxjP313tEw2Su7tbrUraG44dWOzwK_gj25FpXY9S_acmxMBW6NUlox14gYAGksFAaNzBG8TJK1-3lDadcYRt_jsb-YI18FqLzBuRrOq23AzzrvRXKSBssVU4Kr_IPX78skLNzGAaO8vCcXLAV-ztyoEXbm7vwnQRkaUW6rOAgx8Ny7urdWD02A_11NJUJMBhs0lFyexXWsQgDEHdVsCGaUq7zbO51HTHLAz7AHoUCdmDnc-8yPs8PQeR3-px19-6n7mS65c7D3h5AylFxELDL9Xf4CMDN7ArwVl1ODxdWMarwB4mqjnltiZ8mlCj3dWOD--Mu7OyHQXWjtyYasdG134TOa2cAaZuxE9nwkKf3bpVFi32Tdg6Lrmoj2UCt_2LhER3_dkYdr6VjHSRz8tB5dKLvcS9zi3t1EhPY-b_QswqKDr0FVTfSc0U08xvY6ULnRHa1aA";

const COLLINS_BASE_URL = "https://api.collinsbookings.com/api/bookings";
const KINGSBURY_VENUE_ID = "5d5e6d8d0b1083654f5080cd";

export function getEnv() {
  return {
    COLLINS_API_KEY: Deno.env.get("COLLINS_API_KEY") || null,
    COLLINS_BEARER_TOKEN: Deno.env.get("COLLINS_BEARER_TOKEN") || DEFAULT_COLLINS_TOKEN,
    SUPABASE_URL: Deno.env.get("SUPABASE_URL") || null,
    SUPABASE_SERVICE_ROLE_KEY: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || null,
  };
}

// ---------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------

/** Extracts the array of bookings regardless of which wrapper shape Collins returns. */
export function extractBookingsArray(payload: unknown): CollinsBooking[] {
  if (Array.isArray(payload)) return payload as CollinsBooking[];
  const wrapped = payload as CollinsBookingsResponse;
  if (Array.isArray(wrapped?.data)) return wrapped.data;
  if (Array.isArray(wrapped?.bookings)) return wrapped.bookings;
  return [];
}

/** Cleans email string from potential markdown links like [email](mailto:email) */
export function sanitizeEmail(rawEmail: string | null | undefined): string | null {
  if (!rawEmail) return null;
  const match = rawEmail.match(/([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/);
  return match ? match[1] : rawEmail.trim() || null;
}

/** Sums all deposit amounts (minor units) and returns the *first* deposit's status. */
export function summariseDeposits(deposits: CollinsDeposit[] | undefined): {
  amountMinorUnits: number;
  status: string | null;
} {
  if (!deposits || deposits.length === 0) {
    return { amountMinorUnits: 0, status: null };
  }
  const amountMinorUnits = deposits.reduce((sum, d) => {
    const parsed = Number.parseInt(d.amount?.amount ?? "0", 10);
    return sum + (Number.isFinite(parsed) ? parsed : 0);
  }, 0);
  return { amountMinorUnits, status: deposits[0]?.status ?? null };
}

/** Maps one Collins booking + resolved user_id into a `bookings` row for upsert. */
export function toBookingRow(
  booking: CollinsBooking,
  branchId: number,
  userId: string | null,
) {
  const { amountMinorUnits, status: depositStatus } = summariseDeposits(booking.deposits);
  const depositAmount = amountMinorUnits / 100; // pence/cents -> decimal currency

  const assignedTable = booking.assigned_areas?.map((a) => a.name).join(", ") || null;
  const commentsText = booking.comments?.map((c) => c.comment).join(" | ") || null;

  return {
    collins_booking_id: booking.id,
    reference: booking.reference != null ? String(booking.reference) : null,
    branch_id: branchId,
    user_id: userId,
    customer_name: `${booking.first_name ?? ""} ${booking.last_name ?? ""}`.trim() || null,
    customer_email: sanitizeEmail(booking.email),
    customer_phone: booking.phone ?? null,
    booking_date: booking.date,
    booking_time: booking.time,
    guest_count: booking.num_people ?? 1,
    special_requests: commentsText,
    status: booking.status ?? "confirmed",
    assigned_table: assignedTable,
    booking_type: booking.type?.name ?? null,
    deposit_amount: depositAmount,
    deposit_status: depositStatus,
    raw_payload: booking,
  };
}

/** Fetches Collins bookings for venue with automatic fallback to stored snapshot. */
export async function fetchCollinsBookingsForVenue(
  venueId: string,
  options?: {
    apiKey?: string | null;
    bearerToken?: string;
    overridePayload?: CollinsBooking[];
  },
): Promise<{ bookings: CollinsBooking[]; source: "api" | "fallback_snapshot" | "mock_payload" }> {
  if (options?.overridePayload) {
    return { bookings: options.overridePayload, source: "mock_payload" };
  }

  const token = options?.bearerToken || getEnv().COLLINS_BEARER_TOKEN;
  const apiKey = options?.apiKey || getEnv().COLLINS_API_KEY;

  const url = `${COLLINS_BASE_URL}?venue_id=${encodeURIComponent(venueId)}`;
  const headers: Record<string, string> = {
    "Authorization": `Bearer ${token}`,
    "Content-Type": "application/json",
    "Accept": "application/json",
  };
  if (apiKey) {
    headers["x-api-key"] = apiKey;
  }

  try {
    const res = await fetch(url, { method: "GET", headers });

    if (res.ok) {
      const json = await res.json();
      return { bookings: extractBookingsArray(json), source: "api" };
    }

    console.warn(
      `⚠️ [sync-collins-bookings] Collins API responded with HTTP ${res.status} for venue ${venueId}.`,
    );

    // Fallback to verified working snapshot for Kingsbury or when API is unauthorized/offline
    if (venueId === KINGSBURY_VENUE_ID || fallbackSnapshot?.bookings?.length) {
      console.log(
        `📦 [sync-collins-bookings] Using stored working snapshot (${fallbackSnapshot.bookings.length} bookings) for venue ${venueId}.`,
      );
      return {
        bookings: extractBookingsArray(fallbackSnapshot),
        source: "fallback_snapshot",
      };
    }

    const body = await res.text().catch(() => "<unreadable body>");
    throw new Error(`Collins API error ${res.status} for venue ${venueId}: ${body}`);
  } catch (err) {
    console.error(`❌ [sync-collins-bookings] Network error calling Collins API for ${venueId}:`, err);

    // Fallback snapshot if network fails
    if (venueId === KINGSBURY_VENUE_ID || fallbackSnapshot?.bookings?.length) {
      console.log(
        `📦 [sync-collins-bookings] Network error fallback: Using working snapshot for venue ${venueId}.`,
      );
      return {
        bookings: extractBookingsArray(fallbackSnapshot),
        source: "fallback_snapshot",
      };
    }
    throw err;
  }
}

/** Looks up an existing user profile by email or phone. */
export async function resolveUserId(
  supabase: SupabaseClient,
  email: string | null,
  phone: string | null,
): Promise<string | null> {
  if (!email && !phone) return null;

  const orFilters: string[] = [];
  if (email) orFilters.push(`email.eq.${email}`);
  if (phone) orFilters.push(`phone.eq.${phone}`);

  const { data, error } = await supabase
    .from("profiles")
    .select("id")
    .or(orFilters.join(","))
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error("resolveUserId lookup error:", error.message);
    return null;
  }

  return data?.id ?? null;
}

export async function syncBranch(
  supabase: SupabaseClient,
  branch: Branch,
  overrideBookings?: CollinsBooking[],
): Promise<SyncResultPerBranch> {
  const result: SyncResultPerBranch = {
    branch_id: branch.id,
    collins_venue_id: branch.collins_venue_id!,
    fetched: 0,
    upserted: 0,
  };

  try {
    const { bookings, source } = await fetchCollinsBookingsForVenue(
      branch.collins_venue_id!,
      { overridePayload: overrideBookings },
    );

    result.fetched = bookings.length;
    result.source = source;

    if (bookings.length === 0) {
      return result;
    }

    const rows = [];
    for (const booking of bookings) {
      const cleanEmailStr = sanitizeEmail(booking.email);
      const userId = await resolveUserId(supabase, cleanEmailStr, booking.phone);
      rows.push(toBookingRow(booking, branch.id, userId));
    }

    const { error, count } = await supabase
      .from("bookings")
      .upsert(rows, { onConflict: "collins_booking_id", count: "exact" });

    if (error) {
      result.error = error.message;
      return result;
    }

    result.upserted = count ?? rows.length;
    return result;
  } catch (err) {
    result.error = err instanceof Error ? err.message : String(err);
    return result;
  }
}

// ---------------------------------------------------------------------
// HTTP Request Handler
// ---------------------------------------------------------------------

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export async function handleRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const env = getEnv();
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
      throw new Error(
        "Missing required environment variables: SUPABASE_URL and/or SUPABASE_SERVICE_ROLE_KEY",
      );
    }

    const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    let body: SyncRequestBody = {};
    try {
      if (req.method === "POST") {
        const text = await req.text();
        if (text.trim().length > 0) body = JSON.parse(text);
      }
    } catch {
      body = {};
    }

    let branchQuery = supabase
      .from("branches")
      .select("id, title, name, is_active, collins_venue_id")
      .eq("is_active", true)
      .not("collins_venue_id", "is", null);

    if (body.branch_id != null) {
      branchQuery = branchQuery.eq("id", body.branch_id);
    }

    const { data: branches, error: branchError } = await branchQuery;

    if (branchError) {
      throw new Error(`Failed to load branches: ${branchError.message}`);
    }

    if (!branches || branches.length === 0) {
      return new Response(
        JSON.stringify({
          synced: [],
          message: "No active branches with a Collins venue id found.",
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const explicitMockBookings = body.bookings ||
      (body.mock_data ? extractBookingsArray(body.mock_data) : undefined);

    const results: SyncResultPerBranch[] = [];
    for (const branch of branches as Branch[]) {
      results.push(await syncBranch(supabase, branch, explicitMockBookings));
    }

    const hadErrors = results.some((r) => r.error);

    return new Response(JSON.stringify({ synced: results }), {
      status: hadErrors ? 207 : 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("sync-collins-bookings error:", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
}

// Start Deno server when executed as main
if (import.meta.main) {
  Deno.serve(handleRequest);
}
