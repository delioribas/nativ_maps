# Changelog

## 0.1.0

Primera versión.

- `SigV4Signer`: firma AWS Signature Version 4 con `crypto` como única
  dependencia, en lugar de las dieciséis transitivas de `aws_signature_v4`.
- **Verificado contra el vector oficial `get-vanilla`** de la suite de pruebas
  de SigV4 de AWS: el valor hexadecimal exacto, no solo la forma.
- Codificación RFC 3986 correcta —que no es la de `Uri.encodeComponent`—,
  cadena de consulta ordenada, cabeceras canónicas y colapso de espacios.
- `SigV4Credentials` con renovación automática, caché con margen de caducidad y
  una sola renovación compartida entre llamadas simultáneas.
- `mapHeaders` para firmar **también las teselas del mapa**, que es lo que
  ningún otro camino permite.
- El nombre de firma lo pone el enum `AlsService`: `geo-places`, `geo-routes`,
  `geo-maps` en la generación v2, y `geo` en geovallas y rastreo. No se puede
  escribir mal.
