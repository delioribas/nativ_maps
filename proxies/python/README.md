# Proxy de referencia en Python

El servidor al que llama una app que usa `ProxyCredentials`. Comprueba al
usuario de la app, se autentica con Amazon Location —SigV4 con las
credenciales de IAM del servidor, o una clave de API que solo vive aquí—,
reenvía la petición y devuelve la respuesta tal cual. **El teléfono nunca
tiene un secreto de AWS.**

Se comporta exactamente igual que el de Node (`proxies/node`); el contrato
completo está en `doc/PROXY.md`.

| Archivo | Qué es |
|---|---|
| `proxy.py` | El núcleo, sin framework: `handle(method, path, query, headers, body, origin)` → `(status, headers, body)` |
| `server.py` | Un servidor con solo la biblioteca estándar (`ThreadingHTTPServer`) |

## Requisitos

- Python **3.10** o superior.
- `botocore` (fijado en `requirements.txt`): firma SigV4 y la cadena de
  credenciales estándar de AWS. No hay más dependencias.

## Variables

Las mismas en todos los proxies de referencia.

| Variable | Obligatoria | Por defecto | Qué es |
|---|---|---|---|
| `PROXY_TOKEN` | **sí** | — | El token de prueba: la app manda `Authorization: Bearer <token>` |
| `AWS_REGION` | **sí** | — | La región de los mapas (el renderizador no manda cabeceras `X-Nativ-*`) |
| `PORT` | no | `8080` | Puerto |
| `PROXY_BASE_PATH` | no | `/geo` | Prefijo de las rutas; fuera de él, `404` |
| `PROXY_PUBLIC_URL` | no | se deduce de cada petición | La URL pública del proxy, p. ej. `https://api.miempresa.com/geo`. Detrás de un balanceador, ponla |
| `ALS_API_KEY` | no | — | Clave de API de Amazon Location. Si está, Places, Routes y Maps la usan en vez de SigV4. Geovallas y rastreo firman siempre |
| `AWS_ACCESS_KEY_ID`, `AWS_PROFILE`, rol… | según el caso | cadena estándar | Las credenciales de IAM, por la vía habitual de AWS |

Sin `PROXY_TOKEN` o sin `AWS_REGION`, no arranca.

## Arrancar

```sh
cd proxies/python
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
PROXY_TOKEN=… AWS_REGION=us-east-1 .venv/bin/python server.py
```

En el registro solo sale `MÉTODO ruta → estado`: nunca la consulta ni las
cabeceras, que llevan datos del usuario y su token.

**En producción** cambia `bearer_token(...)` en `server.py` por tu propia
comprobación de sesión (tu JWT, tu cookie): es una función que recibe las
cabeceras y devuelve `True` o `False`.

## Probarlo: la prueba de conformidad

Con el proxy en marcha, desde `packages/nativ_maps`:

```sh
PROXY_URL=http://localhost:8080/geo PROXY_TOKEN=… AWS_REGION=us-east-1 \
  dart test -P proxy --reporter expanded
```

Comprueba lo que tiene que rechazar, lo que reenvía el paquete y lo que pide
el renderizador del mapa. Crea y borra una colección de geovallas y un
rastreador, así que las credenciales necesitan permisos de geovallas y
rastreo.

## Dentro de FastAPI o Flask

El núcleo es el mismo; solo cambia cómo se le pasa la petición. Pásale la
ruta **sin decodificar**: decodificada, el `%2F` de un identificador de lugar
se convierte en `/`.

```python
import os
from proxy import bearer_token, create_proxy

handle = create_proxy(
    region=os.environ["AWS_REGION"],
    authorize=bearer_token(os.environ["PROXY_TOKEN"]),  # o tu comprobación de sesión
    api_key=os.environ.get("ALS_API_KEY") or None,
    public_url=os.environ.get("PROXY_PUBLIC_URL") or None,
)
METHODS = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]
```

FastAPI (el núcleo es síncrono: va al *threadpool* para no bloquear el bucle):

```python
from fastapi import FastAPI, Request, Response
from starlette.concurrency import run_in_threadpool

app = FastAPI()

@app.api_route("/geo/{rest:path}", methods=METHODS)
async def geo(rest: str, request: Request):
    r = await run_in_threadpool(
        handle,
        method=request.method,
        path=request.scope["raw_path"][len(b"/geo"):],
        query=request.url.query,
        headers=request.headers,
        body=await request.body(),
        origin=str(request.base_url).rstrip("/") + "/geo",
    )
    return Response(r.body, status_code=r.status, headers=r.headers)
```

Flask:

```python
from flask import Flask, Response, request

app = Flask(__name__)

@app.route("/geo/<path:rest>", methods=METHODS)
def geo(rest):
    raw = request.environ.get("RAW_URI") or request.path  # gunicorn y werkzeug dan RAW_URI
    r = handle(
        method=request.method,
        path=raw.split("?")[0][len("/geo"):],
        query=request.query_string.decode("utf-8", "replace"),
        headers=request.headers,
        body=request.get_data(),
        origin=request.host_url.rstrip("/") + "/geo",
    )
    return Response(r.body, status=r.status, headers=r.headers)
```

## Docker

El `Dockerfile` de esta carpeta (`python:3.12-slim`):

```sh
docker build -t nativ-maps-proxy-python proxies/python
docker run -p 8080:8080 -e PROXY_TOKEN=… -e AWS_REGION=us-east-1 \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY nativ-maps-proxy-python
```

En ECS, EKS o EC2 no pases claves: el rol de la tarea o de la instancia lo
recoge la cadena estándar.
