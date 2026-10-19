# Proxy de referencia en Go

El servidor al que llama una app que usa `ProxyCredentials`. Comprueba al
usuario de tu app, se autentica con Amazon Location —SigV4 con las
credenciales IAM del servidor, o una clave de API que no sale de él—, reenvía
la petición y devuelve la respuesta tal cual. El teléfono nunca tiene un
secreto de AWS.

Hace exactamente lo mismo que el de Node (`proxies/node`): mismas variables,
mismas respuestas, misma prueba de conformidad.

- `nativproxy/proxy.go`: el núcleo, sin framework. `Handle` recibe y devuelve
  valores; `Handler` lo envuelve como `http.Handler`.
- `main.go`: el servidor independiente, solo con `net/http`.

## Requisitos

- Go 1.24 o posterior.
- Credenciales de AWS con permiso para lo que vaya a usar la app:
  `geo-places:*`, `geo-routes:*` y `geo-maps:*` (salvo que uses
  `ALS_API_KEY`), y `geo:*` sobre tus colecciones y rastreadores para
  geovallas y rastreo, que **siempre** van firmados con SigV4.

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
cd proxies/go
PROXY_TOKEN=un-token-largo AWS_REGION=us-east-1 go run .
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

## Dentro de otro router

`Handler(basePath)` es un `http.Handler` corriente. `basePath` es la ruta tal
como la ve el handler: si va detrás de `http.StripPrefix`, pasa lo que queda.

```go
proxy, err := nativproxy.New(ctx, nativproxy.Options{
	Region: "us-east-1",
	// Tu comprobación de siempre: tu JWT, tu cookie, tu sesión.
	Authorize: func(ctx context.Context, h http.Header) bool {
		_, err := sessions.Verify(ctx, strings.TrimPrefix(h.Get("Authorization"), "Bearer "))
		return err == nil
	},
	APIKey:    os.Getenv("ALS_API_KEY"),        // opcional
	PublicURL: "https://api.tuapp.com/geo",     // opcional
})

// net/http
mux.Handle("/geo/", proxy.Handler("/geo"))

// chi
r.Mount("/geo", proxy.Handler("/geo"))

// gin
router.Any("/geo/*path", gin.WrapH(proxy.Handler("/geo")))

// echo
e.Any("/geo/*", echo.WrapHandler(proxy.Handler("/geo")))
```

Fuera de `net/http` —una función Lambda, por ejemplo— llama al núcleo
directamente:

```go
res := proxy.Handle(ctx, nativproxy.Request{
	Method: method,
	Path:   "/v2/geocode",          // la ruta de AWS, sin el prefijo
	Query:  rawQuery,
	Header: header,
	Body:   body,                   // io.Reader; se lee después de autorizar
	Origin: "https://api.tuapp.com/geo",
})
// res.Status, res.Header, res.Body
```

## Docker

```sh
docker build -t nativ-maps-proxy-go proxies/go
docker run -p 8080:8080 \
  -e PROXY_TOKEN=un-token-largo -e AWS_REGION=us-east-1 \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
  nativ-maps-proxy-go
```

El `Dockerfile` compila en `golang:1.24-alpine` y deja solo el binario en
`distroless/static` sin privilegios, con los certificados que hacen falta
para hablar con AWS por HTTPS.
