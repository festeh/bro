import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class TokenService {
  static const String _apiKey = 'devkey';
  static const String _apiSecret = 'secret';

  /// Generate a JWT token for joining a LiveKit room
  String generateRoomToken({
    required String roomName,
    required String identity,
    Duration validFor = const Duration(hours: 24),
  }) {
    final now = DateTime.now();
    final exp = now.add(validFor);

    final jwt = JWT(
      {
        'iss': _apiKey,
        'sub': identity,
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': exp.millisecondsSinceEpoch ~/ 1000,
        'nbf': now.millisecondsSinceEpoch ~/ 1000,
        'jti': identity,
        'video': {
          'room': roomName,
          'roomJoin': true,
          'canPublish': true,
          'canSubscribe': true,
          'canPublishData': true,
        },
      },
    );

    return jwt.sign(SecretKey(_apiSecret));
  }

  /// Generate a JWT token for Egress API calls (admin token)
  String generateEgressToken({
    Duration validFor = const Duration(hours: 24),
  }) {
    final now = DateTime.now();
    final exp = now.add(validFor);

    final jwt = JWT(
      {
        'iss': _apiKey,
        'sub': 'egress-client',
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': exp.millisecondsSinceEpoch ~/ 1000,
        'nbf': now.millisecondsSinceEpoch ~/ 1000,
        'video': {
          'roomRecord': true,
        },
      },
    );

    return jwt.sign(SecretKey(_apiSecret));
  }
}
