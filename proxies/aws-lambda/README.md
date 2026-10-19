# Proxy de referencia de nativ_maps en AWS Lambda

Una app Flutter con `ProxyCredentials` no habla con AWS: le manda cada petición
de Amazon Location a este servidor. La función comprueba quién es el usuario de
la app, firma la petición con SigV4, la reenvía a Amazon Location y devuelve la
respuesta tal cual llegó. El móvil nunca tiene un secreto de AWS.

Es el mismo proxy que el de [`../node`](../node), adaptado a una **Lambda
Function URL**. El contrato que cumplen todos los proxies de referencia está en
`doc/PROXY.md`.

## Por qué en Lambda no hay claves

En cualquier otro servidor alguien tiene que guardar un `AWS_ACCESS_KEY_ID` y
su secreto: en un `.env`, en un gestor de secretos o en la configuración del
contenedor. En Lambda no existen. La función se ejecuta con un **rol de
ejecución**, Lambda le inyecta credenciales temporales que caducan solas y la
cadena de credenciales por defecto del SDK las recoge. Lo que hay que proteger
pasa a ser una política de IAM, no un secreto.

Esa política, en [`template.yaml`](template.yaml), permite exactamente lo que
usa el paquete y nada más:

| Familia | Acciones | Recurso |
|---|---|---|
| Places | las 7 de `geo-places` (`Suggest`, `SearchText`, `GetPlace`…) | `arn:aws:geo-places:{región}::provider/default` |
| Routes | las 5 de `geo-routes` | `arn:aws:geo-routes:{región}::provider/default` |
| Maps | `geo-maps:GetTile` y `geo-maps:GetStaticMap` | `arn:aws:geo-maps:{región}::provider/default` |
| Geovallas | las 11 que nombran una colección | `geofence-collection/*` de tu cuenta y región |
| Rastreo | las 14 que nombran un rastreador | `tracker/*` de tu cuenta y región |
| Listados | `geo:ListGeofenceCollections`, `geo:ListTrackers` | `*`, porque no nombran ningún recurso |

Los glifos, los sprites y el descriptor de estilo no necesitan permiso.

## Cómo comparte el núcleo con el proxy de Node

El comportamiento está en un solo sitio: [`../node/proxy.mjs`](../node/proxy.mjs).
Este proxy **no tiene una copia**:

- [`src/index.mjs`](src/index.mjs) importa `../../node/proxy.mjs` directamente
  y solo hace de adaptador: convierte el evento de la Function URL en la
  petición que espera el núcleo, y la respuesta del núcleo en lo que espera
  Lambda.
- [`build.mjs`](build.mjs) empaqueta con esbuild el adaptador, el núcleo y sus
  dependencias en **un único archivo**, `dist/index.mjs`. Ese archivo es lo que
  se despliega y lo que prueba `local.mjs`.
- Antes de empaquetar, `build.mjs` compara las versiones de las dependencias de
  `../node/package.json` con las de aquí. Si alguien cambia una allí y no aquí,
  la compilación se para en vez de desplegar un firmante distinto del del proxy
  de Node.

¿Por qué empaquetar y no declarar `"nativ-maps-proxy-node": "file:../node"`
como dependencia? Porque npm y pnpm resuelven esa dependencia de formas
distintas: npm la enlaza y pnpm hace una copia en el momento de instalar, que
puede quedarse atrás. Y porque `sam build` copia la carpeta de la función a otro
sitio, donde la ruta relativa ya no apunta a nada. El paquete autocontenido evita
todo eso. Tampoco depende de la versión del SDK de AWS que trae el runtime de
Lambda, que cambia sin avisar.

## Requisitos

- **Node.js 20 o superior** para compilar (en Lambda corre en `nodejs22.x`,
  arm64).
- `npm` o `pnpm` para instalar las dependencias de compilación.
- **AWS SAM CLI** para desplegar, y una cuenta de AWS con permiso para crear
  pilas de CloudFormation, funciones y roles.

## Variables

Son las mismas en todos los proxies de referencia.

| Variable | Obligatoria | Qué es |
|---|---|---|
| `PROXY_TOKEN` | sí | Comprobación de usuario de demostración: la app manda `Authorization: Bearer {PROXY_TOKEN}` y se compara en tiempo constante. **En producción, sustitúyela** (ver más abajo) |
| `PROXY_BASE_PATH` | no, `/geo` | La ruta bajo la que escucha. Cualquier otra ruta da `404` |
| `PROXY_PUBLIC_URL` | no | La URL pública del proxy, para reescribir el descriptor de estilo. Por defecto, `https://{dominio de la Function URL}{PROXY_BASE_PATH}`. Hace falta detrás de CloudFront o de un dominio propio |
| `AWS_REGION` | la pone Lambda | La región de las peticiones del mapa, que no traen cabeceras `X-Nativ-*` |
| `ALS_API_KEY` | no | Una clave de API de Amazon Location para Places, Routes y Maps. En Lambda **no hace falta**: el rol ya firma, y una clave es un secreto más que guardar. Geovallas y rastreo firman siempre con el rol |

Credenciales de AWS: ninguna. En Lambda las pone el rol de ejecución; en local,
las que haya en tu entorno (variables, perfil).

En el registro solo aparece `MÉTODO ruta → estado`: ni la consulta, que puede
llevar datos del usuario, ni las cabeceras, que llevan su token. Si la firma
falla antes de enviar —sin rol, sin credenciales—, se registra el tipo de error
y la app recibe un `500`.

## Compilar

```sh
cd proxies/aws-lambda
npm ci
npm run build        # → dist/index.mjs (≈750 KiB) y dist/package.json
```

Hay que volver a compilar cada vez que cambie `../node/proxy.mjs`.

## Probar en local

[`local.mjs`](local.mjs) es un servidor `node:http` mínimo que convierte cada
petición en el evento que mandaría una Function URL (formato 2.0), llama al
`handler` **compilado** de `dist/index.mjs` y escribe la respuesta como lo haría
la Function URL: decodifica el base64, responde `502` si la función lanza una
excepción o si la respuesta pasa de 6 MB. No forma parte del despliegue.

```sh
npm run build
PORT=8086 PROXY_TOKEN=token-de-prueba AWS_REGION=us-east-1 node local.mjs
```

Con eso, la prueba de conformidad —la misma para todos los proxies—, desde
`packages/nativ_maps`:

```sh
PROXY_URL=http://localhost:8086/geo PROXY_TOKEN=token-de-prueba \
  AWS_REGION=us-east-1 dart test -P proxy --reporter expanded
```

Son 26 pruebas. Para que pasen las cinco de geovallas y rastreo, las
credenciales que vea `local.mjs` tienen que poder crear y borrar colecciones y
rastreadores: la prueba crea `nativ-maps-proxy-…` y los borra al terminar.

Después de desplegar, la misma prueba contra la URL de verdad comprueba también
el rol:

```sh
PROXY_URL=https://abc123.lambda-url.us-east-1.on.aws/geo PROXY_TOKEN=… \
  AWS_REGION=us-east-1 dart test -P proxy
```

## Desplegar con SAM

```sh
npm ci && npm run build
sam build
sam deploy --guided
```

`sam build` solo copia `dist/`: el paquete ya está hecho. `sam deploy --guided`
pregunta el nombre de la pila, la región y los parámetros:

| Parámetro | Qué poner |
|---|---|
| `ProxyToken` | Un token largo y aleatorio, por ejemplo `openssl rand -hex 32` (mínimo 16 caracteres). Es `NoEcho`: SAM lo pide sin mostrarlo y no lo guarda en `samconfig.toml` |
| `AlsApiKey` | Vacío |
| `ProxyBasePath` | `/geo`, salvo que quieras otra ruta |
| `ProxyPublicUrl` | Vacío, salvo que haya CloudFront o un dominio propio delante |

**Despliega en la misma región que pones en `NativMaps(region: …)`.** La
política solo permite la región de la pila; para otra, amplía las ARN de
`template.yaml`.

Al terminar, la pila devuelve:

| Salida | Ejemplo |
|---|---|
| `ProxyBaseUrl` | `https://abc123.lambda-url.us-east-1.on.aws/geo` |
| `StyleUrl` | `https://abc123.lambda-url.us-east-1.on.aws/geo/v2/styles/Standard/descriptor` |
| `FunctionUrl` | `https://abc123.lambda-url.us-east-1.on.aws/` |
| `RoleArn` | El rol que firma, por si hay que ampliarlo |

La Function URL es `AuthType: NONE` a propósito: la comprobación del usuario está
dentro de la función, antes de que nada llegue a Amazon Location. Desde octubre
de 2025, una Function URL pública necesita los permisos `lambda:InvokeFunctionUrl`
**y** `lambda:InvokeFunction`. SAM CLI genera los dos a partir de
`FunctionUrlConfig`, pero las versiones antiguas solo el primero, y la URL
respondería `403` a todo el mundo: por eso la plantilla declara además el
segundo. Con un SAM reciente queda repetido, sin efecto.

## Usarlo desde la app

```dart
final session = {'Authorization': 'Bearer $token'};

final maps = NativMaps(
  region: 'us-east-1',   // la de la pila
  credentials: ProxyCredentials(
    baseUrl: Uri.parse('https://abc123.lambda-url.us-east-1.on.aws/geo'),
    headers: session,
  ),
);

NativMap(
  // El paquete construye la URL del descriptor sobre el proxy.
  styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
  // MapLibre pide el estilo, las teselas, los glifos y los sprites con estas
  // cabeceras. Sin ellas, cada petición del mapa recibe un 401.
  customHeaders: session,
  initialCameraPosition: CameraPosition(target: LatLng(-0.18, -78.48), zoom: 13),
  onStyleError: (e) => debugPrint('$e'),   // un 401 aquí: faltan las cabeceras
);
```

El proxy reescribe el descriptor de estilo para que todas las teselas, glifos y
sprites apunten a él, y nunca le da al móvil una clave.

## API Gateway HTTP API

Si prefieres API Gateway (por un dominio propio, por WAF, por límites de
peticiones), una **HTTP API** con integración Lambda y **formato de carga 2.0**
manda el mismo evento: el `handler` sirve sin cambios. Dos detalles:

- Usa la etapa `$default`. Con una etapa con nombre, la ruta llega con la etapa
  delante (`/prod/geo/…`), y entonces `PROXY_BASE_PATH` tiene que ser
  `/prod/geo`.
- Con un dominio propio, pon `PROXY_PUBLIC_URL` (`https://maps.example.com/geo`).

No usa la REST API (formato 1.0), que manda otro evento.

## Costes y limitaciones

- **Cada petición es una invocación.** Mover el mapa pide decenas de teselas,
  y cada una cuesta una invocación más los milisegundos que la función pasa
  esperando a AWS. Las cabeceras `cache-control` y `etag` de AWS se devuelven
  tal cual, así que MapLibre cachea en el dispositivo y no vuelve a pedir lo
  que ya tiene. Antes de cachear teselas en CloudFront, lee la Sección 82 de los
  AWS Service Terms.
- **Arranque en frío.** La primera petición tras un rato sin tráfico paga el
  arranque de la función: típicamente unos cientos de milisegundos. El paquete
  se carga en unos 30 ms; el resto es Lambda y la primera conexión TLS con AWS.
  Si importa, `ProvisionedConcurrency` lo elimina, a cambio de pagar por tenerla
  caliente.
- **6 MB por respuesta.** Es el límite de una Function URL en modo `BUFFERED`,
  y los cuerpos binarios viajan en base64, que ocupa un tercio más: en la
  práctica, unos 4,5 MB de imagen. Las teselas, los glifos y los sprites pesan
  decenas o cientos de KB; lo único que podría acercarse es un mapa estático
  satelital grande. Si una respuesta no cabe, la Function URL responde `502`, y
  `local.mjs` aplica el mismo límite para que se vea antes de desplegar.
- **30 s de tiempo máximo**, en `template.yaml`. El paquete deja de esperar a
  los 8 s por defecto; 30 s dejan margen si subes ese límite para una matriz o
  un `snapToRoads` largo, sin pagar por respuestas que ya nadie espera. Si la
  función se pasa, la Function URL responde `502`.
- **La URL es pública.** Quien la encuentre puede invocarla: un `401` no gasta
  nada de Amazon Location, pero sí una invocación de Lambda. Para acotarlo, pon
  `ReservedConcurrentExecutions` en la función, o CloudFront con AWS WAF
  delante.
- **El token de ejemplo hay que sustituirlo.** `PROXY_TOKEN` es un secreto
  compartido por todas las instalaciones de la app, y además cualquiera con
  `lambda:GetFunctionConfiguration` lo lee en claro. En producción, cambia
  `authorize` en `src/index.mjs` por la verificación de la sesión real de tu
  app —el JWT de Cognito, Firebase o tu backend, comprobado con su JWKS—, y
  manda ese token en `headers` y `customHeaders`.
- **KMS.** Si creas colecciones o rastreadores con `kmsKeyId`, el rol necesita
  además permisos sobre esa clave: añádelos al rol de la salida `RoleArn`.
- **Detrás de CloudFront**, reenvía `Authorization` y las cabeceras
  `X-Nativ-Host`, `X-Nativ-Service` y `X-Nativ-Region`, no reenvíes `Host` (la
  Function URL lo rechaza) y pon `PROXY_PUBLIC_URL`.
- **El registro** se guarda 14 días en CloudWatch Logs (`ProxyLogs`).

## Archivos

| Archivo | Qué es |
|---|---|
| `src/index.mjs` | El adaptador de Lambda: evento 2.0 → núcleo → respuesta |
| `build.mjs` | Empaqueta todo en `dist/index.mjs` y comprueba las versiones |
| `local.mjs` | La Function URL en tu máquina, para la prueba de conformidad |
| `template.yaml` | La plantilla de SAM: función, Function URL, rol y registro |
| `dist/` | Lo que se despliega. No se sube al repositorio |
