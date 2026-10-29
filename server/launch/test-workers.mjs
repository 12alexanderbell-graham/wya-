// node test-workers.mjs : both Workers against mocks (no network, no keys)
import ai from './ai-worker.js';
import data from './data-worker.js';
const kv = new Map();
const env = {SUPABASE_URL: 'https://sb.example', SUPABASE_ANON_KEY: 'anon', ANTHROPIC_API_KEY: 'sk-test', MODEL_FREE: 'free-model', MODEL_PREMIUM: 'premium-model', CAP_FREE: '2',
  LIMITS: {get: async k => kv.get(k) ?? null, put: async (k, v) => { kv.set(k, v); }}};
const sent = [];
globalThis.fetch = async (url, opt = {}) => {
  sent.push([String(url), opt.headers && (opt.headers['x-api-key'] || opt.headers.Authorization)]);
  if (String(url).endsWith('/auth/v1/user')) return opt.headers.Authorization === 'Bearer good' ? new Response(JSON.stringify({id: 'u1'})) : new Response('no', {status: 401});
  if (String(url).includes('/rest/v1/profiles')) return new Response(JSON.stringify([{premium: false}]));
  if (String(url) === 'https://api.anthropic.com/v1/messages') { const b = JSON.parse(opt.body); return new Response(JSON.stringify({model: b.model, content: [{type: 'text', text: 'hi'}]})); }
  throw new Error('unexpected ' + url);
};
const ask = (auth, body) => ai.fetch(new Request('https://ai.example/', {method: 'POST', headers: {Authorization: auth, 'Content-Type': 'application/json'}, body: JSON.stringify(body)}), env);
let r = await ask('Bearer bad', {messages: [{role: 'user', content: 'x'}]}); console.log('bad token', r.status);
r = await ask('Bearer good', {messages: [{role: 'user', content: 'x'}]}); console.log('good 1', r.status, (await r.json()).model);
r = await ask('Bearer good', {messages: [{role: 'user', content: 'x'}]}); console.log('good 2', r.status);
r = await ask('Bearer good', {messages: [{role: 'user', content: 'x'}]}); console.log('good 3 (over cap of 2)', r.status, r.headers.get('Access-Control-Allow-Origin'));
r = await ask('Bearer good', {}); console.log('no messages (still capped first)', r.status);
console.log('key only ever sent to Anthropic:', sent.filter(s => s[1] === 'sk-test').every(s => s[0] === 'https://api.anthropic.com/v1/messages'));
// data
const store = {'v1/countries.json.gz': 'GZ', 'v1/passports/fr.svg': '<svg/>'};
const denv = {DATA: {get: async k => k in store ? {body: store[k]} : null}};
for (const p of ['/v1/countries.json', '/v1/passports/fr.svg', '/v1/nope.json', '/etc/passwd', '/v1/../x']) {
  const res = await data.fetch(new Request('https://data.example' + p), denv);
  console.log('data', p, res.status, res.headers.get('Content-Type'), res.headers.get('Content-Encoding'));
}
