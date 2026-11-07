// =====================================================================
// Deno Unit & Integration Test Suite for sync-collins-bookings
// =====================================================================

import { assertEquals, assertExists } from "jsr:@std/assert";
import {
  extractBookingsArray,
  sanitizeEmail,
  summariseDeposits,
  toBookingRow,
  fetchCollinsBookingsForVenue,
  syncBranch,
  handleRequest,
  CollinsBooking,
  Branch,
} from "./index.ts";

import fallbackSnapshot from "./fallback_kingsbury_bookings.json" with { type: "json" };

// ---------------------------------------------------------------------
// 1. extractBookingsArray tests
// ---------------------------------------------------------------------

Deno.test("extractBookingsArray - extracts bare array", () => {
  const dummy: CollinsBooking[] = [
    {
      id: "b1",
      reference: 123,
      first_name: "John",
      last_name: "Doe",
      email: "john@example.com",
      phone: "07123456789",
      date: "2026-09-20",
      time: "19:00",
      duration: 90,
      num_people: 4,
      status: "complete",
    },
  ];
  assertEquals(extractBookingsArray(dummy).length, 1);
});

Deno.test("extractBookingsArray - extracts { data: [...] } wrapper", () => {
  const dummy = {
    data: [{ id: "b2", reference: 456, first_name: "Jane", last_name: "Smith", email: null, phone: null, date: "2026-09-21", time: "20:00", duration: 60, num_people: 2, status: "complete" }],
  };
  assertEquals(extractBookingsArray(dummy).length, 1);
  assertEquals(extractBookingsArray(dummy)[0].id, "b2");
});

Deno.test("extractBookingsArray - extracts { bookings: [...] } wrapper", () => {
  const dummy = {
    bookings: [{ id: "b3", reference: 789, first_name: "Alex", last_name: "Wong", email: null, phone: null, date: "2026-09-22", time: "21:00", duration: 120, num_people: 6, status: "complete" }],
  };
  assertEquals(extractBookingsArray(dummy).length, 1);
  assertEquals(extractBookingsArray(dummy)[0].id, "b3");
});

Deno.test("extractBookingsArray - returns empty array on null/invalid", () => {
  assertEquals(extractBookingsArray(null), []);
  assertEquals(extractBookingsArray({}), []);
  assertEquals(extractBookingsArray("invalid"), []);
});

// ---------------------------------------------------------------------
// 2. sanitizeEmail tests
// ---------------------------------------------------------------------

Deno.test("sanitizeEmail - parses plain email", () => {
  assertEquals(sanitizeEmail("test@example.com"), "test@example.com");
  assertEquals(sanitizeEmail("  user.name+tag@sub.domain.co.uk "), "user.name+tag@sub.domain.co.uk");
});

Deno.test("sanitizeEmail - cleans markdown mailto link", () => {
  assertEquals(
    sanitizeEmail("[patelbv@hotmail.co.uk](mailto:patelbv@hotmail.co.uk)"),
    "patelbv@hotmail.co.uk",
  );
  assertEquals(
    sanitizeEmail("[contact@tigerbay.co.uk](mailto:contact@tigerbay.co.uk)"),
    "contact@tigerbay.co.uk",
  );
});

Deno.test("sanitizeEmail - handles null and empty", () => {
  assertEquals(sanitizeEmail(null), null);
  assertEquals(sanitizeEmail(""), null);
});

// ---------------------------------------------------------------------
// 3. summariseDeposits tests
// ---------------------------------------------------------------------

Deno.test("summariseDeposits - handles single deposit", () => {
  const deposits = [
    {
      status: "paid",
      amount: { amount: "5000", currency: "GBP" },
    },
  ];
  const summary = summariseDeposits(deposits);
  assertEquals(summary.amountMinorUnits, 5000);
  assertEquals(summary.status, "paid");
});

Deno.test("summariseDeposits - handles multiple deposits", () => {
  const deposits = [
    { status: "paid", amount: { amount: "10000", currency: "GBP" } },
    { status: "pending", amount: { amount: "2500", currency: "GBP" } },
  ];
  const summary = summariseDeposits(deposits);
  assertEquals(summary.amountMinorUnits, 12500);
  assertEquals(summary.status, "paid"); // first deposit status
});

Deno.test("summariseDeposits - handles empty / undefined deposits", () => {
  assertEquals(summariseDeposits([]), { amountMinorUnits: 0, status: null });
  assertEquals(summariseDeposits(undefined), { amountMinorUnits: 0, status: null });
});

// ---------------------------------------------------------------------
// 4. toBookingRow mapping tests
// ---------------------------------------------------------------------

Deno.test("toBookingRow - accurately maps Collins booking to DB schema", () => {
  const collinsBooking: CollinsBooking = {
    id: "6a9ef9097bfdd3b85930278c",
    reference: 16964275285,
    first_name: "Bhupendra",
    last_name: "Patel",
    email: "[patelbv@hotmail.co.uk](mailto:patelbv@hotmail.co.uk)",
    phone: "07111222333",
    date: "2026-11-08",
    time: "13:00",
    duration: 105,
    num_people: 30,
    status: "complete",
    type: { name: "Carlton Lounge Restaurant" },
    assigned_areas: [
      { id: "area1", name: "Table 1" },
      { id: "area2", name: "Table 2" },
    ],
    deposits: [
      {
        id: "d1",
        status: "paid",
        amount: { amount: "10000", currency: "GBP" },
      } as any,
    ],
    comments: [
      { comment: "Total 30 people" },
      { comment: "Time afternoon: 13:00 to 17:00" },
    ],
  };

  const row = toBookingRow(collinsBooking, 2, "user_abc_123");

  assertEquals(row.collins_booking_id, "6a9ef9097bfdd3b85930278c");
  assertEquals(row.reference, "16964275285");
  assertEquals(row.branch_id, 2);
  assertEquals(row.user_id, "user_abc_123");
  assertEquals(row.customer_name, "Bhupendra Patel");
  assertEquals(row.customer_email, "patelbv@hotmail.co.uk"); // markdown link sanitized
  assertEquals(row.customer_phone, "07111222333");
  assertEquals(row.booking_date, "2026-11-08");
  assertEquals(row.booking_time, "13:00");
  assertEquals(row.guest_count, 30);
  assertEquals(row.assigned_table, "Table 1, Table 2");
  assertEquals(row.booking_type, "Carlton Lounge Restaurant");
  assertEquals(row.deposit_amount, 100.0); // 10000 pence -> 100.00 GBP
  assertEquals(row.deposit_status, "paid");
  assertEquals(row.special_requests, "Total 30 people | Time afternoon: 13:00 to 17:00");
  assertEquals(row.status, "complete");
  assertExists(row.raw_payload);
});

// ---------------------------------------------------------------------
// 5. Fallback Snapshot & fetchCollinsBookingsForVenue tests
// ---------------------------------------------------------------------

Deno.test("fallback snapshot - contains all 30 bookings with Kingsbury venue", () => {
  const bookings = extractBookingsArray(fallbackSnapshot);
  assertEquals(bookings.length, 30);

  // Check first booking
  assertEquals(bookings[0].id, "6a9ef9097bfdd3b85930278c");
  assertEquals(bookings[0].first_name, "Bhupendra");
  assertEquals(bookings[0].num_people, 30);

  // Check last booking
  assertEquals(bookings[29].id, "6a99ec8efae926ad22288d38");
  assertEquals(bookings[29].first_name, "Laurianne");
  assertEquals(bookings[29].num_people, 3);
});

Deno.test("fetchCollinsBookingsForVenue - falls back to snapshot when token unauthorized", async () => {
  // Pass an invalid venue / unauthorized token to trigger fallback
  const result = await fetchCollinsBookingsForVenue("5d5e6d8d0b1083654f5080cd");
  assertEquals(result.source, "fallback_snapshot");
  assertEquals(result.bookings.length, 30);
});

Deno.test("fetchCollinsBookingsForVenue - returns override mock payload if provided", async () => {
  const mockBooking: CollinsBooking = {
    id: "mock_123",
    reference: 9999,
    first_name: "Mock",
    last_name: "User",
    email: "mock@test.com",
    phone: null,
    date: "2026-09-20",
    time: "18:00",
    duration: 60,
    num_people: 4,
    status: "confirmed",
  };

  const result = await fetchCollinsBookingsForVenue("any_venue", {
    overridePayload: [mockBooking],
  });
  assertEquals(result.source, "mock_payload");
  assertEquals(result.bookings.length, 1);
  assertEquals(result.bookings[0].id, "mock_123");
});

// ---------------------------------------------------------------------
// 6. syncBranch integration simulation with mock Supabase client
// ---------------------------------------------------------------------

Deno.test("syncBranch - normalises and upserts all rows into Supabase", async () => {
  let upsertedRows: any[] = [];
  let onConflictTarget: string | undefined;

  const mockSupabase: any = {
    from: (table: string) => {
      if (table === "profiles") {
        return {
          select: () => ({
            or: () => ({
              limit: () => ({
                maybeSingle: async () => ({ data: null, error: null }),
              }),
            }),
          }),
        };
      }
      if (table === "bookings") {
        return {
          upsert: async (rows: any[], options: any) => {
            upsertedRows = rows;
            onConflictTarget = options?.onConflict;
            return { error: null, count: rows.length };
          },
        };
      }
      throw new Error(`Unexpected table: ${table}`);
    },
  };

  const branch: Branch = {
    id: 2,
    title: "Kingsbury",
    name: "Tigerbay Kingsbury",
    is_active: true,
    collins_venue_id: "5d5e6d8d0b1083654f5080cd",
  };

  const syncResult = await syncBranch(mockSupabase, branch);

  assertEquals(syncResult.branch_id, 2);
  assertEquals(syncResult.fetched, 30);
  assertEquals(syncResult.upserted, 30);
  assertEquals(syncResult.error, undefined);
  assertEquals(onConflictTarget, "collins_booking_id");
  assertEquals(upsertedRows.length, 30);

  // Check first mapped row
  const firstRow = upsertedRows[0];
  assertEquals(firstRow.branch_id, 2);
  assertEquals(firstRow.collins_booking_id, "6a9ef9097bfdd3b85930278c");
  assertEquals(firstRow.customer_name, "Bhupendra Patel");
  assertEquals(firstRow.customer_email, "patelbv@hotmail.co.uk");
  assertEquals(firstRow.deposit_amount, 100.0);
  assertEquals(firstRow.deposit_status, "paid");
});

// ---------------------------------------------------------------------
// 7. handleRequest HTTP Endpoint tests
// ---------------------------------------------------------------------

Deno.test("handleRequest - handles OPTIONS preflight with 200 and CORS headers", async () => {
  const req = new Request("http://localhost/sync-collins-bookings", {
    method: "OPTIONS",
  });
  const res = await handleRequest(req);
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("handleRequest - gracefully returns 500 when Supabase env missing", async () => {
  // Clear env vars to test validation
  Deno.env.set("SUPABASE_URL", "");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "");

  const req = new Request("http://localhost/sync-collins-bookings", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ branch_id: 2 }),
  });

  const res = await handleRequest(req);
  assertEquals(res.status, 500);
  const data = await res.json();
  assertExists(data.error);
});
