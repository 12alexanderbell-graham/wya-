"""python3 server/test_app.py: the app server's rules, on a database in memory (nothing on disk is touched)"""
import os, sys, unittest
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import app


def call(method, path, token=None, body=None):
    h = {'Authorization': 'Bearer ' + token} if token else {}
    return app.handle(method, path, h, body)


class AppServer(unittest.TestCase):
    def setUp(self):
        app.reset_for_tests(':memory:')
        code, r = call('POST', '/v1/me', body={'name': '  Alex   B '})
        self.assertEqual(code, 201)
        self.user, self.tok = r['user'], r['token']
        self.assertEqual(r['name'], 'Alex B')

    def test_names(self):
        self.assertEqual(call('POST', '/v1/me', body={'name': ''})[0], 400)
        self.assertEqual(call('POST', '/v1/me', body={'name': 'x' * 51})[0], 400)
        self.assertEqual(call('POST', '/v1/me', body={'name': 'x' * 50})[0], 201)

    def test_who(self):
        self.assertEqual(call('GET', '/v1/me')[0], 401)
        self.assertEqual(call('GET', '/v1/me', 'nonsense')[0], 401)
        code, r = call('GET', '/v1/me', self.tok)
        self.assertEqual((code, r['user'], r['name']), (200, self.user, 'Alex B'))
        call('POST', '/v1/me/out', self.tok)
        self.assertEqual(call('GET', '/v1/me', self.tok)[0], 401)

    def test_ai_gate(self):
        self.assertEqual(app.ai_gate(None), (True, None))
        app.AI_DAILY = 2
        try:
            h = 'Bearer ' + self.tok
            self.assertEqual(app.ai_gate(h), (True, self.user))
            self.assertEqual(app.ai_gate(h), (True, self.user))
            self.assertEqual(app.ai_gate(h), (False, self.user))
        finally:
            app.AI_DAILY = 0

    def test_not_ours(self):
        self.assertIsNone(call('GET', '/v1/manifest.json'))

    def test_same_op_once(self):
        op = {'op': 'op-00000001', 'type': 'report', 'report': 'mistake', 'target': 'place:fr', 'words': 'wrong capital'}
        a = call('POST', '/v1/ops', self.tok, {'ops': [op]})[1]['results'][0]
        b = call('POST', '/v1/ops', self.tok, {'ops': [op]})[1]['results'][0]
        self.assertEqual(a['status'], 'ok')
        self.assertTrue(b['dup'])
        self.assertEqual(a['receipt'], b['receipt'])
        n = app.db().execute('SELECT COUNT(*) FROM reports').fetchone()[0]
        self.assertEqual(n, 1)

    def test_rejected_is_told(self):
        r = call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-00000002', 'type': 'report', 'report': 'nope', 'target': 'x'}]})
        self.assertEqual(r[1]['results'][0]['status'], 'rejected')
        r = call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'short', 'type': 'vote', 'feature': 'f'}]})
        self.assertEqual(r[1]['results'][0]['error'], 'op-id')

    def test_votes_floor(self):
        call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-vote-0001', 'type': 'vote', 'feature': 'solo', 'on': True}]})
        self.assertEqual(call('GET', '/v1/votes')[1]['votes'], {})
        for i in range(app.VOTE_FLOOR - 1):
            t = call('POST', '/v1/me', body={'name': 'v%d' % i})[1]['token']
            call('POST', '/v1/ops', t, {'ops': [{'op': 'op-vote-%04d' % i, 'type': 'vote', 'feature': 'solo', 'on': True}]})
        self.assertEqual(call('GET', '/v1/votes')[1]['votes'], {'solo': app.VOTE_FLOOR})
        # voting again changes the vote, never adds one
        call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-vote-9999', 'type': 'vote', 'feature': 'solo', 'on': False}]})
        self.assertEqual(call('GET', '/v1/votes')[1]['votes'], {})

    def test_merge(self):
        send = lambda oid, e: call('POST', '/v1/ops', self.tok, {'ops': [{'op': oid, 'type': 'merge', 'kind': 'stamps', 'obj': 'book', 'entries': e}]})
        send('op-stamp-001', {'stamps/fr': {'at': 10, 'v': {'visits': 1}}, 'stamps/de': {'at': 10, 'v': {'visits': 1}}})
        send('op-stamp-002', {'stamps/it': {'at': 11, 'v': {}}, 'stamps/fr': {'at': 5, 'v': {'old': True}},
                              'stamps/de': {'at': 12, 'gone': True}})
        book = call('GET', '/v1/changes?since=0', self.tok)[1]['changes'][-1]['body']
        self.assertEqual(set(book), {'stamps/fr', 'stamps/de', 'stamps/it'})
        self.assertNotIn('old', book['stamps/fr']['v'])     # the older change did not win
        self.assertTrue(book['stamps/de']['gone'])           # the later unstamp did
        self.assertEqual(send('op-stamp-003', {'x': {'at': 1}})[1]['results'][0]['status'], 'ok')
        r = call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-stamp-004', 'type': 'merge', 'kind': 'list', 'obj': 'b', 'entries': {}}]})
        self.assertEqual(r[1]['results'][0]['error'], 'object')

    def test_list_conflict_keeps_both(self):
        put = lambda oid, base, name: call('POST', '/v1/ops', self.tok, {'ops': [
            {'op': oid, 'type': 'put', 'kind': 'list', 'obj': 'L1', 'base': base, 'body': {'name': name}}]})[1]['results'][0]
        a = put('op-list-0001', None, 'Cafés')
        self.assertEqual(a['status'], 'ok')
        b = put('op-list-0002', a['rev'], 'Cafés 2')
        self.assertEqual(b['status'], 'ok')
        c = put('op-list-0003', a['rev'], 'Cafés from the other phone')   # changed from an old revision
        self.assertEqual(c['status'], 'conflict')
        self.assertEqual(c['body']['name'], 'Cafés 2')
        # a conflict is not kept as done: sent again from the new revision, it goes through
        d = call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-list-0003', 'type': 'put', 'kind': 'list', 'obj': 'L1',
                                                         'base': c['rev'], 'body': {'name': 'merged'}}]})[1]['results'][0]
        self.assertEqual(d['status'], 'ok')

    def test_delete_is_a_tombstone(self):
        r = call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-del-00001', 'type': 'put', 'kind': 'plan', 'obj': 'P1', 'body': {'n': 1}}]})
        rev = r[1]['results'][0]['rev']
        call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-del-00002', 'type': 'delete', 'kind': 'plan', 'obj': 'P1'}]})
        # an offline phone sending its old change cannot bring it back
        r = call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-del-00003', 'type': 'put', 'kind': 'plan', 'obj': 'P1', 'base': rev, 'body': {'n': 2}}]})
        self.assertEqual(r[1]['results'][0]['error'], 'deleted')
        ch = call('GET', '/v1/changes?since=%d' % rev, self.tok)[1]['changes']
        self.assertEqual([(c['obj'], c['deleted']) for c in ch], [('P1', True)])

    def test_changes_are_yours_only(self):
        call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-mine-0001', 'type': 'put', 'kind': 'tier', 'obj': 'T', 'body': {}}]})
        other = call('POST', '/v1/me', body={'name': 'Someone'})[1]['token']
        self.assertEqual(call('GET', '/v1/changes?since=0', other)[1]['changes'], [])

    def test_placepages(self):
        self.assertEqual(call('GET', '/v1/placepage/af-bamyan')[0], 404)
        self.assertEqual(call('POST', '/v1/placepage/af-bamyan', None, {'page': {'about': 'x'}})[0], 401)
        self.assertEqual(call('POST', '/v1/placepage/af-bamyan', self.tok, {'page': {'about': 'Valley'}})[0], 201)
        code, r = call('GET', '/v1/placepage/af-bamyan')
        self.assertEqual((code, r['source'], r['page']['about']), (200, 'ai', 'Valley'))
        self.assertEqual(call('POST', '/v1/placepage/af-bamyan', self.tok, {'page': {'about': 'Other'}})[0], 409)
        self.assertEqual(call('GET', '/v1/placepage/..%2Fetc')[0], 400)
        # any language, as the app keys it; through the queue too, and a second page for a place is refused
        self.assertEqual(call('GET', '/v1/placepage/af%7CB%C4%81my%C4%81n')[0], 404)
        ok = call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-page-0001', 'type': 'placepage', 'obj': 'af|Bāmyān', 'page': {'about': 'x'}}]})
        self.assertEqual(ok[1]['results'][0]['status'], 'ok')
        self.assertEqual(call('GET', '/v1/placepage/af%7CB%C4%81my%C4%81n')[1]['page'], {'about': 'x'})
        again = call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-page-0002', 'type': 'placepage', 'obj': 'af|Bāmyān', 'page': {'about': 'y'}}]})
        self.assertEqual(again[1]['results'][0]['error'], 'exists')

    def test_board_counts_only_server_verified(self):
        call('POST', '/v1/ops', self.tok, {'ops': [{'op': 'op-brd-00001', 'type': 'merge', 'kind': 'stamps', 'obj': 'book',
                                                     'entries': {'stamps/fr': {'at': 1, 'v': {'verified': True}}}}]})
        self.assertEqual(call('GET', '/v1/board')[1]['board'], [])
        app.db().execute("INSERT INTO verifications VALUES (?, 'fr', 'location', 1)", (self.user,))
        self.assertEqual(call('GET', '/v1/board')[1]['board'], [{'user': self.user, 'name': 'Alex B', 'verified': 1}])


class Proofs(unittest.TestCase):
    """the server's own look at a proof: a made-up country "zz", a square from 0 to 10 east and 40 to 50 north, with a
    hole from 4 to 6; region "ZZ1" is the same square"""
    def setUp(self):
        import gzip, json, tempfile
        app.reset_for_tests(':memory:')
        self.dir = tempfile.mkdtemp()
        topo = {'transform': {'scale': [1, 1], 'translate': [0, 40]},
                'arcs': [[[0, 0], [10, 0], [0, 10], [-10, 0], [0, -10]], [[4, 4], [2, 0], [0, 2], [-2, 0], [0, -2]]],
                'objects': {'ZZ1': {'type': 'Polygon', 'arcs': [[0], [1]]}}, 'units': []}
        for lvl in (1,):
            with gzip.open(os.path.join(self.dir, 'zz-%d.js.gz' % lvl), 'wt') as f:
                f.write('REGIONPUT("zz",%d,%s);' % (lvl, json.dumps(topo)))
        app.SHAPES = self.dir
        app._shapes.clear()
        r = call('POST', '/v1/me', body={'name': 'P'})[1]
        self.user, self.tok = r['user'], r['token']

    def send(self, oid, **op):
        op.update({'op': oid, 'type': 'verify'})
        return call('POST', '/v1/ops', self.tok, {'ops': [op]})[1]['results'][0]

    def test_country(self):
        self.assertEqual(self.send('op-ver-00001', ref='c:zz', how='here', lat=41, lon=1)['state'], 'verified')
        self.assertEqual(call('GET', '/v1/board')[1]['board'][0]['verified'], 1)
        r = self.send('op-ver-00002', ref='c:zz', how='library', lat=45, lon=5)     # in the hole
        self.assertEqual((r['state'], r['reason']), ('notAccepted', 'elsewhere'))
        self.assertEqual(self.send('op-ver-00003', ref='c:zz', how='here', lat=30, lon=1)['state'], 'notAccepted')

    def test_region_and_unknown(self):
        self.assertEqual(self.send('op-ver-00004', ref='r:ZZ1', how='camera', lat=49, lon=9, cc='zz', lvl=1)['state'], 'verified')
        self.assertEqual(self.send('op-ver-00005', ref='c:qq', how='here', lat=1, lon=1)['state'], 'device')
        self.assertEqual(self.send('op-ver-00006', ref='t:paris', how='here', lat=1, lon=1)['state'], 'device')
        # only countries the server verified count on the board, and regions don't
        self.assertEqual(call('GET', '/v1/board')[1]['board'], [])

    def test_by_hand_and_bad(self):
        self.assertEqual(self.send('op-ver-00007', ref='c:zz', how='documents')['state'], 'checking')
        self.assertEqual(self.send('op-ver-00008', ref='c:zz', how='here')['error'], 'point')
        self.assertEqual(self.send('op-ver-00009', ref='x', how='here', lat=1, lon=1)['error'], 'proof')


def _rsa(bits=1024):
    """a throwaway RSA key for the tests (Miller-Rabin primes; nothing like this is used outside tests)"""
    import random
    rnd = random.Random(146)

    def prime(b):
        while True:
            n = rnd.getrandbits(b) | (1 << (b - 1)) | 1
            if all(n % q for q in (3, 5, 7, 11, 13, 17, 19, 23, 29, 31)) and _mr(n, rnd):
                return n
    e = 65537
    while True:
        p_, q_ = prime(bits // 2), prime(bits // 2)
        phi = (p_ - 1) * (q_ - 1)
        if p_ != q_ and phi % e:
            return p_ * q_, e, pow(e, -1, phi)


def _mr(n, rnd, k=20):
    d, r = n - 1, 0
    while d % 2 == 0:
        d //= 2; r += 1
    for _ in range(k):
        a = rnd.randrange(2, n - 2)
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def _b64u(b):
    import base64
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode()


class Apple(unittest.TestCase):
    N, E, D = _rsa()

    def token(self, sub='apple-sub-1', aud='com.wya.app', exp=None, iss='https://appleid.apple.com', kid='k1', tamper=False):
        import hashlib, json, time
        h = _b64u(json.dumps({'alg': 'RS256', 'kid': kid}).encode())
        c = _b64u(json.dumps({'iss': iss, 'aud': aud, 'sub': sub, 'exp': exp or time.time() + 600}).encode())
        k = (self.N.bit_length() + 7) // 8
        t = app._SHA256_INFO + hashlib.sha256((h + '.' + c).encode()).digest()
        em = b'\x00\x01' + b'\xff' * (k - len(t) - 3) + b'\x00' + t
        sig = pow(int.from_bytes(em, 'big'), self.D, self.N).to_bytes(k, 'big')
        if tamper:
            c = _b64u(json.dumps({'iss': iss, 'aud': aud, 'sub': 'someone-else', 'exp': exp or time.time() + 600}).encode())
        return h + '.' + c + '.' + _b64u(sig)

    def setUp(self):
        import time
        app.reset_for_tests(':memory:')
        app.APPLE_AUD = 'com.wya.app'
        n = self.N.to_bytes((self.N.bit_length() + 7) // 8, 'big')
        app._apple_keys.update({'at': time.time(), 'keys': {'k1': {'kty': 'RSA', 'kid': 'k1', 'n': _b64u(n), 'e': _b64u(self.E.to_bytes(3, 'big'))}}})
        r = call('POST', '/v1/me', body={'name': 'Alex'})[1]
        self.user, self.tok = r['user'], r['token']

    def test_checks(self):
        self.assertEqual(app.apple_subject(self.token())[0], 'apple-sub-1')
        self.assertEqual(app.apple_subject(self.token(aud='other'))[1], 'aud')
        self.assertEqual(app.apple_subject(self.token(exp=1))[1], 'expired')
        self.assertEqual(app.apple_subject(self.token(iss='https://evil'))[1], 'iss')
        self.assertEqual(app.apple_subject(self.token(tamper=True))[1], 'signature')
        self.assertEqual(app.apple_subject(self.token(kid='nope'))[1], 'signature')
        self.assertEqual(app.apple_subject('a.b')[1], 'token')

    def test_link_then_new_phone(self):
        self.assertEqual(call('POST', '/v1/me/apple', self.tok, {'identityToken': self.token()})[0], 200)
        self.assertTrue(call('GET', '/v1/me', self.tok)[1]['apple'])
        code, r = call('POST', '/v1/apple', body={'identityToken': self.token()})
        self.assertEqual((code, r['user']), (200, self.user))
        self.assertEqual(call('GET', '/v1/me', r['token'])[1]['user'], self.user)
        # another identity cannot take the same Apple account
        other = call('POST', '/v1/me', body={'name': 'B'})[1]['token']
        self.assertEqual(call('POST', '/v1/me/apple', other, {'identityToken': self.token()})[1]['error'], 'linked-elsewhere')
        self.assertEqual(call('POST', '/v1/apple', body={'identityToken': self.token(sub='never')})[0], 404)

    def test_delete_everything(self):
        call('POST', '/v1/me/apple', self.tok, {'identityToken': self.token()})
        call('POST', '/v1/ops', self.tok, {'ops': [
            {'op': 'op-del-a0001', 'type': 'merge', 'kind': 'stamps', 'obj': 'book', 'entries': {'stamps/fr': {'at': 1, 'v': {}}}},
            {'op': 'op-del-a0002', 'type': 'report', 'report': 'mistake', 'target': 'place:fr', 'words': 'x'},
            {'op': 'op-del-a0003', 'type': 'placepage', 'obj': 'fr|Lyon', 'page': {'about': 'y'}}]})
        self.assertEqual(call('POST', '/v1/me/delete', self.tok)[0], 200)
        self.assertEqual(call('GET', '/v1/me', self.tok)[0], 401)
        c = app.db()
        self.assertEqual(c.execute('SELECT COUNT(*) FROM objects').fetchone()[0], 0)
        self.assertEqual(c.execute('SELECT user FROM reports').fetchone()[0], 'deleted')
        self.assertEqual(c.execute('SELECT by_user FROM placepages').fetchone()[0], 'deleted')
        # Apple brings nobody back
        self.assertEqual(call('POST', '/v1/apple', body={'identityToken': self.token()})[0], 404)


if __name__ == '__main__':
    unittest.main()
