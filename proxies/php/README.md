# Proxy de referencia en PHP

El servidor al que apunta `ProxyCredentials`. La app manda cada petición de
Amazon Location aquí en lugar de a AWS; el proxy comprueba al usuario de tu
app, se autentica con Amazon Location —SigV4 con las credenciales de IAM del
servidor, o una clave de API que nunca sale de él—, reenvía y devuelve la
respuesta tal cual. **El teléfono no guarda ningún secreto de AWS.**

Se comporta igual que el de Node (`proxies/node`) y pasa la misma prueba de
conformidad. El contrato completo está en `doc/PROXY.md`.

| Archivo | Qué es |
|---|---|
| `src/Proxy.php` | El núcleo, sin framework: `handle(método, ruta, query, cabeceras, cuerpo, origen)` → `[estado, cabeceras, cuerpo]` |
| `public/index.php` | Un *front controller* plano que lo conecta a cualquier SAPI |

## Requisitos

- PHP 8.1 o superior, con `curl`, `json` y `simplexml`.
- Composer 2.

Firma con el SDK oficial (`aws/aws-sdk-php`) y reenvía con Guzzle. Al
instalar, Composer borra los modelos de servicio que no se usan: `vendor/` se
queda en ~7 MB en lugar de ~70.

## Variables

Las mismas en todos los proxies de referencia.

| Variable | Obligatoria | Por defecto | Para qué |
|---|---|---|---|
| `PROXY_TOKEN` | sí | — | Token de demostración: la app manda `Authorization: Bearer {PROXY_TOKEN}`. En producción, cámbialo por tu comprobación de sesión |
| `AWS_REGION` | sí | — | Región de las peticiones del mapa, que no traen cabeceras `X-Nativ-*` |
| `ALS_API_KEY` | no | — | Clave de API de Amazon Location, guardada en el servidor. Places, Routes y Maps la usan en lugar de SigV4; geovallas y rastreo firman siempre |
| `PROXY_BASE_PATH` | no | `/geo` | Prefijo bajo el que escucha; fuera de él, `404` |
| `PROXY_PUBLIC_URL` | no | se deduce de la petición | URL pública del proxy, para reescribir el descriptor de estilo. Ponla si hay un balanceador delante |
| `PORT` | no | `8080` | Solo para `composer serve` y Docker; con `php -S`, el puerto va en el comando |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`… | — | cadena por defecto | Credenciales de IAM: variables, perfil, rol de ECS o EC2 |

Sin `PROXY_TOKEN` o sin `AWS_REGION`, toda petición recibe un `500` que lo dice.

## Arrancarlo

```sh
composer install
PROXY_TOKEN=un-secreto AWS_REGION=us-east-1 php -S localhost:8080 public/index.php
```

El registro solo lleva `MÉTODO ruta → estado`: ni la query, que puede llevar
datos del usuario, ni las cabeceras, que llevan su token.

## Probarlo

Con el proxy en marcha, desde `packages/nativ_maps`:

```sh
PROXY_URL=http://localhost:8080/geo PROXY_TOKEN=un-secreto AWS_REGION=us-east-1 \
  dart test -P proxy
```

Crea una colección de geovallas y un rastreador a través del proxy y los borra
al terminar: las credenciales de IAM necesitan permisos de geovallas y de
rastreo.

## En Laravel

```php
// routes/api.php → la base queda en /api/geo
use Illuminate\Http\Request;
use NativMaps\Proxy\Proxy;

Route::any('/geo/{path}', function (Request $request) {
    $proxy = new Proxy(
        region: config('services.nativ_maps.region'),
        authorize: fn (array $headers) => auth('sanctum')->check(),  // tu sesión
        apiKey: config('services.nativ_maps.api_key'),
    );
    [$status, $headers, $body] = $proxy->handle(
        $request->method(),
        substr($request->getPathInfo(), strlen('/api/geo')),   // sin decodificar
        (string) $request->server('QUERY_STRING'),             // cruda: no getQueryString()
        array_map(fn ($v) => implode(', ', $v), $request->headers->all()),
        $request->getContent(),
        $request->getSchemeAndHttpHost() . '/api/geo',
    );
    return response($body, $status, $headers);
})->where('path', '.*');
```

## En Slim 4

```php
use NativMaps\Proxy\Proxy;
use Psr\Http\Message\ResponseInterface as Response;
use Psr\Http\Message\ServerRequestInterface as Request;

$proxy = new Proxy(
    region: getenv('AWS_REGION'),
    authorize: fn (array $headers) => $sessions->isValid($headers['authorization'] ?? ''),
);

$app->any('/geo/{path:.*}', function (Request $request, Response $response) use ($proxy) {
    $uri = $request->getUri();
    [$status, $headers, $body] = $proxy->handle(
        $request->getMethod(),
        substr($uri->getPath(), strlen('/geo')),
        $uri->getQuery(),
        array_change_key_case(array_map(fn ($v) => implode(', ', $v), $request->getHeaders())),
        (string) $request->getBody(),
        $uri->getScheme() . '://' . $uri->getAuthority() . '/geo',
    );
    foreach ($headers as $name => $value) {
        $response = $response->withHeader($name, $value);
    }
    $response->getBody()->write($body);
    return $response->withStatus($status);
});
```

En los dos, la query va **cruda**: `$_GET`, `parse_str` y `getQueryString()`
juntan o reordenan los parámetros repetidos, y `getPlace` manda
`additional-features` dos veces.

## Docker

```sh
docker build -t nativ-maps-proxy-php .
docker run -p 8080:8080 -e PROXY_TOKEN=un-secreto -e AWS_REGION=us-east-1 \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY nativ-maps-proxy-php
```

La imagen usa el servidor integrado de PHP, que es para desarrollo.

## En producción

- **php-fpm + nginx o Apache**, con todo dirigido a `public/index.php`
  (`FallbackResource /index.php` en Apache; `fastcgi_param SCRIPT_FILENAME
  …/public/index.php` en nginx).
- **php-fpm borra el entorno** (`clear_env = yes`): pasa las variables con
  `env[PROXY_TOKEN] = $PROXY_TOKEN` en el *pool* o pon `clear_env = no`.
- **Apache + php-fpm no pasa `Authorization`** si no se lo pides:
  `CGIPassAuth On`.
- En EC2 o ECS, cada petición pide las credenciales al servicio de metadatos.
  Para no repetirlo, dale una caché persistente al construir el proxy:
  `credentials: CredentialProvider::defaultProvider(['credentials' => $cache])`,
  con `$cache` un `Aws\CacheInterface` (por ejemplo `Aws\PsrCacheAdapter`
  sobre APCu).
