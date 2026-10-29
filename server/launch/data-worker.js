// wya?! travel data, a Cloudflare Worker in front of an R2 bucket. The data server on your Mac writes
// server/public.nosync/v1/, mostly as .gz files; upload-data.sh copies that folder into the bucket as it is, and this
// Worker answers /v1/<path> the way serve.py does: the .gz copy, sent compressed, with the right type. Written 24 Sep
// 2026 night; tested against mocks. Binding: DATA (the R2 bucket). Vars: ALLOW_ORIGIN.
const TYPES = {json: 'application/json; charset=utf-8', js: 'text/javascript; charset=utf-8', svg: 'image/svg+xml',
               jpg: 'image/jpeg', png: 'image/png', mp4: 'video/mp4'};

export default {
  async fetch(req, env){
    const url = new URL(req.url);
    if (req.method !== 'GET' && req.method !== 'HEAD') return new Response('GET only', {status: 405});
    const path = decodeURIComponent(url.pathname).replace(/^\/+/, '');
    if (!path.startsWith('v1/') || path.includes('..')) return new Response('Not here', {status: 404});
    const ext = (path.split('.').pop() || '').toLowerCase();
    const headers = new Headers({'Access-Control-Allow-Origin': env.ALLOW_ORIGIN || '*',
                                 'Cache-Control': 'public, max-age=3600',
                                 'Content-Type': TYPES[ext] || 'application/octet-stream'});
    let obj = await env.DATA.get(path + '.gz');
    if (obj){ headers.set('Content-Encoding', 'gzip'); }
    else obj = await env.DATA.get(path);
    if (!obj) return new Response('Not here', {status: 404, headers});
    // the bytes are already gzip: tell Cloudflare not to compress them again
    return new Response(req.method === 'HEAD' ? null : obj.body, {status: 200, headers, encodeBody: 'manual'});
  },
};
