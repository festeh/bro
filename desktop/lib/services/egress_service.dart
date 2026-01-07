import 'dart:convert';

import 'package:http/http.dart' as http;

import 'token_service.dart';

class EgressInfo {
  final String egressId;
  final String status;
  final String? filePath;
  final int? duration;

  EgressInfo({
    required this.egressId,
    required this.status,
    this.filePath,
    this.duration,
  });

  factory EgressInfo.fromJson(Map<String, dynamic> json) {
    return EgressInfo(
      egressId: json['egress_id'] ?? json['egressId'] ?? '',
      status: json['status'] ?? '',
      filePath: json['file']?['filename'] ?? json['file_results']?[0]?['filename'],
      duration: json['file']?['duration'] ?? json['file_results']?[0]?['duration'],
    );
  }

  bool get isActive =>
      status == 'EGRESS_STARTING' || status == 'EGRESS_ACTIVE';
  bool get isComplete => status == 'EGRESS_COMPLETE';
}

class EgressService {
  static const String _baseUrl = 'http://localhost:7880/twirp';
  final TokenService _tokenService;
  String? _cachedToken;

  EgressService({TokenService? tokenService})
      : _tokenService = tokenService ?? TokenService();

  String get _token {
    _cachedToken ??= _tokenService.generateEgressToken();
    return _cachedToken!;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  /// Start recording a track to a file
  Future<EgressInfo> startTrackEgress({
    required String roomName,
    required String trackId,
    required String filepath,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/livekit.Egress/StartTrackEgress'),
      headers: _headers,
      body: jsonEncode({
        'room_name': roomName,
        'track_id': trackId,
        'file': {
          'filepath': filepath,
        },
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to start egress: ${response.body}');
    }

    return EgressInfo.fromJson(jsonDecode(response.body));
  }

  /// Stop an active egress
  Future<EgressInfo> stopEgress(String egressId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/livekit.Egress/StopEgress'),
      headers: _headers,
      body: jsonEncode({
        'egress_id': egressId,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to stop egress: ${response.body}');
    }

    return EgressInfo.fromJson(jsonDecode(response.body));
  }

  /// List all egress sessions
  Future<List<EgressInfo>> listEgress({String? roomName}) async {
    final body = <String, dynamic>{};
    if (roomName != null) {
      body['room_name'] = roomName;
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/livekit.Egress/ListEgress'),
      headers: _headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to list egress: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final items = data['items'] as List<dynamic>? ?? [];
    return items.map((e) => EgressInfo.fromJson(e)).toList();
  }
}
