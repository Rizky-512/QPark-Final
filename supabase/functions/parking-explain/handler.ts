type Environment = { get(name: string): string | undefined };
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (status: number, body: unknown) => Response.json(body, { status, headers: cors });

// Only numeric model output is accepted. Never accept a free-form prompt or a key.
export function createHandler(env: Environment, request: typeof fetch = fetch) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") return new Response(null, { headers: cors });
    if (req.method !== "POST") return reply(405, { error: "Gunakan POST." });
    try {
      const raw = await req.text();
      if (raw.length > 4096) return reply(413, { error: "Permintaan terlalu besar." });
      let body;
      try { body = JSON.parse(raw); } catch { return reply(400, { error: "Data tidak valid." }); }
      if (!body || typeof body.token !== "string" || body.token.length > 256 || !body.token) {
        return reply(401, { error: "Silakan login sebagai admin." });
      }
      const f = body.forecast;
      const finite = (v: unknown) => typeof v === "number" && Number.isFinite(v);
      if (!f || !finite(f.capacity) || f.capacity < 1 || f.capacity > 1000000 ||
          !finite(f.current) || f.current < 0 || f.current > 1000000 ||
          !finite(f.target_time) || Math.abs(f.target_time - Date.now()/1000 - 1800) > 600 ||
          (f.predicted !== null && (!finite(f.predicted) || f.predicted < 0 || f.predicted > f.capacity)) ||
          (f.probability !== null && (!finite(f.probability) || f.probability < 0 || f.probability > 1))) {
        return reply(400, { error: "Muat ulang prediksi sebelum meminta penjelasan." });
      }
      // QPark admin uses its own opaque session token, not Supabase Auth JWT.
      const url = env.get("SUPABASE_URL"), service = env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (!url || !service) return reply(503, { error: "Konfigurasi backend belum lengkap." });
      const auth = await request(`${url}/rest/v1/rpc/qpark_ai_claim`, {
        method: "POST", headers: { "Content-Type": "application/json", apikey: service, Authorization: `Bearer ${service}` },
        body: JSON.stringify({ p_token: body.token }), signal: AbortSignal.timeout(8000),
      });
      if (!auth.ok) {
        const error = await auth.json().catch(() => ({}));
        let status = 403;
        try { status = JSON.parse(error.message).status === 429 ? 429 : 403; } catch { /* safe response */ }
        return reply(status, { error: status === 429 ? "Tunggu satu menit sebelum mencoba lagi." : "Sesi admin tidak valid atau migrasi AI belum terpasang." });
      }
      const settings = await auth.json();
      if (settings.capacity !== f.capacity) return reply(409, { error: "Kapasitas berubah. Muat ulang analisis." });
      const key = env.get("GEMINI_API_KEY"), model = env.get("GEMINI_MODEL");
      if (!key || !model) return reply(503, { error: "Gemini belum diaktifkan. Pengelola perlu mengisi GEMINI_API_KEY dan GEMINI_MODEL di Secrets Supabase." });
      if (!/^[a-zA-Z0-9._-]+$/.test(model)) return reply(503, { error: "Nama model Gemini tidak valid." });
      const facts = {
        kendaraan_sekarang: f.current, kapasitas: f.capacity,
        perkiraan_kendaraan_30_menit: f.predicted === null ? null : Math.round(f.predicted),
        peluang_hampir_penuh_persen: f.probability === null ? null : Math.round(f.probability*100),
        batas_hampir_penuh: Math.ceil(f.capacity*.8),
      };
      const response = await request(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
        method: "POST", headers: { "Content-Type": "application/json", "x-goog-api-key": key },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: "Jelaskan hasil supervised learning parkir ini dalam bahasa Indonesia sederhana, maksimal 3 kalimat. Angka berasal dari regresi linear dan logistik aplikasi. Jangan menghitung prediksi baru, mengubah angka, atau mengklaim kepastian/akurasi. Null berarti model belum layak, jangan isi angka. Peluang bukan persentase tempat terisi. Akhiri dengan saran ringan untuk petugas. Tanpa markdown." }] },
          contents: [{ role: "user", parts: [{ text: JSON.stringify(facts) }] }],
          generationConfig: { temperature: .2, maxOutputTokens: 512 },
        }), signal: AbortSignal.timeout(20000),
      });
      if (!response.ok) return reply(502, { error: "Gemini belum dapat merespons. Periksa API key, akses model, dan kuota di Google AI Studio." });
      const generated = await response.json();
      const text = generated.candidates?.[0]?.content?.parts?.filter((p: { text?: string; thought?: boolean }) => !p.thought && typeof p.text === "string").map((p: { text: string }) => p.text).join("").trim();
      if (!text) return reply(502, { error: "Gemini tidak mengembalikan penjelasan. Coba lagi nanti." });
      return reply(200, { explanation: text.slice(0, 2000) });
    } catch {
      return reply(503, { error: "Penjelasan AI sedang tidak tersedia. Prediksi tetap dapat digunakan." });
    }
  };
}
