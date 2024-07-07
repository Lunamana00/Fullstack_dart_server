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
  // 유저 폴더 기본 경로 설정
  final userFolderBasePath = p.join(Directory.current.path, './db/users');

  // 회원가입 post 시작
  router.post('/register', (Request request) async {
    final payload = await request.readAsString();
    final newUser = jsonDecode(payload);

    print('Received newUser: $newUser');

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
        print('Error reading JSON file: $e');
      }
    }

    final existingUser = users.firstWhere((user) => user['id'] == newUser['id'], orElse: () => null);

    if (existingUser != null) {
      return Response(101); // id 중복 오류
    }

    users.add(newUser);
    print('Number of users: ${users.length}');
    await file.writeAsString(jsonEncode(users), mode: FileMode.write);

    final userFolder = Directory(p.join(userFolderBasePath, newUser['id']));
    if (!(await userFolder.exists())) {
      await userFolder.create(recursive: true);
      print('User folder created: ${userFolder.path}');
    }

    final userJsonFile = File(p.join(userFolder.path, '${newUser['id']}.json'));
    final AJsonFile = File(p.join(userFolder.path, '${newUser['id']}_A.json'));
    final BJsonFile = File(p.join(userFolder.path, '${newUser['id']}_B.json'));
    final CJsonFile = File(p.join(userFolder.path, '${newUser['id']}_C.json'));
    final DJsonFile = File(p.join(userFolder.path, '${newUser['id']}_D.json'));

    final userInitialData = {
      'name': newUser['name'],
      'id': newUser['id'],
      'char_type': newUser['char_type'],
      'u_lv': 1,
      'u_exp': 0
    };
    final subjectData = {'lv': 1, 'exp': 0, 'dates': []};

    await userJsonFile.writeAsString(jsonEncode(userInitialData), mode: FileMode.write);
    await AJsonFile.writeAsString(jsonEncode(subjectData), mode: FileMode.write);
    await BJsonFile.writeAsString(jsonEncode(subjectData), mode: FileMode.write);
    await CJsonFile.writeAsString(jsonEncode(subjectData), mode: FileMode.write);
    await DJsonFile.writeAsString(jsonEncode(subjectData), mode: FileMode.write);

    return Response(200);
  });

  // 로그인 post 시작
  router.post('/login', (Request request) async {
    final payload = await request.readAsString();
    final loginData = jsonDecode(payload);

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
        print('Error reading JSON file: $e');
      }
    }

    final existingUser = users.firstWhere(
      (user) => user['id'] == loginData['id'] && user['pw'] == loginData['pw'],
      orElse: () => null,
    );

    if (existingUser != null) {
      return Response.ok(jsonEncode(existingUser), headers: {'Content-Type': 'application/json'});
    } else {
      return Response(201);
    }
  });

  // 유저 정보 가져오기
  router.get('/user_info/<id>', (Request request, String id) async {
    final userFolder = Directory(p.join(userFolderBasePath, id));
    final userJsonFilePath = p.join(userFolder.path, '$id.json');
    final userJsonFile = File(userJsonFilePath);

    final AJsonFile = File(p.join(userFolder.path, '${id}_A.json'));
    final BJsonFile = File(p.join(userFolder.path, '${id}_B.json'));
    final CJsonFile = File(p.join(userFolder.path, '${id}_C.json'));
    final DJsonFile = File(p.join(userFolder.path, '${id}_D.json'));

    var response_list = [userJsonFile, AJsonFile, BJsonFile, CJsonFile, DJsonFile];

    if (await userJsonFile.exists()) {
      var response_data = [];
      for (int i = 0; i < 5; i++) {
        final JsonData = await response_list[i].readAsString();
        response_data.add(jsonDecode(JsonData));
      }
      print(response_data);
      return Response.ok(jsonEncode(response_data), headers: {'Content-Type': 'application/json'});
    } else {
      return Response(500, body: 'User data file not found');
    }
  });

  // 기록 요청 저장
  router.post('/upload', (Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);

    final String id = data['id'];
    final String date = data['date'];
    final String subject = data['icon'];
    final List<String> images = data['images'] != null ? List<String>.from(data['images']) : [];
    final String comment = data['comment'] ?? '';

    final SavePath = p.join(Directory.current.path, 'db', 'users', id, date, '$subject.json');

    final userFolder = Directory(p.dirname(SavePath));
    final recordFile = File(SavePath);

    bool isFirstRecordToday = !(await recordFile.exists());

    if (!(await userFolder.exists())) {
      await userFolder.create(recursive: true);
      print('Folder created: ${userFolder.path}');
    }

    // JSON 파일 생성 및 기본 정보 저장
    final recordData = {
      'comment': comment,
      'images': images,
    };

    await recordFile.writeAsString(jsonEncode(recordData), mode: FileMode.write);

    // subject가 ETC가 아닌 경우에만 경험치 업데이트
    if (subject != 'ETC') {
      // 사용자 폴더의 {유저이름}_{subject}.json 파일의 exp와 lv 업데이트
      final subjectExpPath = p.join(Directory.current.path, 'db', 'users', id, '${id}_$subject.json');
      final subjectExpFile = File(subjectExpPath);
      Map<String, dynamic> subjectExpData;
      if (await subjectExpFile.exists()) {
        subjectExpData = jsonDecode(await subjectExpFile.readAsString());
        subjectExpData['dates'] = subjectExpData['dates'] ?? [];
      } else {
        subjectExpData = {'lv': 1, 'exp': 0, 'dates': []};
      }

      if (!subjectExpData['dates'].contains(date)) {
        subjectExpData['dates'].add(date);

        if (subjectExpData['exp'] < 90) {
          subjectExpData['exp'] += 10;
        } else {
          subjectExpData['exp'] = 0;
          subjectExpData['lv'] += 1;
        }
        await subjectExpFile.writeAsString(jsonEncode(subjectExpData), mode: FileMode.write);
      }

      // 사용자 폴더의 {유저이름}.json 파일의 exp와 lv 업데이트
      final userExpPath = p.join(Directory.current.path, 'db', 'users', id, '$id.json');
      final userExpFile = File(userExpPath);
      if (await userExpFile.exists()) {
        final userExpData = jsonDecode(await userExpFile.readAsString());

        if (userExpData['u_exp'] < 90) {
          userExpData['u_exp'] += 10;
        } else {
          userExpData['u_exp'] = 0;
          userExpData['u_lv'] += 1;
        }
        await userExpFile.writeAsString(jsonEncode(userExpData), mode: FileMode.write);
      }
    }

    return Response(200);
  });

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router);

  final server = await io.serve(handler, '0.0.0.0', 8080);

  print('Server listening on port ${server.port}');
}
