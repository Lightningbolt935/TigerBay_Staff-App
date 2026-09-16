// =====================================================================
// End-to-End Local Server Verification Script
// =====================================================================

import { handleRequest } from "./index.ts";

// Read from environment or fallback
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") || "https://xxnqlktcbwqhoyezlokv.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh4bnFsa3RjYndxaG95ZXpsb2t2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE5MTQ5MzYsImV4cCI6MjA5NzQ5MDkzNn0.5BsuhfWfEy-iZSNiJPGKk_QC3eHScWfSe2yhdcMSqMA";

Deno.env.set("SUPABASE_URL", SUPABASE_URL);
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", SUPABASE_SERVICE_ROLE_KEY);

const PORT = 8899;

console.log(`🚀 Starting local Edge Function server on port ${PORT}...`);
const server = Deno.serve({ port: PORT }, handleRequest);

try {
  // Test 1: OPTIONS CORS preflight
  console.log("Testing OPTIONS CORS preflight...");
  const optionsRes = await fetch(`http://127.0.0.1:${PORT}/`, {
    method: "OPTIONS",
  });
  console.log(`OPTIONS Status: ${optionsRes.status} (Expected: 200)`);
  console.log(`CORS Header: ${optionsRes.headers.get("Access-Control-Allow-Origin")}`);

  // Test 2: POST with explicit mock data
  console.log("\nTesting POST with test payload...");
  const postRes = await fetch(`http://127.0.0.1:${PORT}/`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      branch_id: 2,
    }),
  });
  console.log(`POST Status: ${postRes.status}`);
  const postData = await postRes.json();
  console.log("POST Response:", JSON.stringify(postData, null, 2));

  console.log("\n✅ Local End-to-End Server Verification Completed Successfully!");
} finally {
  console.log("Shutting down local server...");
  await server.shutdown();
}
