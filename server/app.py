"""The wya?! app server (row 146): who you are, what you have, and what the server decides.

It runs inside serve.py on the same port (http://localhost:8787), next to the data, while developing on this Mac.
Nothing here is tied to a provider: the same API moves to the real host later (its address changes, the paths don't).
Standard library only. The database is state.nosync/app.sqlite (.nosync: kept out of iCloud, each Mac its own).

What it does:
- WHO YOU ARE, WITH NO SIGN-UP WALL (D651): POST /v1/me {name} makes a stable WYA identity with the name you chose and
  gives the phone a secret token for it (only its hash is kept here). Every other call carries it as
  "Authorization: Bearer <token>". Linking Sign in with Apple to it comes later and keeps the same user.
- ONE SYNC QUEUE FOR EVERYTHING (15.2, 18.5): POST /v1/ops takes the phone's queued changes, each with its own op id.
  The same op sent twice is done once ("dup"), so a flaky connection never makes two of anything. A change the
  server will never take ("rejected", with why) is told apart from one to try again (any 5xx or no answer).
- WHAT YOU HAVE (18.6): your things are kept per object (kind + id) with a revision. Your stamp book, your lists and
  your profile merge thing by thing (a stamp, a list: the later of two changes of the same thing wins; nothing is lost
  because two phones changed different things). A single list, plan, tier list or book can also be
  taken whole when the phone changed it from the revision the server has; changed on two phones at once, the server
  keeps its own and says "conflict" with it, and the phone keeps its own as a copy: nothing is silently thrown away.
  Deleting leaves a tombstone, so a phone that was offline cannot bring it back. GET /v1/changes?since=N gives every
  object changed after revision N.
- COMING SOON VOTES (19.6, the first test of the queue): one vote per user per feature, on or off; the count is never
  shown until it is real (GET /v1/votes gives it only above a floor).
- REPORTS GET A RECEIPT (19.5): a report is stored with its kind (report, slop, mistake), what it is about and the
  words, and the phone is given a receipt id; only then does it say it was received.
- PLACE PAGES FOR EVERY PLACE ON EARTH: GET /v1/placepage/<id> is the page if there is one, 404 if nobody has made
  it yet; POST /v1/placepage/<id> keeps a page a user approved (made by the AI, so its source says so), for everyone
  from then on. One page per place; a second one for the same place is refused, not overwritten.
- THE LEADERBOARD IS THE SERVER'S (16.3, 19.3): GET /v1/board counts only stamps the server has verified
  (verifications table), never what a phone says about itself.
"""
import base64, gzip, hashlib, json, os, re, secrets, sqlite3, threading, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SHAPES = os.environ.get('WYA_SHAPES') or os.path.join(HERE, 'public.nosync', 'v1', 'shapes')
STATE = os.path.join(HERE, 'state.nosync')
DB_PATH = os.environ.get('WYA_APP_DB') or os.path.join(STATE, 'app.sqlite')

SCHEMA_VERSION = 3
NAME_MAX = 50                 # Q13
KINDS = {'list', 'plan', 'tier', 'book'}               # taken whole, with conflicts
MERGED = {'stamps', 'lists', 'profile'}                 # merged thing by thing (Sync.swift KeyedDoc on the phone)
REPORT_KINDS = {'report', 'slop', 'mistake'}
VOTE_FLOOR = 25               # a count is shown only once this many have voted (19.6: never an invented number)
BODY_MAX = 2_000_000          # one object, as JSON
OPS_MAX = 200                 # changes in one call

_lock = threading.Lock()
_db = None


def db():
    """the one connection (serve.py answers on threads; sqlite is told so, and every write holds _lock)"""
    global _db
    if _db is None:
        if DB_PATH != ':memory:':
            os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
        _db = sqlite3.connect(DB_PATH, check_same_thread=False, isolation_level=None)
        _db.row_factory = sqlite3.Row
        _db.execute('PRAGMA journal_mode=WAL')
        _db.execute('PRAGMA foreign_keys=ON')
        migrate(_db)
    return _db


def reset_for_tests(path=':memory:'):
    global _db, DB_PATH
    if _db is not None:
        _db.close()
    _db = None
    DB_PATH = path


def migrate(c):
    v = c.execute('PRAGMA user_version').fetchone()[0]
    if v < 1:
        c.executescript('''
        CREATE TABLE users (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, created REAL NOT NULL,
            apple_sub TEXT UNIQUE                         -- Sign in with Apple, once linked
        );
        CREATE TABLE sessions (
            token_hash TEXT PRIMARY KEY, user TEXT NOT NULL REFERENCES users(id),
            created REAL NOT NULL, revoked REAL
        );
        CREATE TABLE ops (                                -- every change taken, by its own id: the same one is done once
            user TEXT NOT NULL, op TEXT NOT NULL, at REAL NOT NULL, result TEXT NOT NULL,
            PRIMARY KEY (user, op)
        );
        CREATE TABLE objects (
            user TEXT NOT NULL, kind TEXT NOT NULL, obj TEXT NOT NULL,
            rev INTEGER NOT NULL, body TEXT, deleted INTEGER NOT NULL DEFAULT 0, updated REAL NOT NULL,
            PRIMARY KEY (user, kind, obj)
        );
        CREATE INDEX objects_rev ON objects(user, rev);
        CREATE TABLE revs (user TEXT PRIMARY KEY, rev INTEGER NOT NULL);
        CREATE TABLE votes (
            user TEXT NOT NULL, feature TEXT NOT NULL, on_ INTEGER NOT NULL, at REAL NOT NULL,
            PRIMARY KEY (user, feature)
        );
        CREATE TABLE reports (
            id TEXT PRIMARY KEY, user TEXT NOT NULL, kind TEXT NOT NULL, target TEXT NOT NULL,
            words TEXT NOT NULL, at REAL NOT NULL, state TEXT NOT NULL DEFAULT 'received'
        );
        CREATE TABLE placepages (
            place TEXT PRIMARY KEY, body TEXT NOT NULL, source TEXT NOT NULL, by_user TEXT NOT NULL,
            at REAL NOT NULL
        );
        CREATE TABLE verifications (                      -- what the server decided, never what a phone says
            user TEXT NOT NULL, place TEXT NOT NULL, method TEXT NOT NULL, decided REAL NOT NULL,
            PRIMARY KEY (user, place)
        );
        PRAGMA user_version = 1;
        ''')
    if v < 2:
        c.executescript('''
        CREATE TABLE cases (                              -- every proof shown, and what became of it (19.3, 19.4)
            id TEXT PRIMARY KEY, user TEXT NOT NULL, ref TEXT NOT NULL, how TEXT NOT NULL,
            state TEXT NOT NULL,                          -- verified / notAccepted / checking (a person looks) / device
            reason TEXT, day TEXT, at REAL NOT NULL, decided REAL
        );
        CREATE INDEX cases_user ON cases(user, ref);
        PRAGMA user_version = 2;
        ''')
    if v < 3:
        c.executescript('''
        CREATE TABLE ai_use (user TEXT NOT NULL, day TEXT NOT NULL, n INTEGER NOT NULL, PRIMARY KEY (user, day));
        PRAGMA user_version = 3;
        ''')


# ---- who you are ----

def _hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def clean_name(n):
    if not isinstance(n, str):
        return None
    n = re.sub(r'\s+', ' ', n).strip()
    if not n or len(n) > NAME_MAX:
        return None
    return n


def make_me(body):
    name = clean_name(body.get('name'))
    if name is None:
        return 400, {'error': 'name', 'detail': 'a name of 1 to %d characters' % NAME_MAX}
    uid = 'u_' + secrets.token_hex(12)
    token = secrets.token_urlsafe(32)
    now = time.time()
    with _lock:
        c = db()
        c.execute('BEGIN')
        c.execute('INSERT INTO users(id, name, created) VALUES (?,?,?)', (uid, name, now))
        c.execute('INSERT INTO sessions(token_hash, user, created) VALUES (?,?,?)', (_hash(token), uid, now))
        c.execute('COMMIT')
    return 201, {'user': uid, 'name': name, 'token': token}


def who(auth_header):
    """the user a call is from, or None"""
    if not auth_header or not auth_header.startswith('Bearer '):
        return None
    row = db().execute('SELECT user FROM sessions WHERE token_hash=? AND revoked IS NULL',
                       (_hash(auth_header[7:].strip()),)).fetchone()
    return row['user'] if row else None


def me(user):
    r = db().execute('SELECT id, name, created, apple_sub IS NOT NULL AS apple FROM users WHERE id=?', (user,)).fetchone()
    return 200, {'user': r['id'], 'name': r['name'], 'created': r['created'], 'apple': bool(r['apple'])}


def rename(user, body):
    name = clean_name(body.get('name'))
    if name is None:
        return 400, {'error': 'name', 'detail': 'a name of 1 to %d characters' % NAME_MAX}
    with _lock:
        db().execute('UPDATE users SET name=? WHERE id=?', (name, user))
    return 200, {'name': name}


def sign_out(user, auth_header):
    with _lock:
        db().execute('UPDATE sessions SET revoked=? WHERE token_hash=?', (time.time(), _hash(auth_header[7:].strip())))
    return 200, {'ok': True}


# ---- Sign in with Apple, linked to the identity you already have (D651: "later linked/upgraded ... without losing
# continuity"; 19.2: provider tokens verified by the backend, no provider secret on the phone) ----

APPLE_ISS = 'https://appleid.apple.com'
APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys'
# the app's bundle id, which Apple puts in the token's "aud": WYA_APPLE_AUD, else secret.nosync/apple-aud.txt beside this
def _aud():
    try:
        with open(os.path.join(HERE, 'secret.nosync', 'apple-aud.txt')) as f:
            return f.read().strip()
    except OSError:
        return ''
APPLE_AUD = os.environ.get('WYA_APPLE_AUD') or _aud()
_apple_keys = {'at': 0, 'keys': {}}


def _b64(s):
    return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))


def apple_keys():
    """Apple's public keys by kid, fetched at most once an hour (tests set _apple_keys themselves)"""
    if time.time() - _apple_keys['at'] > 3600 or not _apple_keys['keys']:
        req = urllib.request.Request(APPLE_KEYS_URL, headers={'User-Agent': 'wya-app-data/1.0'})
        with urllib.request.urlopen(req, timeout=10) as f:
            ks = json.loads(f.read().decode())['keys']
        _apple_keys['keys'] = {k['kid']: k for k in ks if k.get('kty') == 'RSA'}
        _apple_keys['at'] = time.time()
    return _apple_keys['keys']


# the DER prefix of a SHA-256 DigestInfo (RFC 8017 9.2)
_SHA256_INFO = bytes.fromhex('3031300d060960864801650304020105000420')


def rs256_ok(signing_input, sig, jwk):
    """RSASSA-PKCS1-v1_5 with SHA-256, checked with the standard library alone"""
    n = int.from_bytes(_b64(jwk['n']), 'big')
    e = int.from_bytes(_b64(jwk['e']), 'big')
    k = (n.bit_length() + 7) // 8
    if len(sig) != k:
        return False
    m = pow(int.from_bytes(sig, 'big'), e, n).to_bytes(k, 'big')
    t = _SHA256_INFO + hashlib.sha256(signing_input).digest()
    expected = b'\x00\x01' + b'\xff' * (k - len(t) - 3) + b'\x00' + t
    return secrets.compare_digest(m, expected)


def apple_subject(token, aud=None, now=None):
    """the Apple user an identity token is for, or (None, why)"""
    aud = APPLE_AUD if aud is None else aud
    try:
        h64, p64, s64 = token.split('.')
        head, claims = json.loads(_b64(h64)), json.loads(_b64(p64))
    except Exception:
        return None, 'token'
    if head.get('alg') != 'RS256':
        return None, 'alg'
    try:
        key = apple_keys().get(head.get('kid'))
    except Exception:
        return None, 'apple-unreachable'
    if not key or not rs256_ok((h64 + '.' + p64).encode(), _b64(s64), key):
        return None, 'signature'
    if claims.get('iss') != APPLE_ISS:
        return None, 'iss'
    if not aud or claims.get('aud') != aud:
        return None, 'aud'
    if float(claims.get('exp', 0)) < (now or time.time()):
        return None, 'expired'
    sub = claims.get('sub')
    return (sub, None) if isinstance(sub, str) and sub else (None, 'sub')


def link_apple(user, body):
    """this identity, signed in with Apple: from now on Apple brings you back to it on any phone"""
    sub, why = apple_subject(body.get('identityToken') or '')
    if not sub:
        return 401 if why != 'apple-unreachable' else 503, {'error': why}
    with _lock:
        c = db()
        other = c.execute('SELECT id FROM users WHERE apple_sub=?', (sub,)).fetchone()
        if other and other['id'] != user:
            # that Apple account already has its identity: the phone signs in to it instead (POST /v1/apple)
            return 409, {'error': 'linked-elsewhere'}
        c.execute('UPDATE users SET apple_sub=? WHERE id=?', (sub, user))
    return 200, {'apple': True}


def sign_in_apple(body):
    """a new phone, or one that was reset: Apple's word gives back the identity linked to it, with a new token"""
    sub, why = apple_subject(body.get('identityToken') or '')
    if not sub:
        return 401 if why != 'apple-unreachable' else 503, {'error': why}
    with _lock:
        c = db()
        row = c.execute('SELECT id, name FROM users WHERE apple_sub=?', (sub,)).fetchone()
        if not row:
            return 404, {'error': 'not-linked'}
        token = secrets.token_urlsafe(32)
        c.execute('INSERT INTO sessions(token_hash, user, created) VALUES (?,?,?)', (_hash(token), row['id'], time.time()))
    return 200, {'user': row['id'], 'name': row['name'], 'token': token}


def delete_me(user):
    """DELETE EVERYTHING (23.9): your things, votes, proofs and sessions go; a report you made stays for the people
    who act on it, with nothing left that says it was you; a place page you added stays everyone's, with nobody's name
    on it"""
    with _lock:
        c = db()
        c.execute('BEGIN')
        for t in ('objects', 'ops', 'revs', 'votes', 'verifications', 'cases', 'ai_use', 'sessions'):
            c.execute('DELETE FROM %s WHERE user=?' % t, (user,))
        c.execute("UPDATE reports SET user='deleted' WHERE user=?", (user,))
        c.execute("UPDATE placepages SET by_user='deleted' WHERE by_user=?", (user,))
        c.execute('DELETE FROM users WHERE id=?', (user,))
        c.execute('COMMIT')
    return 200, {'deleted': True}


# ---- your things ----

def _next_rev(c, user):
    r = c.execute('SELECT rev FROM revs WHERE user=?', (user,)).fetchone()
    n = (r['rev'] if r else 0) + 1
    c.execute('INSERT INTO revs(user, rev) VALUES (?,?) ON CONFLICT(user) DO UPDATE SET rev=excluded.rev', (user, n))
    return n


def merge_entries(old, new):
    """a merged document's things, two phones' into one: every thing either has, the one changed later where both
    have it. Each is {"at": seconds, "v": value} or {"at": seconds, "gone": true} (a tombstone: a thing removed on one
    phone stays removed, unless changed again later somewhere)"""
    out = dict(old or {})
    for k, v in (new or {}).items():
        if not isinstance(v, dict):
            continue
        try: at = float(v.get('at', 0))
        except (TypeError, ValueError): continue
        o = out.get(k)
        if o is None or at >= float(o.get('at', 0)):
            out[k] = v
    return out


def _apply(c, user, op):
    """one change; returns the result to keep for its op id"""
    kind, obj = op.get('kind'), op.get('obj')
    t = op.get('type')
    if t == 'vote':
        f = op.get('feature')
        if not isinstance(f, str) or not f or len(f) > 80:
            return {'status': 'rejected', 'error': 'feature'}
        c.execute('INSERT INTO votes(user, feature, on_, at) VALUES (?,?,?,?) '
                  'ON CONFLICT(user, feature) DO UPDATE SET on_=excluded.on_, at=excluded.at',
                  (user, f, 1 if op.get('on') else 0, time.time()))
        return {'status': 'ok'}
    if t == 'report':
        k = op.get('report')
        target, words = op.get('target'), op.get('words', '')
        if k not in REPORT_KINDS or not isinstance(target, str) or not target or not isinstance(words, str) or len(words) > 4000:
            return {'status': 'rejected', 'error': 'report'}
        rid = 'r_' + secrets.token_hex(8)
        c.execute('INSERT INTO reports(id, user, kind, target, words, at) VALUES (?,?,?,?,?,?)',
                  (rid, user, k, target, words, time.time()))
        return {'status': 'ok', 'receipt': rid}
    if t == 'merge':
        entries = op.get('entries')
        if kind not in MERGED or not isinstance(obj, str) or not obj or len(obj) > 120 or not isinstance(entries, dict):
            return {'status': 'rejected', 'error': 'object'}
        cur = c.execute('SELECT body FROM objects WHERE user=? AND kind=? AND obj=?', (user, kind, obj)).fetchone()
        merged = merge_entries(json.loads(cur['body']) if cur and cur['body'] else {}, entries)
        raw = json.dumps(merged, separators=(',', ':'), ensure_ascii=False)
        if len(raw) > BODY_MAX:
            return {'status': 'rejected', 'error': 'too-big'}
        rev = _next_rev(c, user)
        c.execute('INSERT INTO objects(user, kind, obj, rev, body, deleted, updated) VALUES (?,?,?,?,?,0,?) '
                  'ON CONFLICT(user, kind, obj) DO UPDATE SET rev=excluded.rev, body=excluded.body, deleted=0, updated=excluded.updated',
                  (user, kind, obj, rev, raw, time.time()))
        return {'status': 'ok', 'rev': rev}
    if t == 'verify':
        return verify(c, user, op)
    if t == 'placepage':
        code, out = _keep_page(c, user, op.get('obj'), op.get('page'))
        if code == 201:
            return {'status': 'ok'}
        # somebody kept a page for it first: theirs stands, this one stays on the phone (not an error to retry)
        return {'status': 'rejected', 'error': out.get('error', 'page')}
    if t in ('put', 'delete'):
        if kind not in KINDS or not isinstance(obj, str) or not obj or len(obj) > 120:
            return {'status': 'rejected', 'error': 'object'}
        cur = c.execute('SELECT rev, body, deleted FROM objects WHERE user=? AND kind=? AND obj=?', (user, kind, obj)).fetchone()
        base = op.get('base')            # the revision the phone changed it from (None: new on the phone)
        if t == 'delete':
            rev = _next_rev(c, user)
            c.execute('INSERT INTO objects(user, kind, obj, rev, body, deleted, updated) VALUES (?,?,?,?,NULL,1,?) '
                      'ON CONFLICT(user, kind, obj) DO UPDATE SET rev=excluded.rev, body=NULL, deleted=1, updated=excluded.updated',
                      (user, kind, obj, rev, time.time()))
            return {'status': 'ok', 'rev': rev}
        body = op.get('body')
        raw = json.dumps(body, separators=(',', ':'), ensure_ascii=False)
        if len(raw) > BODY_MAX:
            return {'status': 'rejected', 'error': 'too-big'}
        if cur is not None and not cur['deleted'] and base != cur['rev']:
            # changed on another phone since this one last had it: the server keeps its own, the phone keeps a copy
            return {'status': 'conflict', 'rev': cur['rev'], 'body': json.loads(cur['body'])}
        elif cur is not None and cur['deleted']:
            return {'status': 'rejected', 'error': 'deleted'}
        rev = _next_rev(c, user)
        c.execute('INSERT INTO objects(user, kind, obj, rev, body, deleted, updated) VALUES (?,?,?,?,?,0,?) '
                  'ON CONFLICT(user, kind, obj) DO UPDATE SET rev=excluded.rev, body=excluded.body, deleted=0, updated=excluded.updated',
                  (user, kind, obj, rev, raw, time.time()))
        return {'status': 'ok', 'rev': rev}
    return {'status': 'rejected', 'error': 'type'}


def take_ops(user, body):
    ops = body.get('ops')
    if not isinstance(ops, list) or len(ops) > OPS_MAX:
        return 400, {'error': 'ops'}
    results = []
    with _lock:
        c = db()
        for op in ops:
            oid = op.get('op') if isinstance(op, dict) else None
            if not isinstance(oid, str) or not (8 <= len(oid) <= 80):
                results.append({'op': oid, 'status': 'rejected', 'error': 'op-id'})
                continue
            done = c.execute('SELECT result FROM ops WHERE user=? AND op=?', (user, oid)).fetchone()
            if done:
                r = json.loads(done['result']); r['op'] = oid; r['dup'] = True
                results.append(r)
                continue
            c.execute('BEGIN')
            try:
                r = _apply(c, user, op)
                # a conflict is not kept as done: the phone sends it again once it has made its copy
                if r['status'] != 'conflict':
                    c.execute('INSERT INTO ops(user, op, at, result) VALUES (?,?,?,?)', (user, oid, time.time(), json.dumps(r)))
                c.execute('COMMIT')
            except Exception:
                c.execute('ROLLBACK')
                raise
            r = dict(r); r['op'] = oid
            results.append(r)
    return 200, {'results': results}


def changes(user, since):
    rows = db().execute('SELECT kind, obj, rev, body, deleted FROM objects WHERE user=? AND rev>? ORDER BY rev LIMIT 500',
                        (user, since)).fetchall()
    out = [{'kind': r['kind'], 'obj': r['obj'], 'rev': r['rev'], 'deleted': bool(r['deleted']),
            'body': json.loads(r['body']) if r['body'] else None} for r in rows]
    top = db().execute('SELECT rev FROM revs WHERE user=?', (user,)).fetchone()
    return 200, {'changes': out, 'rev': top['rev'] if top else 0, 'more': len(out) == 500}


# ---- the server's own check of a proof (row 139's "the server's check", 16.3: the board is the server's) ----

AUTO_WAYS = {'here', 'history', 'library', 'camera'}     # a point the phone read: the server looks at it again
BY_HAND = {'documents', 'other'}                          # a person looks (the file stays on the phone until the real host)
_shapes = {}


def _shape(cc, lvl):
    """a country's regions at a level, from the data server's own files: {id: [polygon, ...]}, each polygon its
    rings of (lon, lat), the first the outside; None when there is no such file"""
    key = (cc, lvl)
    if key in _shapes:
        return _shapes[key]
    path = os.path.join(SHAPES, '%s-%d.js.gz' % (cc, lvl))
    if not re.match(r'^[a-z0-9-]{2,12}$', cc) or not os.path.isfile(path):
        _shapes[key] = None
        return None
    with gzip.open(path, 'rt', encoding='utf-8') as f:
        s = f.read()
    t = json.loads(s[s.index('{'):s.rindex('}') + 1])
    (kx, ky), (tx, ty) = t['transform']['scale'], t['transform']['translate']
    arcs = []
    for a in t['arcs']:
        x = y = 0
        pts = []
        for dx, dy in a:
            x += dx; y += dy
            pts.append((x * kx + tx, y * ky + ty))
        arcs.append(pts)

    def ring(ids):
        out = []
        for i in ids:
            pts = arcs[i] if i >= 0 else arcs[~i][::-1]
            out.extend(pts if not out else pts[1:])
        return out

    shapes = {}
    for oid, g in t['objects'].items():
        polys = g['arcs'] if g['type'] == 'MultiPolygon' else [g['arcs']]
        shapes[oid] = [[ring(r) for r in poly] for poly in polys]
    _shapes[key] = shapes
    return shapes


def _in_ring(lon, lat, ring):
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]; xj, yj = ring[j]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def _in_polys(lon, lat, polys):
    return any(_in_ring(lon, lat, p[0]) and not any(_in_ring(lon, lat, h) for h in p[1:]) for p in polys)


def point_in(ref, lon, lat, cc=None, lvl=None):
    """is the point in the place? True / False, or None when the server has no shape to tell by"""
    if ref.startswith('c:'):
        sh = _shape(ref[2:].lower(), 1)
        if not sh:
            return None
        return any(_in_polys(lon, lat, polys) for polys in sh.values())
    if ref.startswith('r:') and isinstance(cc, str) and isinstance(lvl, int):
        sh = _shape(cc.lower(), lvl)
        if not sh or ref[2:] not in sh:
            return None
        return _in_polys(lon, lat, sh[ref[2:]])
    return None


def verify(c, user, op):
    ref, how = op.get('ref'), op.get('how')
    if not isinstance(ref, str) or not re.match(r'^[crtm]:.{1,120}$', ref) or how not in AUTO_WAYS | BY_HAND:
        return {'status': 'rejected', 'error': 'proof'}
    day = op.get('day') if isinstance(op.get('day'), str) else None
    reason = None
    if how in BY_HAND:
        state = 'checking'
    else:
        lat, lon = op.get('lat'), op.get('lon')
        if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)) or not (-90 <= lat <= 90 and -180 <= lon <= 180):
            return {'status': 'rejected', 'error': 'point'}
        ok = point_in(ref, float(lon), float(lat), op.get('cc'), op.get('lvl'))
        if ok is None:
            # nothing here to tell by (a town, a thing, a country with no shape on the server): the phone's word for
            # your own map, never the board's
            state = 'device'
        elif ok:
            state = 'verified'
        else:
            state, reason = 'notAccepted', 'elsewhere'
    now = time.time()
    cid = 'v_' + secrets.token_hex(8)
    c.execute('INSERT INTO cases(id, user, ref, how, state, reason, day, at, decided) VALUES (?,?,?,?,?,?,?,?,?)',
              (cid, user, ref, how, state, reason, day, now, None if state == 'checking' else now))
    if ref.startswith('c:'):
        if state == 'verified':
            c.execute('INSERT INTO verifications(user, place, method, decided) VALUES (?,?,?,?) '
                      'ON CONFLICT(user, place) DO UPDATE SET method=excluded.method, decided=excluded.decided',
                      (user, ref[2:].lower(), how, now))
    out = {'status': 'ok', 'case': cid, 'state': state}
    if reason:
        out['reason'] = reason
    return out


# ---- shared ----

def votes():
    rows = db().execute('SELECT feature, SUM(on_) AS n FROM votes GROUP BY feature').fetchall()
    return 200, {'votes': {r['feature']: r['n'] for r in rows if r['n'] >= VOTE_FLOOR}, 'floor': VOTE_FLOOR}


# a place's key as the app makes it ("af|Bamyan": its country and its name, any language); no slashes, no controls
PLACE_ID = re.compile(r'^[^/\\\x00-\x1f]{1,200}$')


def placepage(place):
    if not PLACE_ID.match(place):
        return 400, {'error': 'place'}
    r = db().execute('SELECT body, source, at FROM placepages WHERE place=?', (place,)).fetchone()
    if not r:
        return 404, {'error': 'no-page', 'place': place}
    return 200, {'place': place, 'page': json.loads(r['body']), 'source': r['source'], 'at': r['at']}


def _keep_page(c, user, place, page):
    """(status, result): a page a user approved, kept for everyone; one per place, a second refused"""
    if not isinstance(place, str) or not PLACE_ID.match(place):
        return 400, {'error': 'place'}
    if not isinstance(page, dict) or not page:
        return 400, {'error': 'page'}
    raw = json.dumps(page, separators=(',', ':'), ensure_ascii=False)
    if len(raw) > 200_000:
        return 413, {'error': 'too-big'}
    if c.execute('SELECT 1 FROM placepages WHERE place=?', (place,)).fetchone():
        return 409, {'error': 'exists', 'place': place}
    c.execute('INSERT INTO placepages(place, body, source, by_user, at) VALUES (?,?,?,?,?)',
              (place, raw, 'ai', user, time.time()))
    return 201, {'place': place}


def keep_placepage(user, place, body):
    with _lock:
        return _keep_page(db(), user, place, body.get('page'))


def board(limit=100):
    rows = db().execute('SELECT u.id, u.name, COUNT(v.place) AS n FROM users u JOIN verifications v ON v.user=u.id '
                        'GROUP BY u.id ORDER BY n DESC, MIN(v.decided) ASC LIMIT ?', (limit,)).fetchall()
    return 200, {'board': [{'user': r['id'], 'name': r['name'], 'verified': r['n']} for r in rows]}


# ---- the AI's gate (row 146): who asks, and how much a day ----

# questions a day for one identity; unset: no limit
AI_DAILY = int(os.environ.get('WYA_AI_DAILY') or 0)


def ai_gate(auth_header):
    """(allowed, user): a question from an identity is counted for its day; over the day's limit it is refused. A
    question with no identity is let through while developing (the app sends it once it has one)"""
    user = who(auth_header) if auth_header else None
    if user is None:
        return True, None
    day = time.strftime('%Y-%m-%d', time.gmtime())
    with _lock:
        c = db()
        row = c.execute('SELECT n FROM ai_use WHERE user=? AND day=?', (user, day)).fetchone()
        n = row['n'] if row else 0
        if AI_DAILY and n >= AI_DAILY:
            return False, user
        c.execute('INSERT INTO ai_use(user, day, n) VALUES (?,?,1) ON CONFLICT(user, day) DO UPDATE SET n=n+1', (user, day))
    return True, user


# ---- the door: serve.py hands every /v1/ call that is not a data file here ----

def handle(method, path, headers, body):
    """(status, dict) for an app call, or None when the path is not the app server's"""
    p = path.split('?', 1)[0]
    q = path.split('?', 1)[1] if '?' in path else ''
    if method == 'POST' and p == '/v1/me':
        return make_me(body or {})
    if method == 'POST' and p == '/v1/apple':
        return sign_in_apple(body or {})
    if p == '/v1/votes' and method == 'GET':
        return votes()
    if p == '/v1/board' and method == 'GET':
        return board()
    m = re.match(r'^/v1/placepage/([^/]+)$', p)
    place = urllib.parse.unquote(m.group(1)) if m else None
    if m and method == 'GET':
        return placepage(place)
    mine = p in ('/v1/me', '/v1/me/name', '/v1/me/out', '/v1/me/apple', '/v1/me/delete', '/v1/ops', '/v1/changes') \
        or (m and method == 'POST')
    if not mine:
        return None
    user = who(headers.get('Authorization'))
    if user is None:
        return 401, {'error': 'who'}
    if p == '/v1/me' and method == 'GET':
        return me(user)
    if p == '/v1/me/name' and method == 'POST':
        return rename(user, body or {})
    if p == '/v1/me/out' and method == 'POST':
        return sign_out(user, headers.get('Authorization'))
    if p == '/v1/me/apple' and method == 'POST':
        return link_apple(user, body or {})
    if p == '/v1/me/delete' and method == 'POST':
        return delete_me(user)
    if p == '/v1/ops' and method == 'POST':
        return take_ops(user, body or {})
    if p == '/v1/changes' and method == 'GET':
        mm = re.search(r'(?:^|&)since=(\d+)', q)
        return changes(user, int(mm.group(1)) if mm else 0)
    if m and method == 'POST':
        return keep_placepage(user, place, body or {})
    return 405, {'error': 'method'}
