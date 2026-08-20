import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const body = await req.json();
    console.log("🚀 Received trigger payload:", JSON.stringify(body));

    const record = body.record || body;
    const email = record?.email;
    const otp = record?.otp;

    if (!email || !otp) {
      console.error("❌ Missing email or otp in request body");
      return new Response(
        JSON.stringify({ error: "Missing email or otp in payload" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    console.log(`📧 Dispatching OTP ${otp} to ${email}...`);

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: "Tigerbay Staff <onboarding@resend.dev>",
        to: [email],
        subject: `${otp} is your Tigerbay Staff Verification Code`,
        html: `
          <div style="font-family: 'Helvetica Neue', Helvetica, Arial, sans-serif; padding: 30px; background-color: #0f0f11; color: #f3f3f3;">
            <div style="max-width: 480px; margin: 0 auto; background: #1a1a1e; padding: 32px; border-radius: 12px; border: 1px solid #2e2e36; text-align: center;">
              <h2 style="color: #d4af37; font-size: 24px; margin-top: 0; letter-spacing: 1px;">TIGERBAY</h2>
              <p style="color: #a1a1aa; font-size: 14px; margin-bottom: 24px;">Your Staff Access Verification Code</p>
              
              <div style="font-size: 36px; font-weight: 800; letter-spacing: 8px; color: #ffffff; background: #000000; padding: 18px; border-radius: 8px; border: 1px solid #d4af37; margin: 20px 0;">
                ${otp}
              </div>
              
              <p style="font-size: 12px; color: #71717a; margin-top: 24px;">This code expires in 10 minutes. If you did not request this login, please ignore this email.</p>
            </div>
          </div>
        `,
      }),
    });

    const resData = await res.json();
    console.log("✅ Resend API Response:", resData);

    return new Response(JSON.stringify(resData), {
      status: res.status,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err: any) {
    console.error("❌ Exception in send-otp-email:", err.message);
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
