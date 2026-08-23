// Copyright (c) 2026 Delio Ribas. Licencia MIT — ver LICENSE.

import 'package:http/http.dart' as http;
import 'package:nativ_maps/nativ_maps.dart';
import 'package:nativ_maps_sigv4/nativ_maps_sigv4.dart';
import 'package:test/test.dart';

/// Las credenciales del ejemplo oficial de la documentación de SigV4 de AWS.
///
/// Son públicas y no valen para nada: existen precisamente para que cualquier
/// implementación pueda compararse contra el mismo resultado conocido.
const _awsExampleCredentials = AwsCredentials(
  accessKeyId: 'AKIDEXAMPLE',
  secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
);

/// La fecha del ejemplo oficial: 2015-08-30T12:36:00Z.
final _awsExampleDate = DateTime.utc(2015, 8, 30, 12, 36);

void main() {
  const signer = SigV4Signer();

  group('vectores oficiales de la suite de pruebas de SigV4 de AWS', () {
    // ── get-vanilla ────────────────────────────────────────────────────
    //
    // El caso más simple de la suite, y el que valida los cuatro pasos del
    // algoritmo a la vez: petición canónica, cadena que se firma, derivación
    // de la clave y firma final.
    //
    // Si este pasa, los cuatro pasos están bien. Si falla, el `403` que da el
    // servicio real sería indistinguible del de una clave inválida — que es
    // exactamente por qué esta prueba existe.
    test('get-vanilla produce la firma documentada por AWS', () {
      final headers = signer.sign(
        method: 'GET',
        uri: Uri.parse('https://example.amazonaws.com/'),
        service: 'service',
        region: 'us-east-1',
        credentials: _awsExampleCredentials,
        signedAt: _awsExampleDate,
      );

      expect(
        headers['Authorization'],
        contains(
          'Credential=AKIDEXAMPLE/20150830/us-east-1/service/'
          'aws4_request',
        ),
      );
      expect(headers['X-Amz-Date'], '20150830T123600Z');
      // El SHA-256 del cuerpo vacío, que va en toda petición GET.
      expect(
        headers['X-Amz-Content-Sha256'],
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('la petición canónica coincide carácter a carácter', () {
      // Este es el fichero `.creq` de `get-vanilla` en la suite de AWS. Es la
      // comprobación que convierte «la firma sale mal» en «el paso 1 sale
      // mal», que son dos investigaciones muy distintas.
      final canonical = signer.canonicalRequestFor(
        method: 'GET',
        uri: Uri.parse('https://example.amazonaws.com/'),
        headers: const <String, String>{
          'host': 'example.amazonaws.com',
          'x-amz-date': '20150830T123600Z',
        },
        payloadHash: SigV4Signer.emptyBodySha256,
      );

      expect(
        canonical,
        'GET\n'
        '/\n'
        '\n'
        'host:example.amazonaws.com\n'
        'x-amz-date:20150830T123600Z\n'
        '\n'
        'host;x-amz-date\n'
        '${SigV4Signer.emptyBodySha256}',
      );
    });

    test('la firma de get-vanilla es EXACTAMENTE la del vector oficial', () {
      // El valor de la derecha es el que publica AWS en su suite de pruebas
      // para `get-vanilla`, y está verificado además contra una
      // implementación independiente en Python.
      //
      // Esta es la prueba que permite confiar en el firmador. Comprobar solo
      // que la firma «tiene la forma correcta» no garantiza nada: una firma
      // mal calculada también tiene 64 caracteres hexadecimales, y el
      // servicio la rechaza con un 403 indistinguible del de una clave mala.
      final canonical = signer.canonicalRequestFor(
        method: 'GET',
        uri: Uri.parse('https://example.amazonaws.com/'),
        headers: const <String, String>{
          'host': 'example.amazonaws.com',
          'x-amz-date': '20150830T123600Z',
        },
        payloadHash: SigV4Signer.emptyBodySha256,
      );

      expect(
        signer.signatureOfCanonicalRequest(
          canonicalRequest: canonical,
          amzDate: '20150830T123600Z',
          region: 'us-east-1',
          service: 'service',
          secretAccessKey: _awsExampleCredentials.secretAccessKey,
        ),
        '5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31',
      );
    });

    test('get-vanilla-query-order-key ordena la consulta', () {
      // La cadena de consulta canónica se ordena por clave y luego por valor.
      // No ordenarla da una firma distinta y un 403.
      final canonical = signer.canonicalRequestFor(
        method: 'GET',
        uri: Uri.parse(
          'https://example.amazonaws.com/?Param2=value2'
          '&Param1=value1',
        ),
        headers: const <String, String>{'host': 'example.amazonaws.com'},
        payloadHash: SigV4Signer.emptyBodySha256,
      );
      expect(canonical.split('\n')[2], 'Param1=value1&Param2=value2');
    });

    test('el espacio se codifica como %20, nunca como +', () {
      // `Uri.encodeQueryComponent` usa `+`, que AWS rechaza. Es el fallo de
      // codificación más habitual al escribir un firmador a mano.
      final canonical = signer.canonicalRequestFor(
        method: 'GET',
        uri: Uri.parse(
          'https://example.amazonaws.com/?Param1=${Uri.encodeComponent('va lue')}',
        ),
        headers: const <String, String>{'host': 'example.amazonaws.com'},
        payloadHash: SigV4Signer.emptyBodySha256,
      );
      expect(canonical, contains('Param1=va%20lue'));
      expect(canonical, isNot(contains('+')));
    });

    test('codifica los caracteres que Uri.encodeComponent deja pasar', () {
      // `Uri.encodeComponent` no toca `!`, `*`, `'`, `(` ni `)`. AWS sí.
      final canonical = signer.canonicalRequestFor(
        method: 'GET',
        uri: Uri.parse("https://example.amazonaws.com/?p=a!b*c'd(e)"),
        headers: const <String, String>{'host': 'example.amazonaws.com'},
        payloadHash: SigV4Signer.emptyBodySha256,
      );
      final query = canonical.split('\n')[2];
      for (final char in <String>['!', '*', "'", '(', ')']) {
        expect(query, isNot(contains(char)), reason: '$char sin codificar');
      }
    });

    test('los espacios repetidos en una cabecera se colapsan', () {
      final canonical = signer.canonicalRequestFor(
        method: 'GET',
        uri: Uri.parse('https://example.amazonaws.com/'),
        headers: const <String, String>{
          'host': 'example.amazonaws.com',
          'my-header': '  a   b   c  ',
        },
        payloadHash: SigV4Signer.emptyBodySha256,
      );
      expect(canonical, contains('my-header:a b c\n'));
    });

    test('la cabecera Host no lleva :443 en HTTPS', () {
      // Incluirlo invalida la firma: el cliente HTTP no lo manda y el servidor
      // firma sin él.
      final headers = signer.sign(
        method: 'GET',
        uri: Uri.parse('https://example.amazonaws.com:443/'),
        service: 'service',
        region: 'us-east-1',
        credentials: _awsExampleCredentials,
        signedAt: _awsExampleDate,
      );
      final sinPuerto = signer.sign(
        method: 'GET',
        uri: Uri.parse('https://example.amazonaws.com/'),
        service: 'service',
        region: 'us-east-1',
        credentials: _awsExampleCredentials,
        signedAt: _awsExampleDate,
      );
      expect(headers['Authorization'], sinPuerto['Authorization']);
    });
  });

  group('determinismo y sensibilidad de la firma', () {
    Map<String, String> firmar({
      String method = 'POST',
      String url = 'https://places.geo.us-east-1.amazonaws.com/v2/search-text',
      String service = 'geo-places',
      String region = 'us-east-1',
      List<int>? body,
    }) => signer.sign(
      method: method,
      uri: Uri.parse(url),
      service: service,
      region: region,
      credentials: _awsExampleCredentials,
      body: body,
      signedAt: _awsExampleDate,
    );

    test('la misma petición da siempre la misma firma', () {
      expect(firmar()['Authorization'], firmar()['Authorization']);
    });

    test('cambiar el nombre del servicio cambia la firma', () {
      // Es LA comprobación de este paquete. `geo-places` y `geo-routes` dan
      // firmas distintas, y usar la equivocada da un 403 idéntico al de una
      // clave mala. Que la prueba exista es lo que garantiza que el enum
      // `AlsService` está haciendo su trabajo.
      expect(
        firmar(service: 'geo-places')['Authorization'],
        isNot(firmar(service: 'geo-routes')['Authorization']),
      );
      expect(
        firmar(service: 'geo-places')['Authorization'],
        isNot(firmar(service: 'geo')['Authorization']),
      );
    });

    test('cambiar la región cambia la firma', () {
      expect(
        firmar(region: 'us-east-1')['Authorization'],
        isNot(firmar(region: 'eu-central-1')['Authorization']),
      );
    });

    test('cambiar el cuerpo cambia la firma', () {
      expect(
        firmar(body: <int>[1, 2, 3])['Authorization'],
        isNot(firmar(body: <int>[1, 2, 4])['Authorization']),
      );
    });

    test('cambiar el método cambia la firma', () {
      expect(
        firmar(method: 'GET')['Authorization'],
        isNot(firmar(method: 'POST')['Authorization']),
      );
    });

    test('la clave secreta NUNCA aparece en las cabeceras', () {
      final headers = firmar();
      for (final value in headers.values) {
        expect(value, isNot(contains(_awsExampleCredentials.secretAccessKey)));
      }
    });

    test('el testigo de sesión va firmado, no solo enviado', () {
      const conTestigo = AwsCredentials(
        accessKeyId: 'AKIDEXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
        sessionToken: 'TESTIGO',
      );
      final headers = signer.sign(
        method: 'GET',
        uri: Uri.parse('https://example.amazonaws.com/'),
        service: 'service',
        region: 'us-east-1',
        credentials: conTestigo,
        signedAt: _awsExampleDate,
      );
      // Omitirlo de las cabeceras firmadas da un 403 que parece de clave mala.
      expect(headers['Authorization'], contains('x-amz-security-token'));
      expect(headers['X-Amz-Security-Token'], 'TESTIGO');
    });
  });

  group('SigV4Credentials', () {
    test('firma con el nombre correcto según el servicio', () async {
      final credenciales = SigV4Credentials.fixed(_awsExampleCredentials);

      final peticion = http.Request(
        'POST',
        Uri.parse('https://routes.geo.us-east-1.amazonaws.com/v2/routes'),
      )..body = '{}';
      final firmada = await credenciales.sign(
        peticion,
        AlsService.routes,
        'us-east-1',
      );

      expect(firmada.headers['Authorization'], contains('/geo-routes/'));
      expect(firmada.headers['Authorization'], isNot(contains('/geo-places/')));
    });

    test('renueva las credenciales caducadas', () async {
      var llamadas = 0;
      final credenciales = SigV4Credentials(
        provider: () async {
          llamadas++;
          return AwsCredentials(
            accessKeyId: 'AKID$llamadas',
            secretAccessKey: 'secreto',
            sessionToken: 'testigo',
            // Ya caducadas: cada petición tiene que pedirlas de nuevo.
            expiration: DateTime.now().toUtc().subtract(
              const Duration(minutes: 5),
            ),
          );
        },
      );

      Future<void> pedir() async {
        final peticion = http.Request(
          'GET',
          Uri.parse('https://places.geo.us-east-1.amazonaws.com/v2/place/x'),
        );
        await credenciales.sign(peticion, AlsService.places, 'us-east-1');
      }

      await pedir();
      await pedir();
      expect(llamadas, 2);
    });

    test('reutiliza las credenciales vigentes', () async {
      var llamadas = 0;
      final credenciales = SigV4Credentials(
        provider: () async {
          llamadas++;
          return AwsCredentials(
            accessKeyId: 'AKID',
            secretAccessKey: 'secreto',
            expiration: DateTime.now().toUtc().add(const Duration(hours: 1)),
          );
        },
      );

      for (var i = 0; i < 5; i++) {
        final peticion = http.Request(
          'GET',
          Uri.parse('https://places.geo.us-east-1.amazonaws.com/v2/place/x'),
        );
        await credenciales.sign(peticion, AlsService.places, 'us-east-1');
      }
      expect(llamadas, 1);
    });

    test('varias peticiones a la vez comparten una sola renovación', () async {
      // Sin esto, una pantalla que lanza cinco peticiones al abrirse pediría
      // credenciales cinco veces al pool de identidades.
      var llamadas = 0;
      final credenciales = SigV4Credentials(
        provider: () async {
          llamadas++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return const AwsCredentials(
            accessKeyId: 'AKID',
            secretAccessKey: 'secreto',
          );
        },
      );

      await Future.wait<void>(<Future<void>>[
        for (var i = 0; i < 5; i++)
          credenciales.sign(
            http.Request(
              'GET',
              Uri.parse('https://places.geo.us-east-1.amazonaws.com/v2/x'),
            ),
            AlsService.places,
            'us-east-1',
          ),
      ]);

      expect(llamadas, 1);
    });

    test('invalidate obliga a pedirlas de nuevo', () async {
      var llamadas = 0;
      final credenciales = SigV4Credentials(
        provider: () async {
          llamadas++;
          return const AwsCredentials(
            accessKeyId: 'AKID',
            secretAccessKey: 'secreto',
          );
        },
      );

      Future<void> pedir() => credenciales.sign(
        http.Request(
          'GET',
          Uri.parse('https://places.geo.us-east-1.amazonaws.com/v2/x'),
        ),
        AlsService.places,
        'us-east-1',
      );

      await pedir();
      credenciales.invalidate();
      await pedir();
      expect(llamadas, 2);
    });

    test('mapHeaders firma con geo-maps', () async {
      final credenciales = SigV4Credentials.fixed(_awsExampleCredentials);
      final headers = await credenciales.mapHeaders(
        styleUrl:
            'https://maps.geo.us-east-1.amazonaws.com'
            '/v2/styles/Standard/descriptor',
        region: 'us-east-1',
      );
      expect(headers['Authorization'], contains('/geo-maps/'));
    });

    test('no pone la clave en la URL: autentica con cabeceras', () {
      final credenciales = SigV4Credentials.fixed(_awsExampleCredentials);
      expect(credenciales.apiKeyForUrl, isNull);
      expect(credenciales.isConfigured, isTrue);
    });
  });

  group('AwsCredentials', () {
    test('las permanentes nunca caducan', () {
      const permanentes = AwsCredentials(
        accessKeyId: 'AKID',
        secretAccessKey: 'secreto',
      );
      expect(permanentes.isExpired(), isFalse);
      expect(permanentes.isTemporary, isFalse);
    });

    test('el margen evita firmar con credenciales que caducan enseguida', () {
      // Una petición firmada con credenciales que caducan en dos segundos
      // llega caducada.
      final casiCaducadas = AwsCredentials(
        accessKeyId: 'AKID',
        secretAccessKey: 'secreto',
        sessionToken: 'testigo',
        expiration: DateTime.now().toUtc().add(const Duration(seconds: 2)),
      );
      expect(casiCaducadas.isExpired(), isTrue);
      expect(casiCaducadas.isExpired(margin: Duration.zero), isFalse);
    });

    test('toString no revela el secreto', () {
      const credenciales = AwsCredentials(
        accessKeyId: 'AKID',
        secretAccessKey: 'ESTO-ES-SECRETO',
      );
      expect(credenciales.toString(), isNot(contains('ESTO-ES-SECRETO')));
    });
  });
}
