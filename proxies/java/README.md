# Proxy de referencia — Java

El servidor al que llama una app con `ProxyCredentials`. Comprueba al usuario de
la app, se autentica con Amazon Location —SigV4 con las credenciales IAM del
servidor, o una clave de API que se queda en el servidor—, reenvía y devuelve la
respuesta. **El teléfono nunca tiene un secreto de AWS.**

Hace lo mismo que [`proxies/node`](../node), punto por punto; el contrato
completo está en [doc/PROXY.md](../../doc/PROXY.md). Sin framework: el
`HttpServer` del JDK para recibir, `java.net.http` para reenviar y el SDK
oficial de AWS para Java v2 (`AwsV4HttpSigner`) para firmar.

| Archivo | Qué es |
|---|---|
| [`Proxy.java`](src/main/java/io/github/delioribas/nativmaps/proxy/Proxy.java) | El núcleo, sin servidor: `handle(method, path, query, headers, body, origin)` → `Result(status, headers, body)` |
| [`Main.java`](src/main/java/io/github/delioribas/nativmaps/proxy/Main.java) | El servidor independiente alrededor del núcleo |

## Requisitos

- **JDK 17** o posterior. O solo Docker.
- Credenciales IAM con permisos `geo:*` (geovallas y rastreo las exigen siempre;
  el resto, si no hay `ALS_API_KEY`).

## Variables

Las mismas en todos los proxies de referencia.

| Variable | Obligatoria | Por defecto | Qué es |
|---|---|---|---|
| `PORT` | no | `8080` | Puerto de escucha |
| `PROXY_BASE_PATH` | no | `/geo` | Prefijo de las rutas. Fuera de él, `404` |
| `PROXY_PUBLIC_URL` | no | la de cada petición | URL pública del proxy, para reescribir el descriptor de estilo. Ej.: `https://api.miempresa.com/geo`. Sin ella: `{X-Forwarded-Proto o http}://{Host}{PROXY_BASE_PATH}` |
| `PROXY_TOKEN` | **sí** | — | Token de prueba: se exige `Authorization: Bearer <token>`. En producción, cámbialo por tu comprobación de sesión |
| `AWS_REGION` | **sí** | — | Región del mapa: el renderizador no manda `X-Nativ-Region` |
| `ALS_API_KEY` | no | — | Clave de Amazon Location. Si está, Places, Routes y Maps la usan en vez de SigV4. Nunca llega al teléfono |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`… | — | cadena estándar | Credenciales IAM: variables, perfil (también con `role_arn`), rol de ECS/EKS/EC2 |

Sin `PROXY_TOKEN` o sin `AWS_REGION`, no arranca.

## Compilar y arrancar

```sh
./mvnw -DskipTests package       # basta un JDK; el wrapper se baja Maven

# o sin Java ni Maven instalados:
docker run --rm -v "$PWD":/app -v "$HOME/.m2":/root/.m2 -w /app \
  maven:3.9-eclipse-temurin-17 mvn -q -DskipTests package
```

Deja un único jar ejecutable, con todas las dependencias dentro:

```sh
PROXY_TOKEN=… AWS_REGION=us-east-1 java -jar target/nativ-maps-proxy.jar
# nativ_maps proxy on :8080/geo
```

El registro solo lleva `MÉTODO ruta → estado`: nunca la consulta, que puede
traer datos del usuario, ni las cabeceras, que traen su token.

## Probarlo

La prueba de conformidad del paquete pasa por el proxy igual que la app y que el
renderizador del mapa, y comprueba lo que tiene que rechazar. Con el proxy en
marcha, desde `packages/nativ_maps`:

```sh
PROXY_URL=http://localhost:8080/geo PROXY_TOKEN=… AWS_REGION=us-east-1 \
  dart test -P proxy
```

Crea una colección de geovallas y un rastreador `nativ-maps-proxy-…` a través
del proxy y los borra al terminar: las credenciales IAM del proxy necesitan
permisos de geovallas y de rastreo.

## Desde Spring Boot

El núcleo no depende del servidor. En una aplicación Spring Boot 3 existente,
copia `Proxy.java`, añade `software.amazon.awssdk:http-auth-aws` y
`software.amazon.awssdk:auth` (con el BOM del SDK, como en el
[`pom.xml`](pom.xml)) y un controlador:

```java
@RestController
class GeoProxyController {

  private final Proxy proxy = Proxy.builder()
      .region(System.getenv("AWS_REGION"))
      .apiKey(System.getenv("ALS_API_KEY"))                  // opcional
      .publicUrl("https://api.miempresa.com/geo")
      // Tu comprobación de sesión: tu JWT, tu cookie… false = 401 y no se reenvía nada.
      .authorize(headers -> sesiones.esValida(headers.get("authorization")))
      .build();

  @RequestMapping("/geo/**")
  ResponseEntity<byte[]> geo(HttpServletRequest request,
                             @RequestBody(required = false) byte[] body) {
    Map<String, String> headers = new HashMap<>();
    for (String name : Collections.list(request.getHeaderNames())) {
      headers.put(name, request.getHeader(name));
    }
    String base = request.getContextPath() + "/geo";
    Proxy.Result r = proxy.handle(
        request.getMethod(),
        request.getRequestURI().substring(base.length()),   // sin decodificar
        request.getQueryString(),
        headers,
        body,
        null);                                               // ya hay publicUrl
    HttpHeaders out = new HttpHeaders();
    r.headers().forEach(out::set);
    return ResponseEntity.status(r.status()).headers(out).body(r.body());
  }
}
```

`Proxy` es seguro entre hilos: uno para toda la aplicación. Si Spring Security
ya exige sesión en `/geo/**`, `authorize` puede limitarse a lo que falte
(límites por usuario, por ejemplo).

## Docker

El [`Dockerfile`](Dockerfile) compila con Maven y arranca con solo el JRE:

```sh
docker build -t nativ-maps-proxy .
docker run -p 8080:8080 -e PROXY_TOKEN -e AWS_REGION -e ALS_API_KEY nativ-maps-proxy
```

En ECS, EKS o EC2, no pases claves: el rol de la tarea, del pod o de la
instancia lo recoge la cadena estándar.
