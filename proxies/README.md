# Servidores de referencia para `ProxyCredentials`

Seis implementaciones del mismo contrato: tu app habla con ellas, ellas se
autentican ante Amazon Location, y **la clave nunca llega al teléfono**.

| Carpeta | |
|---|---|
| [`node/`](node) | la referencia; Express, Fastify, NestJS |
| [`aws-lambda/`](aws-lambda) | el núcleo de Node en una función con URL, sin ninguna clave: firma el rol |
| [`go/`](go) | `net/http`, chi, gin, echo |
| [`python/`](python) | biblioteca estándar; FastAPI, Flask |
| [`php/`](php) | Laravel, Slim |
| [`java/`](java) | `HttpServer` del JDK; Spring Boot |

Mismas variables, mismo comportamiento, misma estructura —un núcleo sin
framework y un servidor mínimo—, y las seis comprobadas con la misma prueba
de conformidad contra AWS.

**Empieza por [doc/PROXY.md](../doc/PROXY.md)**: qué tiene que hacer un proxy,
la política IAM, cómo probar el tuyo y qué revisar antes de producción.
