import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as p;

void main() async {
  final router = Router();

  // JSON 파일 경로 설정
  final jsonFilePath = p.join(Directory.current.path, './db/users.json');

  // 회원가입 post 시작
  router.post('/register', (Request request) async {
    // 요청의 본문을 읽어서 JSON 데이터로 디코딩합니다.
    final payload = await request.readAsString();
    final newUser = jsonDecode(payload);

    // newUser 출력
    print('Received newUser: $newUser');

    // 기존 JSON 파일 읽기
    File file = File(jsonFilePath);
    List<dynamic> users = [];

    if (await file.exists()) {
      try {
        final contents = await file.readAsString();
        if (contents.isNotEmpty) {
          final decoded = jsonDecode(contents);
          if (decoded is List) {
            users = decoded;
          }
        }
      } catch (e) {
        // JSON 파싱 오류 처리
        print('Error reading JSON file: $e');
      }
    }

    // ID 중복 확인
    final existingUser = users.firstWhere((user) => user['id'] == newUser['id'],
        orElse: () => null);

    if (existingUser != null) {
      // ID가 중복된 경우
      return Response(101); // id 중복 오류
    }

    // 새로운 사용자 추가
    users.add(newUser);

    // 리스트 길이 출력
    print('Number of users: ${users.length}');

    // JSON 파일에 저장
    await file.writeAsString(jsonEncode(users), mode: FileMode.write);

    return Response(200);
  });
  // 회원가입 post 완료

  final handler =
      const Pipeline().addMiddleware(logRequests()).addHandler(router);

  final server = await io.serve(handler, '0.0.0.0', 8080);

  print('Server listening on port ${server.port}');
}
