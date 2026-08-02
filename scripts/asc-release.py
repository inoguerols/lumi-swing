#!/usr/bin/env python3
"""Release a App Store sin abrir App Store Connect.

Engancha la última build VALID de TestFlight a la versión editable y la envía
a revisión. Xcode Cloud ya sube la build en cada push a main; esto es el último
tramo, pensado para ejecutarse tal cual (sin cd, python3 del sistema):

    python3 "…/Pendulo/scripts/asc-release.py" --status
    python3 "…/Pendulo/scripts/asc-release.py" --whats-new "Texto de novedades" [--whats-new-en "…"]

Sin --whats-new solo tiene sentido para la 1.0 (App Store no admite novedades
en la primera versión). Credenciales: ~/.appstoreconnect/asc-api-key.json
(key_id + issuer_id + key), la misma que usa fastlane.
"""
import argparse, json, pathlib, subprocess, sys, time

# ponytail: bootstrap de dependencias en el python del sistema; un venv
# dedicado no sobrevive a las sesiones y complica el permiso de ejecución.
try:
    import jwt, requests
except ImportError:
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', '--user', '--quiet',
                           'pyjwt', 'cryptography', 'requests'])
    import jwt, requests

CRED = json.loads((pathlib.Path.home() / '.appstoreconnect/asc-api-key.json').read_text())
BASE = 'https://api.appstoreconnect.apple.com/v1'
BUNDLE = 'com.noguerol.lumiswing'
EDITABLES = {'PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'}


def hdrs():
    tok = jwt.encode({'iss': CRED['issuer_id'], 'iat': int(time.time()),
                      'exp': int(time.time()) + 900, 'aud': 'appstoreconnect-v1'},
                     CRED['key'], algorithm='ES256', headers={'kid': CRED['key_id']})
    return {'Authorization': f'Bearer {tok}', 'Content-Type': 'application/json'}


def get(path):
    r = requests.get(f'{BASE}{path}', headers=hdrs())
    r.raise_for_status()
    return r.json()


def call(method, path, payload):
    r = requests.request(method, f'{BASE}{path}', headers=hdrs(), data=json.dumps(payload))
    if not r.ok:
        print(f'FALLO {method} {path}: {r.status_code}')
        print(json.dumps(r.json(), indent=1, ensure_ascii=False))
        sys.exit(1)
    return r.json() if r.text else {}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--status', action='store_true', help='solo mostrar estado, sin tocar nada')
    p.add_argument('--whats-new', help='novedades (es-ES) de la versión')
    p.add_argument('--whats-new-en', help='novedades (en-US); si falta, se reusa --whats-new')
    p.add_argument('--min-build', type=int, default=0, help='exigir número de build mínimo')
    args = p.parse_args()

    app_id = get(f'/apps?filter[bundleId]={BUNDLE}')['data'][0]['id']
    ver = get(f'/apps/{app_id}/appStoreVersions?limit=1')['data'][0]
    estado = ver['attributes'].get('appStoreState') or ver['attributes'].get('appVersionState')
    builds = get(f'/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5')['data']
    build = next((b for b in builds if b['attributes']['processingState'] == 'VALID'
                  and int(b['attributes']['version']) >= args.min_build), None)

    print(f"versión {ver['attributes']['versionString']} | estado: {estado}")
    print(f"última build VALID: {build['attributes']['version'] if build else 'ninguna'}")
    if args.status:
        return

    # TestFlight: asegurar que la build está en los grupos internos. Aunque el
    # grupo tenga acceso a todas las builds, la 3 no apareció hasta añadirla
    # a mano (2026-08-02); este POST es idempotente y cierra ese hueco.
    if build:
        for g in get(f'/betaGroups?filter[app]={app_id}')['data']:
            if g['attributes'].get('isInternalGroup'):
                requests.post(f"{BASE}/betaGroups/{g['id']}/relationships/builds", headers=hdrs(),
                              data=json.dumps({'data': [{'type': 'builds', 'id': build['id']}]}))
        print('build asegurada en los grupos internos de TestFlight')
    if estado not in EDITABLES:
        sys.exit(f'la versión no está editable ({estado}); crea antes la versión nueva en ASC')
    if not build:
        sys.exit('no hay build VALID que cumpla --min-build; espera a que TestFlight procese')

    if args.whats_new:
        for loc in get(f"/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")['data']:
            texto = args.whats_new if loc['attributes']['locale'].startswith('es') \
                else (args.whats_new_en or args.whats_new)
            call('PATCH', f"/appStoreVersionLocalizations/{loc['id']}",
                 {'data': {'type': 'appStoreVersionLocalizations', 'id': loc['id'],
                           'attributes': {'whatsNew': texto}}})
        print('novedades actualizadas (es + en)')

    call('PATCH', f"/appStoreVersions/{ver['id']}/relationships/build",
         {'data': {'type': 'builds', 'id': build['id']}})
    print('build', build['attributes']['version'], 'enganchada')

    abiertos = get(f'/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES')['data']
    sid = abiertos[0]['id'] if abiertos else call('POST', '/reviewSubmissions',
        {'data': {'type': 'reviewSubmissions', 'attributes': {'platform': 'IOS'},
                  'relationships': {'app': {'data': {'type': 'apps', 'id': app_id}}}}})['data']['id']
    if not get(f'/reviewSubmissions/{sid}/items')['data']:
        call('POST', '/reviewSubmissionItems', {'data': {'type': 'reviewSubmissionItems',
            'relationships': {'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': sid}},
                              'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': ver['id']}}}}})
    call('PATCH', f'/reviewSubmissions/{sid}',
         {'data': {'type': 'reviewSubmissions', 'id': sid, 'attributes': {'submitted': True}}})
    print('ENVIADO A REVISIÓN con build', build['attributes']['version'])


if __name__ == '__main__':
    main()
