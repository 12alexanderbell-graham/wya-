#!/usr/bin/env python3
"""The wya?! data server, for development on this Mac.

    python3 server/serve.py            # then http://localhost:8787/v1/manifest.json
    python3 server/serve.py --background --build-if-needed
                                       # what Xcode runs before the app launches: builds the
                                       # data if it isn't there or its sources changed since,
                                       # starts the server detached, does nothing if the
                                       # right one is already running

It serves public.nosync/ exactly as a static host would: the gzipped files go out with
Content-Encoding: gzip, any web page may read them (CORS), and every file has an ETag so the
app only downloads what changed. It listens on this Mac only (127.0.0.1 and ::1), which is
what the iOS Simulator reaches as "localhost". A real phone cannot reach it; that is what the
remote host is for, later (see README.md).

It also answers the AI (POST /v1/ask) while developing: the app sends {system, messages,
max_tokens, web}, this passes it to Anthropic with the key from secret.nosync/anthropic-key.txt and
sends back Anthropic's answer as it came. The key never leaves this Mac and never goes in the app.
With no key there it answers 503 {"error":"no-key"}, and the app says the AI is not connected.
The model is WYA_AI_MODEL, or AI_MODEL below. launch/ai-worker.js is the same thing for real phones.

It also is the app server while developing (row 146, app.py): who you are, the sync queue, votes, reports, place
pages and the leaderboard, under /v1/me, /v1/ops, /v1/changes, /v1/votes, /v1/placepage/<id> and /v1/board.

Standard library only, nothing to install.
"""
import gzip, hashlib, http.server, json, os, signal, socket, ssl, subprocess, sys, tempfile, threading, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, 'public.nosync')   # see build_api.py for the .nosync
PORT = int(os.environ.get('WYA_PORT', '8787'))
LOG = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'wya-data-server.log')
PIDF = os.path.join(os.environ.get('TMPDIR', '/tmp'), 'wya-data-server.pid')
# which version of this file a running server is: a server started by an older serve.py is
# replaced, so a change here (a new file type, say) reaches the app without anyone quitting it
# (app.py too: a change to the app server replaces a running one the same way)
_code = hashlib.sha1()
for _p in (os.path.abspath(__file__), os.path.join(HERE, 'app.py')):
    try:
        with open(_p, 'rb') as _f: _code.update(_f.read())
    except OSError:
        pass
CODE = _code.hexdigest()[:12]
sys.path.insert(0, HERE)
import app
TYPES = {'.json': 'application/json; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.svg': 'image/svg+xml',
         '.jpg': 'image/jpeg', '.png': 'image/png', '.mp4': 'video/mp4'}
_etags = {}

# ---- the AI (POST /v1/ask) ----
SECRET = os.path.join(HERE, 'secret.nosync')
# model ids from platform.claude.com/docs/en/models/overview, read 2 Oct 2026. The everyday AI;
# premium's "better AI" is MODEL_PREMIUM in launch/wrangler-ai.toml once there are accounts.
AI_MODEL = os.environ.get('WYA_AI_MODEL') or 'claude-sonnet-5-5'
AI_UPSTREAM = os.environ.get('WYA_AI_UPSTREAM') or 'https://api.anthropic.com/v1/messages'
AI_WEB = {'type': 'web_search_20250305', 'name': 'web_search', 'max_uses': 3}

def ai_key():
    try:
        with open(os.path.join(SECRET, 'anthropic-key.txt')) as f: k = f.read().strip()
    except OSError:
        return None
    return k or None

def _upstream_urllib(data, key):
    req = urllib.request.Request(AI_UPSTREAM, data=data, method='POST', headers={
        'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()

def _upstream_curl(data, key):
    """the Mac's own curl, for a Python that has no certificates to check Anthropic's with (the
    python.org one until its Install Certificates is run). The key goes in on stdin, never on the
    command line where ps would show it."""
    fd, body = tempfile.mkstemp(suffix='.json')
    try:
        with os.fdopen(fd, 'wb') as f: f.write(data)
        cfg = 'header = "x-api-key: %s"\nheader = "anthropic-version: 2023-06-01"\nheader = "content-type: application/json"\n' % key
        out = subprocess.run(['curl', '-sS', '-K', '-', '--max-time', '180', '-w', '\n%{http_code}',
                              '--data-binary', '@' + body, AI_UPSTREAM], input=cfg.encode(), capture_output=True, timeout=200)
        text, _, code = out.stdout.rpartition(b'\n')
        if not code.strip().isdigit() or int(code) == 0:
            return 502, json.dumps({'error': 'unreachable', 'detail': out.stderr.decode('utf-8', 'replace')[:300]}).encode()
        return int(code), text
    finally:
        os.unlink(body)

def ai_upstream(payload, key):
    data = json.dumps(payload).encode()
    try:
        return _upstream_urllib(data, key)
    except (ssl.SSLError, urllib.error.URLError) as e:
        if isinstance(e, urllib.error.URLError) and not isinstance(getattr(e, 'reason', None), ssl.SSLError):
            return 502, json.dumps({'error': 'unreachable', 'detail': str(e.reason)[:300]}).encode()
        return _upstream_curl(data, key)

def ai_ask(body):
    """one question: (status, json bytes). Anthropic's answer goes back as it came, so the app
    reads the same thing from here and from the Worker"""
    msgs = body.get('messages')
    if not isinstance(msgs, list) or not msgs:
        return 400, b'{"error":"No question"}'
    key = ai_key()
    if not key:
        return 503, b'{"error":"no-key"}'
    try: mt = int(body.get('max_tokens') or 1024)
    except (TypeError, ValueError): mt = 1024
    payload = {'model': AI_MODEL, 'max_tokens': max(64, min(mt, 2048)), 'messages': msgs[-20:]}
    if isinstance(body.get('system'), str) and body['system']:
        payload['system'] = body['system'][:20000]
    if body.get('web'):
        payload['tools'] = [AI_WEB]
    code, out = ai_upstream(payload, key)
    # web search is switched off for this key (Console, Settings, Capabilities): ask without it
    if code == 400 and 'tools' in payload and b'web_search' in out:
        payload.pop('tools')
        code, out = ai_upstream(payload, key)
    # a turn that searched can stop part way (pause_turn): send it back and let it finish, twice at most
    done = []
    for _ in range(2):
        try: j = json.loads(out)
        except ValueError: break
        if code != 200 or j.get('stop_reason') != 'pause_turn': break
        done += j.get('content') or []
        payload['messages'] = payload['messages'] + [{'role': 'assistant', 'content': j.get('content') or []}]
        code, out = ai_upstream(payload, key)
    if done and code == 200:
        try:
            j = json.loads(out); j['content'] = done + (j.get('content') or []); out = json.dumps(j).encode()
        except ValueError:
            pass
    return code, out

class Handler(http.server.BaseHTTPRequestHandler):
    server_version = 'wya-data/1'

    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, HEAD, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'If-None-Match, Content-Type, Authorization')
        self.send_header('Access-Control-Expose-Headers', 'ETag')

    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()

    def do_HEAD(self): self._serve(head=True)
    def do_GET(self):
        if self._app('GET', None): return
        self._serve(head=False)

    def _app(self, method, body):
        """an app server call (app.py), answered; False when the path is a data file's"""
        try:
            got = app.handle(method, self.path, self.headers, body)
        except Exception as e:                          # said, not swallowed
            got = (500, {'error': 'server', 'detail': str(e)[:300]})
        if got is None: return False
        code, out = got
        data = json.dumps(out, ensure_ascii=False).encode('utf-8')
        self.send_response(code); self._cors()
        self.send_header('Content-Type', TYPES['.json']); self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers(); self.wfile.write(data)
        return True

    def do_POST(self):
        if self.path.split('?', 1)[0] != '/v1/ask':
            try: n = int(self.headers.get('Content-Length') or 0)
            except ValueError: n = 0
            if n > app.BODY_MAX * 2: return self._err(413)
            body = None
            if n > 0:
                try: body = json.loads(self.rfile.read(n).decode('utf-8'))
                except (ValueError, UnicodeDecodeError): return self._err(400)
                if not isinstance(body, dict): return self._err(400)
            if self._app('POST', body): return
            return self._err(404)
        try: n = int(self.headers.get('Content-Length') or 0)
        except ValueError: n = 0
        if n <= 0: return self._err(400)
        if n > 12000000: return self._err(413)        # a question with a photo is well under this
        try:
            body = json.loads(self.rfile.read(n).decode('utf-8'))
        except (ValueError, UnicodeDecodeError):
            return self._err(400)
        if not isinstance(body, dict): return self._err(400)
        # the AI's gate (app.py): an identity's questions are counted per day, and refused past the day's limit
        ok, _who = app.ai_gate(self.headers.get('Authorization'))
        if not ok:
            out = b'{"error":"limit"}'
            self.send_response(429); self._cors()
            self.send_header('Content-Type', TYPES['.json']); self.send_header('Content-Length', str(len(out)))
            self.end_headers(); self.wfile.write(out); return
        try:
            code, out = ai_ask(body)
        except Exception as e:                          # said, not swallowed: the app shows it failed
            code, out = 502, json.dumps({'error': 'server', 'detail': str(e)[:300]}).encode()
        self.send_response(code); self._cors()
        self.send_header('Content-Type', TYPES['.json']); self.send_header('Content-Length', str(len(out)))
        self.end_headers(); self.wfile.write(out)

    def _serve(self, head):
        path = self.path.split('?', 1)[0]
        if path in ('/', '/health'):
            body = ('{"ok":true,"api":"/v1/manifest.json","code":"%s"}' % CODE).encode()
            self.send_response(200); self._cors()
            self.send_header('Content-Type', TYPES['.json']); self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            if not head: self.wfile.write(body)
            return
        # no way out of public/
        rel = os.path.normpath(path.lstrip('/'))
        if rel.startswith('..') or os.path.isabs(rel):
            return self._err(400)
        gz = os.path.join(ROOT, rel + '.gz')
        if not os.path.isfile(gz):
            return self._err(404)
        st = os.stat(gz)
        key = (gz, st.st_mtime_ns, st.st_size)
        with open(gz, 'rb') as f: data = f.read()
        etag = _etags.get(key)
        if not etag:
            etag = '"%s"' % hashlib.sha1(data).hexdigest()[:20]; _etags[key] = etag
        if self.headers.get('If-None-Match') == etag:
            self.send_response(304); self._cors(); self.send_header('ETag', etag); self.end_headers(); return
        gzip_ok = 'gzip' in (self.headers.get('Accept-Encoding') or '')
        body = data if gzip_ok else gzip.decompress(data)
        self.send_response(200); self._cors()
        self.send_header('Content-Type', TYPES.get(os.path.splitext(rel)[1], 'application/octet-stream'))
        if gzip_ok: self.send_header('Content-Encoding', 'gzip')
        self.send_header('Vary', 'Accept-Encoding')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('ETag', etag)
        self.send_header('Cache-Control', 'no-cache')          # always revalidate while developing
        self.end_headers()
        if not head: self.wfile.write(body)

    def _err(self, code):
        body = ('{"error":%d}' % code).encode()
        self.send_response(code); self._cors()
        self.send_header('Content-Type', TYPES['.json']); self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)

    def log_message(self, fmt, *args):
        sys.stdout.write('%s %s\n' % (time.strftime('%H:%M:%S'), fmt % args)); sys.stdout.flush()

class V6(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6

def health():
    """what the wya?! data server on this port says about itself, or None if there is none"""
    try:
        with urllib.request.urlopen('http://127.0.0.1:%d/health' % PORT, timeout=1) as r:
            h = json.loads(r.read().decode('utf-8'))
            return h if h.get('ok') else None
    except Exception:
        return None

def running():
    return health() is not None

def stale():
    """why the built data is out of date, or None: it is missing, or something it is built from
    (this folder's scripts, reference/data) changed after it was built"""
    man = os.path.join(ROOT, 'v1', 'manifest.json.gz')
    if not os.path.isfile(man): return 'no data built yet'
    built = os.path.getmtime(man)
    # (the servers themselves are not what the data is built from)
    srcs = [os.path.join(HERE, f) for f in os.listdir(HERE) if f.endswith('.py') and f not in ('serve.py', 'app.py', 'test_app.py')]
    data = os.path.join(HERE, '..', 'reference', 'data')
    if os.path.isdir(data):
        srcs += [os.path.join(data, f) for f in os.listdir(data) if not f.startswith(('.', '_'))]
    newer = [p for p in srcs if os.path.getmtime(p) > built]
    return ('%d of its sources changed since it was built' % len(newer)) if newer else None

def stop_old():
    """stop the server already on this port (an older serve.py, or data that is being rebuilt)"""
    pids = []
    try:
        with open(PIDF) as f: pids.append(int(f.read().strip()))
    except Exception:
        pass
    if not pids:
        # started before the pid file existed: ask the system who listens on the port, and
        # stop it only if it is this script
        try:
            out = subprocess.run(['lsof', '-ti', 'tcp:%d' % PORT, '-sTCP:LISTEN'], capture_output=True, text=True, timeout=5).stdout
            for pid in out.split():
                cmd = subprocess.run(['ps', '-o', 'command=', '-p', pid], capture_output=True, text=True, timeout=5).stdout
                if 'serve.py' in cmd: pids.append(int(pid))
        except Exception:
            pass
    for pid in pids:
        try: os.kill(pid, signal.SIGTERM)
        except OSError: pass
    for _ in range(30):
        if not running(): return True
        time.sleep(0.1)
    return not running()

def detach():
    """leave the terminal or Xcode behind: two forks and a new session, so closing the
    parent (or Xcode ending its pre-action) doesn't take the server with it"""
    if os.fork(): os._exit(0)
    os.setsid()
    if os.fork(): os._exit(0)
    log = open(LOG, 'a', buffering=1)
    os.dup2(log.fileno(), 1); os.dup2(log.fileno(), 2)
    devnull = os.open(os.devnull, os.O_RDONLY); os.dup2(devnull, 0)
    sys.stdout = sys.stderr = log

def main():
    args = sys.argv[1:]
    build = '--build-if-needed' in args
    why = stale() if build else None
    h = health()
    if h:
        if h.get('code') == CODE and not why:
            print('Already running on http://localhost:%d/' % PORT); return
        print('Replacing the running server (%s)' % (why or 'it is an older serve.py'), flush=True)
        if not stop_old():
            sys.exit('A server is on port %d and would not stop. Quit it and run this again.' % PORT)
    if '--background' in args:
        print('Starting in the background, log: ' + LOG, flush=True)
        detach()
    if not os.path.isfile(os.path.join(ROOT, 'v1', 'manifest.json.gz')) and not build:
        sys.exit('No data built yet. Run:  python3 server/build_api.py')
    if why:
        print('Building the data first: %s (under a minute)' % why, flush=True)
        sys.path.insert(0, HERE)
        import build_api
        build_api.main()
    with open(PIDF, 'w') as f: f.write(str(os.getpid()))
    servers = []
    for cls, host in ((http.server.ThreadingHTTPServer, '127.0.0.1'), (V6, '::1')):
        try:
            servers.append(cls((host, PORT), Handler))
        except OSError as e:
            if host == '127.0.0.1':
                sys.exit('Port %d is taken (%s). Is the server already running?' % (PORT, e))
    for s in servers[1:]:
        threading.Thread(target=s.serve_forever, daemon=True).start()
    print('wya?! data server on http://localhost:%d/v1/manifest.json  (Ctrl-C to stop)' % PORT, flush=True)
    try:
        servers[0].serve_forever()
    except KeyboardInterrupt:
        pass

if __name__ == '__main__':
    main()
