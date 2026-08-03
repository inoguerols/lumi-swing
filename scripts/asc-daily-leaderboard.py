#!/usr/bin/env python3
"""Alta del leaderboard diario `pendulo.diario` en App Store Connect (una vez).

Leaderboard RECURRENTE de 24 h desde medianoche UTC — el mismo reloj que rota
la semilla de DailyWorld. Idempotente: si el ID ya existe, no hace nada.

    python3 "…/Pendulo/scripts/asc-daily-leaderboard.py"

Credenciales: ~/.appstoreconnect/asc-api-key.json (las de asc-release.py).
No toca versiones ni revisiones: solo Game Center.
"""
import json, pathlib, subprocess, sys, time

# ponytail: bootstrap de dependencias en el python del sistema, como asc-release.py.
try:
    import jwt, requests
except ImportError:
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', '--user', '--quiet',
                           'pyjwt', 'cryptography', 'requests'])
    import jwt, requests

CRED = json.loads((pathlib.Path.home() / '.appstoreconnect/asc-api-key.json').read_text())
BASE = 'https://api.appstoreconnect.apple.com/v1'
BUNDLE = 'com.noguerol.lumiswing'
VENDOR_ID = 'pendulo.diario'


def hdrs():
    tok = jwt.encode({'iss': CRED['issuer_id'], 'iat': int(time.time()),
                      'exp': int(time.time()) + 900, 'aud': 'appstoreconnect-v1'},
                     CRED['key'], algorithm='ES256', headers={'kid': CRED['key_id']})
    return {'Authorization': f'Bearer {tok}', 'Content-Type': 'application/json'}


def get(path):
    r = requests.get(f'{BASE}{path}', headers=hdrs())
    r.raise_for_status()
    return r.json()


def post(path, payload):
    r = requests.post(f'{BASE}{path}', headers=hdrs(), data=json.dumps(payload))
    if not r.ok:
        print(f'FALLO POST {path}: {r.status_code}')
        print(json.dumps(r.json(), indent=1, ensure_ascii=False))
        sys.exit(1)
    return r.json()


def main():
    app_id = get(f'/apps?filter[bundleId]={BUNDLE}')['data'][0]['id']
    detail_id = get(f'/apps/{app_id}/gameCenterDetail')['data']['id']

    existing = get(f'/gameCenterDetails/{detail_id}/gameCenterLeaderboards?limit=50')['data']
    if any(l['attributes'].get('vendorIdentifier') == VENDOR_ID for l in existing):
        print(f'{VENDOR_ID} ya existe — nada que hacer.')
        return

    board = post('/gameCenterLeaderboards', {'data': {
        'type': 'gameCenterLeaderboards',
        'attributes': {
            'vendorIdentifier': VENDOR_ID,
            'referenceName': 'Mundo de hoy',
            'defaultFormatter': 'INTEGER',
            'submissionType': 'BEST_SCORE',
            'scoreSortType': 'DESC',
            'scoreRangeStart': '0',
            'scoreRangeEnd': '1000',
            # Recurrente: arranca la PRÓXIMA medianoche UTC (la API rechaza
            # inicios en pasado), dura 24 h y se repite a diario. El mundo
            # diario y el ranking rotan con el mismo reloj.
            'recurrenceStartDate': time.strftime('%Y-%m-%dT00:00:00Z',
                                                 time.gmtime(time.time() + 86400)),
            'recurrenceDuration': 'PT24H',
            'recurrenceRule': 'FREQ=DAILY;INTERVAL=1',
        },
        'relationships': {'gameCenterDetail': {
            'data': {'type': 'gameCenterDetails', 'id': detail_id}}},
    }})['data']
    board_id = board['id']
    print(f'Creado {VENDOR_ID} ({board_id})')

    for locale, name in (('es-ES', 'Mundo de hoy'), ('en-US', "Today's World")):
        post('/gameCenterLeaderboardLocalizations', {'data': {
            'type': 'gameCenterLeaderboardLocalizations',
            'attributes': {'locale': locale, 'name': name},
            'relationships': {'gameCenterLeaderboard': {
                'data': {'type': 'gameCenterLeaderboards', 'id': board_id}}},
        }})
        print(f'  localización {locale}: {name}')

    print('Hecho. Verifica en App Store Connect → Game Center.')


if __name__ == '__main__':
    main()
