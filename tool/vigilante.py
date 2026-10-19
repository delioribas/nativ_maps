"""Corre una prueba de integración y hace desde fuera lo que la prueba pide.

La prueba escribe órdenes en su salida —`CAPTURA:`, `GESTO:`, `RED:`,
`ROTAR:`; la lista está en `example/integration_test/completo_test.dart`— y
este script las cumple con `adb` o `simctl`. Lleva la cuenta de las que ya
cumplió y la sirve en `http://127.0.0.1:18300/hechas`, para que la prueba
espere a cada una en vez de suponer cuánto tarda: con esperas fijas, una
captura lenta dejaba en cola el toque siguiente y la prueba comprobaba antes
de que ocurriera.

    set -a; source .env; set +a
    ALS_API_KEY="$ALS_SERVER" python3 tool/vigilante.py \\
        android emulator-5554 completo_test.dart /tmp/capturas

Por un proxy, sin clave en la app: `PROXY_URL=http://10.0.2.2:8080/geo` y
`PROXY_TOKEN=…` en lugar de `ALS_API_KEY`. La clave nunca se escribe en el
registro.
"""
import os
import re
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

plataforma, dispositivo, prueba, salida = sys.argv[1:5]
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADB = os.path.expanduser('~/Library/Android/sdk/platform-tools/adb')
FLUTTER = os.path.join(REPO, '.fvm', 'flutter_sdk', 'bin', 'flutter')
os.makedirs(salida, exist_ok=True)

clave = os.environ.get('ALS_API_KEY', '')
region = os.environ.get('ALS_REGION', 'us-east-1')
proxy = os.environ.get('PROXY_URL')
if not clave and not proxy:
    sys.exit('Falta ALS_API_KEY o PROXY_URL.')

ORDEN = re.compile(r'(CAPTURA|GESTO|RED|ROTAR): ')

# Las órdenes ya cumplidas. La prueba la consulta y espera a que alcance la
# suya; en iOS cuenta también las que aquí no se pueden hacer, para que la
# cuenta de los dos lados nunca se desacompase.
hechas = 0


class Contador(BaseHTTPRequestHandler):
    def do_GET(self):
        cuerpo = str(hechas).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.send_header('Content-Length', str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def log_message(self, *args):
        pass


servidor = ThreadingHTTPServer(('127.0.0.1', 18300), Contador)
threading.Thread(target=servidor.serve_forever, daemon=True).start()


def adb(*args):
    subprocess.run([ADB, '-s', dispositivo, *args], capture_output=True)


def capturar(nombre):
    destino = os.path.join(salida, f'{nombre}.png')
    if plataforma == 'android':
        with open(destino, 'wb') as f:
            subprocess.run([ADB, '-s', dispositivo, 'exec-out', 'screencap', '-p'], stdout=f)
    else:
        subprocess.run(['xcrun', 'simctl', 'io', dispositivo, 'screenshot', destino],
                       capture_output=True)


def cumplir(linea):
    if m := re.search(r'CAPTURA: (\S+)', linea):
        # Un segundo para que se asiente lo último que se pidió.
        time.sleep(1)
        capturar(m.group(1))
        return f'capturada {m.group(1)}'
    if plataforma != 'android':
        return None
    if m := re.search(r'GESTO: (toque|mantener) (\d+) (\d+)', linea):
        tipo, x, y = m.groups()
        if tipo == 'toque':
            adb('shell', 'input', 'tap', x, y)
        else:
            adb('shell', 'input', 'swipe', x, y, x, y, '1000')
        return f'gesto {tipo} {x} {y}'
    if m := re.search(r'GESTO: arrastrar (\d+) (\d+) (\d+) (\d+) (\d+)', linea):
        # Sin esperar a que acabe: la prueba mira a mitad del movimiento.
        subprocess.Popen([ADB, '-s', dispositivo, 'shell', 'input', 'swipe', *m.groups()])
        return 'gesto arrastrar ' + ' '.join(m.groups())
    if m := re.search(r'RED: (on|off)', linea):
        adb('shell', 'cmd', 'connectivity', 'airplane-mode',
            'enable' if m.group(1) == 'off' else 'disable')
        return f'red {m.group(1)}'
    if m := re.search(r'ROTAR: (horizontal|vertical)', linea):
        adb('shell', 'settings', 'put', 'system', 'accelerometer_rotation', '0')
        adb('shell', 'settings', 'put', 'system', 'user_rotation',
            '1' if m.group(1) == 'horizontal' else '0')
        return f'girada {m.group(1)}'
    return None


comando = [
    FLUTTER, 'test', f'integration_test/{prueba}', '-d', dispositivo,
    f'--dart-define=ALS_REGION={region}',
] + ([f'--dart-define=ALS_PROXY_URL={proxy}',
      f'--dart-define=ALS_PROXY_TOKEN={os.environ.get("PROXY_TOKEN", "")}']
     if proxy else [f'--dart-define=ALS_API_KEY={clave}'])

registro = open(os.path.join(salida, 'registro.log'), 'w')
proceso = subprocess.Popen(comando, cwd=os.path.join(REPO, 'example'),
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, bufsize=1)
for linea in proceso.stdout:
    if clave:
        linea = linea.replace(clave, '<CLAVE>')
    registro.write(linea)
    registro.flush()
    hecho = cumplir(linea)
    if ORDEN.search(linea):
        hechas += 1
    if hecho:
        print(hecho, flush=True)
    elif re.search(r'ERROR_VISIBLE|FALLO:|AVISO:|RESUMEN:|OMITIDO|EXCEPTION|'
                   r'All tests passed|Some tests failed', linea):
        print(linea.rstrip(), flush=True)
proceso.wait()
servidor.shutdown()
if plataforma == 'android':
    # Pase lo que pase, el emulador queda con red y en vertical.
    adb('shell', 'cmd', 'connectivity', 'airplane-mode', 'disable')
    adb('shell', 'settings', 'put', 'system', 'user_rotation', '0')
sys.exit(proceso.returncode)
