import { NextResponse, type NextRequest } from "next/server";
import { apiRequest } from "@/app/(dashboard)/_lib/api";
import { SESSION_COOKIE } from "@/app/(dashboard)/_lib/session";

// Passes the spreadsheet to the API with the staff token, which stays on the server.
const MAX_BYTES = 2 * 1024 * 1024;

export async function POST(req: NextRequest) {
  const token = req.cookies.get(SESSION_COOKIE)?.value;
  if (!token) return NextResponse.json({ error: "Please sign in again.", signedOut: true }, { status: 401 });

  let file: FormDataEntryValue | null = null;
  try {
    file = (await req.formData()).get("file");
  } catch {
    file = null;
  }
  if (!(file instanceof File) || file.size === 0) return NextResponse.json({ error: "Choose a CSV or Excel file first." }, { status: 400 });
  if (file.size > MAX_BYTES) return NextResponse.json({ error: "File is larger than 2 MB. Split it into smaller files." }, { status: 413 });

  const form = new FormData();
  form.set("file", file, file.name);
  const r = await apiRequest("/v1/admin/imports", { method: "POST", form, token, timeoutMs: 60000 });
  if (r.ok) return NextResponse.json({ batch: r.data });
  const res = NextResponse.json({ error: r.error, signedOut: r.status === 401 }, { status: r.status || 502 });
  if (r.status === 401) res.cookies.delete(SESSION_COOKIE);
  return res;
}
