// wya?! AI endpoint, a Cloudflare Worker. The Anthropic key lives here as a secret and never in the app. The app posts
// {system, messages, max_tokens} with the person's Supabase token; the Worker checks the token, counts the day's
// questions, and passes the question to Anthropic. Written 24 Sep 2026 night; tested against mocks, not yet deployed.
// Secrets (npx wrangler secret put NAME): ANTHROPIC_API_KEY, SUPABASE_ANON_KEY Vars (wrangler.toml [vars]):
// SUPABASE_URL, MODEL_FREE, MODEL_PREMIUM, CAP_FREE, CAP_PREMIUM, ALLOW_ORIGIN MODEL_FREE and MODEL_PREMIUM are model
// ids from Anthropic's models page; the app's "better AI" for premium is MODEL_PREMIUM. KV binding: LIMITS (counts per
// person per day)

const cors = (res, env) => {
  const h = new Headers(res.headers);
  h.set('Access-Control-Allow-Origin', env.ALLOW_ORIGIN || '*');
  h.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  h.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  return new Response(res.body, {status: res.status, headers: h});
};
const json = (o, status = 200) => new Response(JSON.stringify(o), {status, headers: {'Content-Type': 'application/json'}});

async function whoIs(env, auth){
  if (!/^Bearer\s+\S+/.test(auth || '')) return null;
  const r = await fetch(env.SUPABASE_URL + '/auth/v1/user', {headers: {Authorization: auth, apikey: env.SUPABASE_ANON_KEY}});
  if (!r.ok) return null;
  const u = await r.json();
  if (!u || !u.id) return null;
  // premium is set on the profile by the purchase webhook; read it with the person's own token
  const p = await fetch(env.SUPABASE_URL + '/rest/v1/profiles?select=premium&id=eq.' + encodeURIComponent(u.id),
    {headers: {Authorization: auth, apikey: env.SUPABASE_ANON_KEY}});
  const rows = p.ok ? await p.json() : [];
  return {id: u.id, premium: !!(rows[0] && rows[0].premium)};
}

export default {
  async fetch(req, env){
    if (req.method === 'OPTIONS') return cors(new Response(null, {status: 204}), env);
    if (req.method !== 'POST') return cors(json({error: 'POST only'}, 405), env);
    const who = await whoIs(env, req.headers.get('Authorization'));
    if (!who) return cors(json({error: 'Sign in first'}, 401), env);

    const day = new Date().toISOString().slice(0, 10);
    const key = 'ai:' + who.id + ':' + day;
    const used = parseInt((await env.LIMITS.get(key)) || '0', 10);
    const cap = who.premium ? Number(env.CAP_PREMIUM || 200) : Number(env.CAP_FREE || 20);
    if (used >= cap) return cors(json({error: 'That is today’s questions', cap}, 429), env);

    let body;
    try { body = await req.json(); } catch (e) { return cors(json({error: 'Bad request'}, 400), env); }
    if (!Array.isArray(body.messages) || !body.messages.length) return cors(json({error: 'No question'}, 400), env);

    // the same as serve.py's /v1/ask: {system, messages, max_tokens, web}; web asks with Anthropic's web search, and
    // without it if the key has search switched off; a turn that searched and paused is sent back to finish, twice at
    // most; the answer goes back as it came
    const model = who.premium ? env.MODEL_PREMIUM : env.MODEL_FREE;
    const payload = {
      model,
      max_tokens: Math.max(64, Math.min(Number(body.max_tokens) || 1024, 2048)),
      system: typeof body.system === 'string' && body.system ? body.system.slice(0, 20000) : undefined,
      messages: body.messages.slice(-20),
    };
    if (body.web) payload.tools = [{type: 'web_search_20250305', name: 'web_search', max_uses: 3}];
    const ask = async () => {
      const r = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {'x-api-key': env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'},
        body: JSON.stringify(payload),
      });
      return {status: r.status, text: await r.text()};
    };
    let res = await ask();
    if (res.status === 400 && payload.tools && res.text.includes('web_search')){ delete payload.tools; res = await ask(); }
    let done = [];
    for (let i = 0; i < 2; i++){
      let j; try { j = JSON.parse(res.text); } catch (e) { break; }
      if (res.status !== 200 || j.stop_reason !== 'pause_turn') break;
      done = done.concat(j.content || []);
      payload.messages = payload.messages.concat([{role: 'assistant', content: j.content || []}]);
      res = await ask();
    }
    if (done.length && res.status === 200){
      try { const j = JSON.parse(res.text); j.content = done.concat(j.content || []); res.text = JSON.stringify(j); } catch (e) {}
    }
    if (res.status === 200) await env.LIMITS.put(key, String(used + 1), {expirationTtl: 60 * 60 * 48});
    return cors(new Response(res.text, {status: res.status, headers: {'Content-Type': 'application/json'}}), env);
  },
};
