# Proxy de referencia en Node

El servidor al que llama una app que usa `ProxyCredentials`. Comprueba al
usuario de tu app, se autentica con Amazon Location —SigV4 con las
credenciales IAM del servidor, o una clave de API que no sale de él—, reenvía
la petición y devuelve la respuesta tal cual. El teléfono nunca tiene un
secreto de AWS.

Es la **referencia**: los de Go, Python, PHP y Java hacen exactamente lo mismo,
y el de AWS Lambda usa este mismo núcleo. El contrato está en
[doc/PROXY.md](../../doc/PROXY.md).

- `proxy.mjs`: el núcleo, sin framework. `createProxy(...)` devuelve una
  función que recibe la petición como valores y devuelve la respuesta.
- `server.mjs`: el servidor independiente, solo con `node:http`.

## Requisitos

- Node 20 o posterior.
- Credenciales de AWS con permiso para lo que vaya a usar la app:
  `geo-places:*`, `geo-routes:*` y `geo-maps:*` (salvo que uses
  `ALS_API_KEY`), y `geo:*` sobre tus colecciones y rastreadores para
  geovallas y rastreo, que **siempre** van firmados con SigV4. La política
  completa está en la sección 4 de [doc/PROXY.md](../../doc/PROXY.md).

## Variables

Las mismas en todos los proxies de referencia.

| Variable | Obligatoria | Por defecto | Qué es |
|---|---|---|---|
| `PROXY_TOKEN` | sí | — | El token de prueba: exige `Authorization: Bearer {PROXY_TOKEN}`. En producción, cámbialo por tu comprobación de sesión |
| `AWS_REGION` | sí | — | La región del mapa, cuyas peticiones no traen cabeceras `X-Nativ-*` |
| `PORT` | no | `8080` | Puerto |
| `PROXY_BASE_PATH` | no | `/geo` | El prefijo bajo el que escucha. Fuera de él, `404` |
| `PROXY_PUBLIC_URL` | no | se deduce de cada petición | La URL pública del proxy, p. ej. `https://api.tuapp.com/geo`. Las URL del descriptor de estilo apuntan aquí. Ponla si hay un balanceador delante |
| `ALS_API_KEY` | no | — | Una clave de API de Amazon Location. Si está, Places, Routes y Maps la usan en lugar de SigV4. Nunca llega al teléfono |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`… | no | la cadena estándar de AWS | Las credenciales IAM. Sin ellas, el rol de la instancia, del contenedor o de la función |

Sin `PROXY_TOKEN` o sin `AWS_REGION`, no arranca.

## Arrancarlo

```sh
cd proxies/node
npm ci
PROXY_TOKEN=un-token-largo AWS_REGION=us-east-1 npm start
# nativ_maps proxy on :8080/geo
```

Y en la app:

```dart
final maps = NativMaps(
  region: 'us-east-1',
  credentials: ProxyCredentials(
    baseUrl: Uri.parse('https://api.tuapp.com/geo'),
    headers: {'Authorization': 'Bearer $sessionToken'},
  ),
);

NativMap(
  styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
  customHeaders: {'Authorization': 'Bearer $sessionToken'},
  ...
)
```

El registro solo dice `MÉTODO ruta → estado`. Nunca la consulta, que puede
llevar datos del usuario, ni las cabeceras, que llevan su token.

## Probarlo: la prueba de conformidad

Con el proxy en marcha, desde `packages/nativ_maps`:

```sh
PROXY_URL=http://localhost:8080/geo PROXY_TOKEN=un-token-largo \
AWS_REGION=us-east-1 dart test -P proxy --reporter expanded
```

Tienen que pasar las 26. La prueba crea una colección de geovallas y un
rastreador `nativ-maps-proxy-…` a través del proxy y los borra al terminar,
así que sus credenciales necesitan esos permisos.

## Dentro de Express, Fastify o NestJS

El núcleo no sabe de frameworks: recibe la petición como valores. Con lo que
ya tenga tu backend, se monta en un par de líneas. **La autorización es la
tuya**: el JWT, la cookie o la sesión que ya compruebas en el resto de la API.

```js
import { createProxy } from './proxy.mjs';

const handle = createProxy({
  region: 'us-east-1',
  // Tu comprobación de siempre. Devuelve false y no se reenvía nada.
  authorize: async (headers) => Boolean(await sessions.verify(headers.authorization)),
  apiKey: process.env.ALS_API_KEY,        // opcional
  publicUrl: 'https://api.tuapp.com/geo', // opcional
});
```

**Express** — el cuerpo, en bruto: sin `express.json()` en esta ruta.

```js
app.use('/geo', express.raw({ type: '*/*' }), async (req, res) => {
  const [path, query = ''] = req.url.split('?');
  const r = await handle({
    method: req.method,
    path,                        // ya sin '/geo': app.use lo quita
    query,
    headers: req.headers,
    body: req.body?.length ? req.body : undefined,
    origin: `${req.protocol}://${req.get('host')}/geo`,
  });
  res.status(r.status).set(r.headers).send(Buffer.from(r.body));
});
```

**Fastify**

```js
fastify.addContentTypeParser('*', { parseAs: 'buffer' }, (_, body, done) => done(null, body));
fastify.all('/geo/*', async (req, reply) => {
  const [path, query = ''] = req.url.slice('/geo'.length).split('?');
  const r = await handle({
    method: req.method, path, query, headers: req.headers,
    body: req.body?.length ? req.body : undefined,
    origin: `${req.protocol}://${req.hostname}/geo`,
  });
  reply.code(r.status).headers(r.headers).send(Buffer.from(r.body));
});
```

**NestJS** — con `rawBody: true` en `NestFactory.create`.

```ts
@Controller('geo')
export class GeoProxyController {
  @All('*')
  async forward(@Req() req: RawBodyRequest<Request>, @Res() res: Response) {
    const [path, query = ''] = req.url.slice('/geo'.length).split('?');
    const r = await handle({
      method: req.method, path, query, headers: req.headers,
      body: req.rawBody?.length ? req.rawBody : undefined,
      origin: `${req.protocol}://${req.get('host')}/geo`,
    });
    res.status(r.status).set(r.headers).send(Buffer.from(r.body));
  }
}
```

Dos cosas que un framework suele hacer y aquí estorban: **parsear el cuerpo**
—hay que reenviarlo byte a byte— y **comprimir la respuesta** con su propio
`content-encoding`, que está bien, siempre que no se lo aplique dos veces.

## Docker

```sh
docker build -t nativ-maps-proxy-node proxies/node
docker run -p 8080:8080 \
  -e PROXY_TOKEN=un-token-largo -e AWS_REGION=us-east-1 \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
  nativ-maps-proxy-node
```

En AWS —ECS, App Runner, EC2— no hacen falta las dos últimas: firma el rol.
