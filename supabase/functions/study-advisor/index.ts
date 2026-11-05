import { createClient } from "npm:@supabase/supabase-js@2";

const PROJECT_URL = Deno.env.get("SUPABASE_URL") ?? "";
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
const MODEL = Deno.env.get("OPENAI_MODEL") ?? "gpt-6-luna";
const PUBLISHABLE_KEYS = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
const PUBLISHABLE_KEY = PUBLISHABLE_KEYS
  ? (JSON.parse(PUBLISHABLE_KEYS).default ?? Object.values(JSON.parse(PUBLISHABLE_KEYS))[0])
  : (Deno.env.get("SUPABASE_ANON_KEY") ?? "");

const allowedOrigins = new Set([
  "https://tara30942.github.io",
  "http://localhost:3000",
  "http://127.0.0.1:5500",
]);

function corsHeaders(origin: string | null) {
  const allowed = origin && allowedOrigins.has(origin) ? origin : "https://tara30942.github.io";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
    "Content-Type": "application/json; charset=utf-8",
  };
}

function json(data: unknown, status: number, headers: Record<string, string>) {
  return new Response(JSON.stringify(data), { status, headers });
}

const instructions = `
تو «مشاور برنامه‌ریزی تحصیلی» داخل یک پلنر فارسی هستی.
- همیشه فارسی روان، محترمانه، روشن و کاربردی پاسخ بده؛ لحن همراه و واقع‌بینانه داشته باش.
- ابتدا منظور و شرایط کاربر را بفهم؛ اگر اطلاعات مهمی کم است فقط یک سؤال روشن بپرس.
- توصیه‌ها را بر اساس هدف، درس‌ها، پیش‌نیازها، نقاط ضعف، زمان‌های ثابت، روزهای در دسترس، زمان مطالعه و آمار ارائه‌شده شخصی‌سازی کن.
- برنامه‌ها باید واقع‌بینانه باشند، استراحت و خواب کافی را در نظر بگیرند و از برنامه‌های فشرده و تنبیهی پرهیز کنند.
- اگر کاربر درباره برنامه سؤال دارد، پیشنهاد را به گام‌های کوچک و قابل اجرا تبدیل کن و دلیل اولویت‌ها را توضیح بده.
- هیچ‌وقت وانمود نکن داده‌ای را می‌دانی که در متن زمینه نیامده است؛ داده ناموجود را صریح بگو.
- درباره سلامت، مسائل حقوقی یا مالی تخصصی تشخیص قطعی نده؛ در موضوعات مهم به بزرگسال قابل اعتماد یا متخصص مناسب ارجاع بده.
- اطلاعات خصوصی غیرضروری درخواست نکن. از کاربر رمز، کلید API یا اطلاعات حساب نخواه.
- پاسخ را با یک قدم بعدی مشخص تمام کن، مگر اینکه سؤال کاملاً پاسخ داده شده باشد.
`.trim();

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  const headers = corsHeaders(origin);

  if (req.method === "OPTIONS") return new Response("ok", { headers });
  if (req.method !== "POST") return json({ error: "روش درخواست پشتیبانی نمی‌شود." }, 405, headers);
  if (!PROJECT_URL || !PUBLISHABLE_KEY || !OPENAI_API_KEY) {
    return json({ error: "تنظیمات اتصال مشاور کامل نیست. مدیر سایت باید کلیدهای امن را در Supabase تنظیم کند." }, 503, headers);
  }

  try {
    const authHeader = req.headers.get("authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "برای استفاده از مشاور ابتدا وارد حساب کاربری شو." }, 401, headers);

    const supabase = createClient(PROJECT_URL, PUBLISHABLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await supabase.auth.getUser(token);
    if (userError || !userData.user) return json({ error: "نشست ورود معتبر نیست؛ دوباره وارد حساب شو." }, 401, headers);

    const body = await req.json();
    const rawMessages = Array.isArray(body.messages) ? body.messages : [];
    const messages = rawMessages
      .filter((m: any) => m && ["user", "assistant"].includes(m.role) && typeof m.content === "string")
      .slice(-12)
      .map((m: any) => ({ role: m.role, content: m.content.slice(0, 2500) }));
    if (!messages.length || !messages.some((m: any) => m.role === "user")) {
      return json({ error: "پیام قابل‌ارسالی پیدا نشد." }, 400, headers);
    }

    const context = body.context && typeof body.context === "object" ? body.context : {};
    const safeContext = JSON.stringify(context).slice(0, 7000);
    const input = [
      { role: "user", content: "اطلاعات برنامه‌ریزی کاربر (فقط برای شخصی‌سازی پاسخ؛ ممکن است ناقص باشد):\n" + safeContext },
      ...messages,
    ];

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + OPENAI_API_KEY,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        instructions,
        input,
        max_output_tokens: 900,
        store: false,
      }),
    });

    const result = await response.json();
    if (!response.ok) {
      console.error("OpenAI API error", response.status, result?.error?.code ?? "unknown");
      return json({ error: "ارتباط با سرویس هوش مصنوعی برقرار نشد. کمی بعد دوباره تلاش کن." }, 502, headers);
    }

    const answer = typeof result.output_text === "string"
      ? result.output_text
      : (result.output ?? [])
          .filter((item: any) => item.type === "message")
          .flatMap((item: any) => item.content ?? [])
          .filter((item: any) => item.type === "output_text")
          .map((item: any) => item.text)
          .join("\n")
          .trim();

    if (!answer) return json({ error: "پاسخی دریافت نشد؛ لطفاً دوباره سؤال را بفرست." }, 502, headers);
    return json({ answer }, 200, headers);
  } catch (error) {
    console.error("study-advisor error", error);
    return json({ error: "خطای موقت در پردازش پیام. دوباره تلاش کن." }, 500, headers);
  }
});
