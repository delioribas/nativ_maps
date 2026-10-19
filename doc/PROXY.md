# Proxy que firma: la clave nunca sale de tu servidor

> Con `ProxyCredentials`, la app no lleva **ningún secreto de AWS**. Habla con
> un servidor tuyo, y ese servidor es el que se autentica ante Amazon Location
> y reenvía. Este documento es el contrato que ese servidor tiene que cumplir,
> los servidores de referencia —Node, AWS Lambda, Go, Python, PHP y Java— y la
> prueba que dice si el tuyo lo cumple.

---

## 1 · Qué es, y cuándo usarlo

Un **proxy** es un intermediario: tu app le pide las cosas a él, y él se las
pide a AWS. Es el recepcionista que tiene la llave de la oficina: tú le das el
pedido, él entra, y la llave nunca sale de sus manos.

```
Sin proxy · ApiKeyCredentials
  App ──(la clave dentro del APK)──────────────────────────► AWS

Con proxy · ProxyCredentials
  App ──(token de tu usuario)──► Tu servidor ──(firma de AWS)──► AWS
      ◄──────── respuesta ────────            ◄─── respuesta ───
```

| | Clave de API en la app | **Proxy** | SigV4 en el móvil |
|---|---|---|---|
| Secreto en el teléfono | la clave, **extraíble en minutos** | **ninguno** | credenciales temporales (Cognito) |
| Quién puede gastar | cualquiera que la saque | solo tus usuarios con sesión | tus usuarios, sin límite propio |
| Operaciones | 17 (sin geovallas ni rastreo) | **las 44** | las 44 |
| Límites por usuario | no | **sí, los pones tú** | no |
| Cambiar la credencial | publicar otra versión | **sin tocar la app** | sin tocar la app |
| Lo que cuesta montarlo | nada | un endpoint | Cognito y políticas IAM |

**Recomendación:** clave de API para desarrollar; **proxy para producción**.

---

## 2 · En la app

```dart
final maps = NativMaps(
  region: 'us-east-1',
  credentials: ProxyCredentials(
    baseUrl: Uri.parse('https://api.miempresa.com/geo'),
    // El token de TU backend: el proxy comprueba con él que es un usuario tuyo.
    headers: {'Authorization': 'Bearer ${sesion.token}'},
  ),
);

NativMap(
  // Apunta al proxy por sí sola: styleDescriptorUrl usa el baseUrl de arriba.
  styleUrl: maps.maps.styleDescriptorUrl(MapStyle.standard)!,
  // El mapa pide el estilo y las teselas por su cuenta, con estas cabeceras.
  customHeaders: {'Authorization': 'Bearer ${sesion.token}'},
  initialCameraPosition: …,
)
```

- **`customHeaders` es imprescindible** con un proxy: sin él, el mapa pide el
  estilo sin token, el proxy responde `401` y el mapa sale en blanco.
- Las cabeceras van **solo** al host del `styleUrl` —tu proxy— y a
  `amazonaws.com`. Nunca a un tercero, aunque añadas teselas de otro sitio.
- Al renovar el token, basta con reconstruir el `NativMap` con las cabeceras
  nuevas: se vuelven a aplicar solas.
- Requiere **`nativ_maps_flutter` 0.9.1** o posterior. En la 0.9.0, Android no
  enviaba nunca las cabeceras del mapa y la primera petición del estilo salía
  siempre sin ellas.

---

## 3 · El contrato

Todo lo que el paquete manda por el proxy sigue estas reglas. Un servidor que
las cumple funciona con el paquete; uno que no, falla de formas difíciles de
diagnosticar.

### 3.1 · Qué le llega al proxy

```
{MÉTODO} {base}{ruta de AWS}?{consulta}
```

La ruta y la consulta son **las de AWS, tal cual**: si la app hace
`POST /v2/search-text`, al proxy le llega `POST /geo/v2/search-text`, con el
mismo cuerpo. Las peticiones del paquete traen además:

| Cabecera | Ejemplo | Para qué |
|---|---|---|
| `Authorization` | `Bearer eyJ…` | **tu** autenticación, la de tu backend |
| `X-Nativ-Host` | `cp.geofencing.geo.us-east-1.amazonaws.com` | a qué host de AWS reenviar |
| `X-Nativ-Service` | `geo` | el nombre de firma SigV4 (informativo) |
| `X-Nativ-Region` | `us-east-1` | la región |

Las del **mapa** —estilo, teselas, glifos, sprites— las pide el motor de
mapas, no el paquete, y **no traen las `X-Nativ-*`**: solo tus `customHeaders`.
Todas empiezan por `/v2/styles/`, `/v2/tiles/`, `/v2/glyphs/` o `/v2/static/`,
y van todas al host de Maps.

### 3.2 · Qué tiene que hacer el proxy, en orden

1. **Comprobar al usuario antes que nada.** Sin sesión válida, `401` y no se
   reenvía nada: una petición sin autenticar no puede costar un céntimo.
2. **Decidir el destino.** Es `X-Nativ-Host`. Si no viene: si la ruta es de
   mapa (3.1), el host de Maps de la región —`X-Nativ-Region` o la del
   servidor—; si no, `400`.
3. **Validar el destino contra la lista de hosts de Amazon Location.** Una
   cabecera del teléfono es una cabecera que cualquiera puede falsificar: sin
   esto, tu proxy reenvía con tus credenciales a donde le pidan. Coincidencia
   **completa** con:

   ```
   ^(places|routes|maps|geofencing|tracking|cp\.geofencing|cp\.tracking)\.geo\.([a-z0-9-]+)\.amazonaws\.com$
   ```

   La región de la firma es el grupo capturado. El nombre de firma se deduce
   del prefijo: `places` → `geo-places`, `routes` → `geo-routes`,
   `maps` → `geo-maps`, y el resto —geovallas y rastreo— `geo`.
4. **Autenticarse ante AWS**, de una de dos formas (sección 4): firmando con
   SigV4, o añadiendo `key=` con una clave que solo tiene el servidor. Antes,
   **quitar cualquier `key` que viniera en la consulta.**
5. **Reenviar** el mismo método, la misma ruta, la misma consulta —con sus
   parámetros repetidos, como `additional-features`— y el mismo cuerpo, con
   solo `host`, `content-type` y las cabeceras de la firma. **Nunca** el
   `Authorization` de tu app, ni las `X-Nativ-*`, ni cookies.
6. **Devolver la respuesta como llegó**: el mismo código —también los errores
   de AWS, para que el paquete los entienda— y el cuerpo intacto, byte a byte
   —las teselas son binarias—. Solo `content-type`, `cache-control`, `etag` y
   `x-amzn-requestid`.
7. **Reescribir el descriptor de estilo** (`/v2/styles/{estilo}/descriptor`):
   dentro vienen las URLs de teselas, glifos y sprites **apuntando a AWS**, y
   con clave de API **AWS escribe la clave en cada URL de tesela**. Hay que
   cambiar `https://maps.geo.{región}.amazonaws.com` por la URL pública del
   proxy y **quitar todo `key=`**. Sin lo primero, el mapa pide las teselas a
   AWS sin autenticar; sin lo segundo, le entregas la clave al teléfono.
8. **Registrar solo método, ruta y código.** Nunca la consulta ni las
   cabeceras: llevan datos del usuario y su token.

Si AWS no responde: `502` con un JSON `{"message": …}`.

---

## 4 · Cómo se autentica el servidor ante AWS

| | Lugares, rutas y mapas | Geovallas y rastreo |
|---|---|---|
| **Credenciales IAM (SigV4)** | ✓ | ✓ — **la única forma** |
| **Clave de API en el servidor** (`ALS_API_KEY`) | ✓ | ✗ |

Con las dos configuradas, los servidores de referencia usan la clave para
lugares, rutas y mapas y SigV4 para geovallas y rastreo. En los dos casos el
secreto se queda en el servidor.

**Las credenciales IAM, de donde ya las tenga tu servidor:** el rol de la
instancia, de la tarea de ECS o de la Lambda —lo mejor: no hay ninguna clave
que guardar— o variables de entorno `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`.

**La política mínima**, cambiando región y cuenta:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LugaresRutasMapas",
      "Effect": "Allow",
      "Action": ["geo-places:*", "geo-routes:*", "geo-maps:*"],
      "Resource": "*"
    },
    {
      "Sid": "GeovallasYRastreo",
      "Effect": "Allow",
      "Action": "geo:*",
      "Resource": [
        "arn:aws:geo:us-east-1:123456789012:geofence-collection/*",
        "arn:aws:geo:us-east-1:123456789012:tracker/*"
      ]
    },
    {
      "Sid": "Listar",
      "Effect": "Allow",
      "Action": ["geo:ListGeofenceCollections", "geo:ListTrackers"],
      "Resource": "*"
    }
  ]
}
```

Si tu app no usa geovallas ni rastreo, basta con el primer bloque —o con una
clave de API— y el proxy es aún más sencillo de dar de alta. La plantilla de
[AWS Lambda](../proxies/aws-lambda/template.yaml) trae esta misma política con
las acciones una a una, limitada a su región, por si prefieres no usar
comodines.

---

## 5 · Servidores de referencia

Seis implementaciones del mismo contrato, con **la misma estructura** —un
núcleo que no depende de ningún framework más un adaptador mínimo— y **las
mismas variables**. Las seis pasan las 26 pruebas de conformidad de la
sección 6 contra AWS, firmando con SigV4 y con clave de API.

| Variable | Obligatoria | Para qué |
|---|---|---|
| `PROXY_TOKEN` | sí | el token de prueba que comprueba el servidor. **En producción, sustitúyelo por la comprobación de tu sesión** |
| `AWS_REGION` | sí | la región para las peticiones del mapa |
| `ALS_API_KEY` | no | una clave de API para lugares, rutas y mapas, en vez de SigV4 |
| `PROXY_BASE_PATH` | no | dónde se monta; `/geo` por defecto |
| `PROXY_PUBLIC_URL` | no | la URL pública, para reescribir el estilo; si falta, se deduce de cada petición |
| `PORT` | no | `8080` por defecto |

Las credenciales de AWS, por la cadena estándar de cada SDK.

| Servidor | Para quien | Arrancar | Dentro de tu backend |
|---|---|---|---|
| [**Node**](../proxies/node) · la referencia | backends en JavaScript | `npm ci && npm start` | Express, Fastify, NestJS |
| [**AWS Lambda**](../proxies/aws-lambda) | quien no quiere un servidor más | `npm ci && npm run build && sam deploy --guided` | — es un despliegue completo, con plantilla SAM |
| [**Go**](../proxies/go) | un binario pequeño, sin dependencias | `go run .` | `net/http`, chi, gin, echo |
| [**Python**](../proxies/python) | backends en Python | `.venv/bin/python server.py` | FastAPI, Flask |
| [**PHP**](../proxies/php) | hospedajes compartidos, Laravel | `composer install && php -S localhost:8080 public/index.php` | Laravel, Slim |
| [**Java**](../proxies/java) | backends en la JVM | `./mvnw package && java -jar target/nativ-maps-proxy.jar` | Spring Boot |

Cada carpeta trae su `README.md` —requisitos, variables, cómo montarlo en tu
framework— y un `Dockerfile`.

**En AWS Lambda no hay ninguna clave**: firma el rol de la función, y la
plantilla ya trae la política con las acciones exactas. Es el camino más corto
si no tienes ya un backend donde montarlo.

Todos coinciden en lo que el contrato deja abierto:

- **No siguen redirecciones.** Una petición firmada no se reenvía a otro sitio.
- **60 segundos** de espera a AWS; después, `502`.
- **La consulta sale exactamente como se firmó**, en RFC 3986 (`%20`, no `+`).
- **Sin credenciales de AWS**, `500` con un mensaje claro, sin caerse; el
  detalle se queda en el registro del servidor.

---

## 6 · Probar tu proxy

La prueba de conformidad pasa por tu proxy **como lo hace el paquete y como lo
hace el motor de mapas**, contra AWS de verdad, y comprueba lo que tiene que
rechazar. Con tu proxy en marcha:

```sh
cd packages/nativ_maps
PROXY_URL=http://localhost:8080/geo PROXY_TOKEN=tu-token \
  dart test -P proxy
```

| Grupo | Qué comprueba |
|---|---|
| Rechaza | sin token y con token falso → `401`; cinco hosts ajenos o disfrazados y una ruta sin destino → `400` |
| Reenvía lo del paquete | lugares (con parámetros repetidos), rutas, un mapa estático con sus bytes intactos, y un error de AWS que llega como AWS lo mandó |
| Sirve el mapa | el estilo con solo el token, todas sus URLs apuntando al proxy, **ninguna clave a la vista**, una tesela, glifos y sprites, y que sin token el mapa también da `401` |
| Llega a los cuatro hosts `geo` | crea y borra una colección de geovallas y un rastreador por el proxy: los planos de datos y de control de las dos familias |

Crea sus propios recursos con el prefijo `nativ-maps-proxy-` y los borra al
terminar. Son unas 25 peticiones: céntimos.

---

## 7 · Seguridad, antes de producción

- [ ] **HTTPS** delante del proxy. El token del usuario viaja en cada petición.
- [ ] **La comprobación del usuario es la de tu backend**, no `PROXY_TOKEN`.
- [ ] **La lista de hosts** de la sección 3.2 está tal cual, con coincidencia
      completa.
- [ ] **Ningún secreto en las respuestas**: el estilo sale sin `key=`.
- [ ] **Límites por usuario**: peticiones por minuto, y por operación si alguna
      es cara —la matriz cobra por par—. Es lo que el proxy permite y una
      clave en la app no.
- [ ] **Un tope de gasto en AWS Budgets**, además.
- [ ] **Registros sin consultas ni cabeceras.**
- [ ] Si la app solo usa algunas operaciones, **rechaza el resto** por ruta.

---

## 8 · En producción

- **Caché de teselas.** El proxy pasa el `cache-control` de AWS —un día para el
  estilo—; una CDN delante del proxy ahorra peticiones y latencia. Cachea solo
  `/v2/tiles/`, `/v2/glyphs/` y `/v2/styles/`, y nunca las respuestas de
  lugares o rutas, que son de cada usuario.
- **Latencia.** Cada petición hace un salto más. Pon el proxy en la misma
  región de AWS que los datos.
- **AWS Lambda.** Sin claves —firma el rol—, pero con arranques en frío y un
  límite de 6 MB por respuesta; las teselas caben de sobra.

---

## 9 · Problemas frecuentes

| Síntoma | Causa |
|---|---|
| El mapa sale en blanco y el proxy registra `401` en `/v2/styles/…` | falta `customHeaders` en el `NativMap`, o `nativ_maps_flutter` es anterior a la 0.9.1 |
| El mapa carga el estilo pero no las teselas | el proxy no reescribe el descriptor (3.2, regla 7): el mapa las pide a AWS sin autenticar |
| `403` de AWS en lugares, rutas o mapas | las credenciales del servidor no tienen `geo-places`/`geo-routes`/`geo-maps` (sección 4) |
| `403` en geovallas o rastreo | falta `geo:*` sobre la colección o el rastreador, o la clave de API no vale para ellas |
| `400 Not an Amazon Location host` | una petición sin `X-Nativ-Host` que no es del mapa, o un host fuera de la lista |
| «The security token included in the request is invalid» | las claves IAM del servidor están desactivadas o caducadas |
