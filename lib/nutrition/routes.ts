import { z } from 'zod';
import { nutritionPrompts } from './prompts.ts';
const number = (max: number) => z.number().finite().min(0).max(max);
const food = z.object({ name: z.string().trim().min(1).max(120).regex(/^[^\u0000-\u001f]+$/), grams: z.number().finite().positive().max(10_000), kcal: number(20_000), protein: number(2_000), carbs: number(2_000), fat: number(2_000), confidence: number(1) }).strict();
const outputFoods = z.object({ items: z.array(food).min(1).max(30) }).strict();
const language = z.enum(['en', 'ar']).optional();
const textInput = z.object({ language, text: z.string().trim().min(1).max(2_000) }).strict();
const imageInput = z.object({ language, image: z.string().min(16).max(1_400_000).regex(/^data:image\/(?:jpeg|png);base64,[A-Za-z0-9+/]+=*$/) }).strict();
const exerciseInput = textInput.extend({ weightKg: z.number().finite().min(20).max(400) }).strict();
const nullable = z.number().finite().min(-1_000_000).max(1_000_000).nullable();
const reviewInput = z.object({ language, day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(v => v >= '1900-01-01' && v <= '2100-12-31' && Number.isFinite(Date.parse(v + 'T00:00:00Z')) && new Date(v + 'T00:00:00Z').toISOString().slice(0, 10) === v), eaten: number(1_000_000), protein: number(100_000), carbs: number(100_000), fat: number(100_000), exercise: number(1_000_000), goal: number(1_000_000).nullable(), estimatedBurned: number(1_000_000).nullable(), balance: nullable, complete: z.boolean() }).strict();
export class NutritionRouteError extends Error {
  public status: number;
  public code: string;
  constructor(status: number, code: string, message: string) { super(message); this.status = status; this.code = code; }
}
export interface NutritionConfig { provider?: string; apiKey?: string; apiURL?: string; model?: string }
type ChatContent = string | ({ type: 'text'; text: string } | { type: 'image_url'; image_url: { url: string; detail: 'low' } })[];
interface ProviderEnvelope { choices: { message: { content: string } }[] }
const providerEnvelope = z.object({ choices: z.array(z.object({ message: z.object({ content: z.string().min(1).max(100_000) }) })).min(1).max(10) });
interface ProviderSettings { provider: 'openai' | 'gemini'; key: string; url: string; model: string }
const geminiEnvelope = z.object({ candidates: z.array(z.object({ content: z.object({ parts: z.array(z.object({ text: z.string().optional(), thought: z.boolean().optional() })).max(20) }) })).min(1).max(10) });
function settings(config: NutritionConfig): ProviderSettings | null {
  const provider = config.provider?.trim().toLowerCase() || 'openai';
  if (provider !== 'openai' && provider !== 'gemini') return null;
  const key = config.apiKey?.trim(), model = config.model?.trim() || (provider === 'gemini' ? 'gemini-2.5-flash' : 'gpt-4o-mini');
  if (!key || key.length > 8_192 || /[\r\n]/.test(key) || !/^[A-Za-z0-9._-]{1,100}$/.test(model)) return null;
  try {
    const u = new URL(config.apiURL || (provider === 'gemini' ? 'https://generativelanguage.googleapis.com/v1beta' : ''));
    if (u.protocol !== 'https:' || u.username || u.password || u.hash) return null;
    if (provider === 'gemini') {
      if (u.hostname !== 'generativelanguage.googleapis.com' || u.port || u.search || !/^\/v1(?:beta)?\/?$/.test(u.pathname)) return null;
      u.pathname = u.pathname.replace(/\/$/, '') + '/models/' + model + ':generateContent';
    }
    return { provider, key, url: u.toString(), model };
  } catch { return null; }
}
export function nutritionConfigurationReady(config: NutritionConfig): boolean { return settings(config) !== null; }
type GeminiPart = { text: string } | { inlineData: { mimeType: 'image/jpeg' | 'image/png'; data: string } };
function geminiParts(content: ChatContent): GeminiPart[] {
  if (typeof content === 'string') return [{ text: content }];
  return content.map(part => {
    if (part.type === 'text') return { text: part.text };
    const match = /^data:image\/(jpeg|png);base64,([A-Za-z0-9+/]+=*)$/.exec(part.image_url.url);
    if (!match?.[2]) throw new NutritionRouteError(400, 'invalid_request', 'Choose a supported meal photo.');
    return { inlineData: { mimeType: match[1] === 'jpeg' ? 'image/jpeg' : 'image/png', data: match[2] } };
  });
}
function parseJSON(text: string): unknown {
  const stripped = text.trim().replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '');
  return JSON.parse(stripped) as unknown;
}
export function createNutritionAPI(config: NutritionConfig, transport: typeof fetch = globalThis.fetch) {
  const configured = settings(config);
  async function ask<T>(system: string, content: ChatContent, schema: z.ZodType<T>, parent?: AbortSignal, responseLanguage: 'en' | 'ar' = 'en'): Promise<T> {
    if (!configured) throw new NutritionRouteError(503, 'ai_not_configured', 'Nutrition AI is not configured. Add AI_API_KEY and AI_API_URL on the server. Manual logging still works.');
    for (let attempt = 0; attempt < 2; attempt++) {
      let response: Response;
      const instruction = system + (responseLanguage === 'ar' ? '\nWrite food names and the summary in Arabic. Preserve the exact JSON property names and numeric values.' : '\nWrite food names and the summary in English.');
      const retry = attempt ? 'The previous response was invalid. Return only valid JSON matching the exact required schema.' : '';
      const headers: Record<string, string> = { 'Content-Type': 'application/json', Accept: 'application/json' };
      let requestBody: object;
      if (configured.provider === 'gemini') {
        headers['x-goog-api-key'] = configured.key;
        requestBody = { systemInstruction: { parts: [{ text: instruction }] }, contents: [{ role: 'user', parts: [...geminiParts(content), ...(retry ? [{ text: retry }] : [])] }],
          generationConfig: { temperature: 0.2, maxOutputTokens: 2_000, responseMimeType: 'application/json', ...(configured.model.startsWith('gemini-2.5-') ? { thinkingConfig: { thinkingBudget: 0 } } : {}) } };
      } else {
        headers.Authorization = `Bearer ${configured.key}`;
        requestBody = { model: configured.model, temperature: 0.2, max_tokens: 1_500, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: instruction }, { role: 'user', content }, ...(retry ? [{ role: 'user', content: retry }] : [])] };
      }
      try {
        response = await transport(configured.url, { method: 'POST', redirect: 'error', signal: AbortSignal.any([AbortSignal.timeout(20_000), ...(parent ? [parent] : [])]),
          headers, body: JSON.stringify(requestBody) });
      } catch { throw new NutritionRouteError(503, 'ai_unavailable', 'The AI provider could not be reached. Try again or enter values manually.'); }
      if (!response.ok) {
        await response.body?.cancel().catch(() => {});
        if (response.status === 401 || response.status === 403) throw new NutritionRouteError(503, 'ai_credentials_rejected', 'The server AI key was rejected. Update it in the server environment settings.');
        if (response.status === 429) throw new NutritionRouteError(429, 'rate_limited', 'Nutrition AI is busy. Wait a moment and try again.');
        throw new NutritionRouteError(503, 'ai_unavailable', 'The AI provider could not complete this request. Check the server configuration or enter values manually.');
      }
      if (Number(response.headers.get('content-length')) > 256 * 1024) { await response.body?.cancel().catch(() => {}); throw new NutritionRouteError(503, 'ai_invalid_response', 'The AI response was too large. Try a smaller meal or enter it manually.'); }
      const chunks: Uint8Array[] = []; let bytes = 0;
      try { for await (const chunk of response.body ?? []) { bytes += chunk.length; if (bytes > 256 * 1024) throw new Error('limit'); chunks.push(chunk); } }
      catch { await response.body?.cancel().catch(() => {}); throw new NutritionRouteError(503, 'ai_unavailable', 'The AI response could not be read. Try again.'); }
      try {
        const raw = parseJSON(Buffer.concat(chunks).toString('utf8'));
        let contentText: string;
        if (configured.provider === 'gemini') {
          const envelope = geminiEnvelope.parse(raw);
          contentText = envelope.candidates[0]?.content.parts.filter(part => !part.thought).flatMap(part => part.text ? [part.text] : []).join('') ?? '';
        } else {
          const envelope: ProviderEnvelope = providerEnvelope.parse(raw);
          contentText = envelope.choices[0]?.message.content ?? '';
        }
        return schema.parse(parseJSON(contentText));
      } catch { if (attempt === 1) throw new NutritionRouteError(502, 'ai_invalid_response', 'The AI could not return usable estimates. Try a clearer description or enter values manually.'); }
    }
    throw new NutritionRouteError(502, 'ai_invalid_response', 'The AI response was invalid.');
  }
  return async (path: string, body: unknown, signal?: AbortSignal): Promise<unknown> => {
    try {
      if (path === '/api/nutrition/analyze-meal') {
        const input = imageInput.parse(body), encoded = input.image.split(',')[1] ?? '', bytes = Buffer.from(encoded, 'base64');
        const jpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
        const png = bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
        if (bytes.length > 1_000_000 || (!jpeg && !png)) throw new NutritionRouteError(400, 'invalid_request', 'Choose a compressed JPEG or PNG meal photo below 1 MB.');
        return ask(nutritionPrompts.analyzeMeal, [{ type: 'text', text: 'Estimate the visible meal for review before saving.' }, { type: 'image_url', image_url: { url: input.image, detail: 'low' } }], outputFoods, signal, input.language);
      }
      if (path === '/api/nutrition/parse-food') { const input = textInput.parse(body); return ask(nutritionPrompts.parseFood, JSON.stringify({ text: input.text }), outputFoods, signal, input.language); }
      if (path === '/api/nutrition/estimate-exercise') { const input = exerciseInput.parse(body); return ask(nutritionPrompts.exercise, JSON.stringify(input), z.object({ kcal: number(20_000) }).strict(), signal, input.language); }
      if (path === '/api/nutrition/day-review') { const input = reviewInput.parse(body); return ask(nutritionPrompts.dayReview, JSON.stringify(input), z.object({ summary: z.string().trim().min(1).max(420) }).strict(), signal, input.language); }
      throw new NutritionRouteError(404, 'not_found', 'Nutrition route not found.');
    } catch (error: unknown) {
      if (error instanceof z.ZodError) throw new NutritionRouteError(400, 'invalid_request', 'Check the nutrition input and try again.');
      throw error;
    }
  };
}
