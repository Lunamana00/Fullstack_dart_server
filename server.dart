/*
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as p;

class UserService {
  final String jsonFilePath;
  final String userFolderBasePath;

  UserService(String basePath)
      : jsonFilePath = p.join(basePath, './db/users.json'),
        userFolderBasePath = p.join(basePath, './db/users');

  Future<List<dynamic>> _readUsersFromFile() async {
    File file = File(jsonFilePath);
    if (await file.exists()) {
      final contents = await file.readAsString();
      if (contents.isNotEmpty) {
        final decoded = jsonDecode(contents);
        if (decoded is List) {
          return decoded;
        }
      }
    }
    return [];
  }

  Future<void> _writeUsersToFile(List<dynamic> users) async {
    File file = File(jsonFilePath);
    await file.writeAsString(jsonEncode(users), mode: FileMode.write);
  }

  Future<Response> registerUser(Request request) async {
    final payload = await request.readAsString();
    final newUser = jsonDecode(payload);

    List<dynamic> users = await _readUsersFromFile();

    final existingUser = users.firstWhere((user) => user['id'] == newUser['id'], orElse: () => null);

    if (existingUser != null) {
      return Response(101); // id 중복 오류
    }

    users.add(newUser);
    await _writeUsersToFile(users);

    final userFolder = Directory(p.join(userFolderBasePath, newUser['id']));
    if (!(await userFolder.exists())) {
      await userFolder.create(recursive: true);
    }

    final userInitialData = {
      'name': newUser['name'],
      'id': newUser['id'],
      'char_type': newUser['char_type'],
      'u_lv': 0,
      'u_exp': 0,
      'change': 0
    };
    final subjectData = {'lv': 0, 'exp': 0, 'dates': []};

    await _writeUserFiles(newUser['id'], userInitialData, subjectData);

    return Response(200);
  }

  Future<void> _writeUserFiles(String id, Map<String, dynamic> userInitialData, Map<String, dynamic> subjectData) async {
    final userFolder = Directory(p.join(userFolderBasePath, id));
    final userJsonFile = File(p.join(userFolder.path, '$id.json'));
    final AJsonFile = File(p.join(userFolder.path, '${id}_A.json'));
    final BJsonFile = File(p.join(userFolder.path, '${id}_B.json'));
    final CJsonFile = File(p.join(userFolder.path, '${id}_C.json'));
    final DJsonFile = File(p.join(userFolder.path, '${id}_D.json'));

    await userJsonFile.writeAsString(jsonEncode(userInitialData), mode: FileMode.write);
    await AJsonFile.writeAsString(jsonEncode(subjectData), mode: FileMode.write);
    await BJsonFile.writeAsString(jsonEncode(subjectData), mode: FileMode.write);
    await CJsonFile.writeAsString(jsonEncode(subjectData), mode: FileMode.write);
    await DJsonFile.writeAsString(jsonEncode(subjectData), mode: FileMode.write);
  }

  Future<Response> loginUser(Request request) async {
    final payload = await request.readAsString();
    final loginData = jsonDecode(payload);

    List<dynamic> users = await _readUsersFromFile();

    final existingUser = users.firstWhere(
      (user) => user['id'] == loginData['id'] && user['pw'] == loginData['pw'],
      orElse: () => null,
    );

    if (existingUser != null) {
      return Response.ok(jsonEncode(existingUser), headers: {'Content-Type': 'application/json'});
    } else {
      return Response(201);
    }
  }

  Future<Response> getUserInfo(Request request, String id) async {
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
      return Response.ok(jsonEncode(response_data), headers: {'Content-Type': 'application/json'});
    } else {
      return Response(500, body: 'User data file not found');
    }
  }

  Future<Response> uploadRecord(Request request) async {
    final payload = await request.readAsString();
    final data = jsonDecode(payload);

    final String id = data['id'];
    final String date = data['date'];
    final String subject = data['icon'];
    final List<String> images = data['images'] != null ? List<String>.from(data['images']) : [];
    final String comment = data['comment'] ?? '';

    final SavePath = p.join(userFolderBasePath, id, date, '$subject.json');

    final userFolder = Directory(p.dirname(SavePath));
    final recordFile = File(SavePath);

    if (!(await userFolder.exists())) {
      await userFolder.create(recursive: true);
    }

    final recordData = {
      'comment': comment,
      'images': images,
    };

    await recordFile.writeAsString(jsonEncode(recordData), mode: FileMode.write);

    Map<String, dynamic> responseData = {};
    if (subject != 'ETC') {
      responseData = await _updateExpAndLevel(id, date, subject);
    }

    return Response.ok(jsonEncode(responseData), headers: {'Content-Type': 'application/json'});
  }

  Future<Map<String, dynamic>> _updateExpAndLevel(String id, String date, String subject) async {
    final subjectExpPath = p.join(userFolderBasePath, id, '${id}_$subject.json');
    final subjectExpFile = File(subjectExpPath);
    Map<String, dynamic> subjectExpData;
    if (await subjectExpFile.exists()) {
      subjectExpData = jsonDecode(await subjectExpFile.readAsString());
      subjectExpData['dates'] = subjectExpData['dates'] ?? [];
    } else {
      subjectExpData = {'lv': 0, 'exp': 0, 'dates': []};
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

    final userExpPath = p.join(userFolderBasePath, id, '$id.json');
    final userExpFile = File(userExpPath);
    Map<String, dynamic> userExpData = {};
    if (await userExpFile.exists()) {
      userExpData = jsonDecode(await userExpFile.readAsString());

      userExpData['u_exp'] = (userExpData['u_exp'] ?? 0) + 10;
      if (userExpData['u_exp'] >= 100) {
        userExpData['u_exp'] = 0;
        userExpData['u_lv'] = (userExpData['u_lv'] ?? 0) + 1;
      }
      await userExpFile.writeAsString(jsonEncode(userExpData), mode: FileMode.write);
    }

    return {
      'subjectExp': subjectExpData['exp'],
      'subjectLevel': subjectExpData['lv'],
      'userExp': userExpData['u_exp'],
      'userLevel': userExpData['u_lv']
    };
  }

  Future<Response> getRecord(Request request, String id, String date) async {
    final recordFolder = Directory(p.join(userFolderBasePath, id, date));
    if (await recordFolder.exists()) {
      final records = recordFolder
          .listSync()
          .where((file) => file is File && p.extension(file.path) == '.json')
          .map((file) {
            final content = jsonDecode(File(file.path).readAsStringSync());
            content['subject'] = p.basenameWithoutExtension(file.path);
            return content;
          })
          .toList();
      return Response.ok(jsonEncode(records), headers: {'Content-Type': 'application/json'});
    } else {
      return Response.ok(jsonEncode([]), headers: {'Content-Type': 'application/json'});
    }
  }

  Future<Response> getRanking(Request request) async {
    List<dynamic> users = await _readUsersFromFile();

    users.sort((a, b) {
      int aScore = (a['u_lv'] ?? 0) * 100 + (a['u_exp'] ?? 0);
      int bScore = (b['u_lv'] ?? 0) * 100 + (b['u_exp'] ?? 0);
      return bScore.compareTo(aScore); // 내림차순 정렬
    });

    List<Map<String, dynamic>> rankingData = [];
    for (int i = 0; i < users.length; i++) {
      rankingData.add({
        'rank': i + 1,
        'name': users[i]['name'],
        'level': users[i]['u_lv'] ?? 0,
        'change': users[i]['change'] ?? 0,
        'categories': ['코딩', '독서', '운동', '음악']
      });
    }

    return Response.ok(jsonEncode(rankingData), headers: {'Content-Type': 'application/json'});
  }
}

void main() async {
  final userService = UserService(Directory.current.path);
  final router = Router();

  router.post('/register', userService.registerUser);
  router.post('/login', userService.loginUser);
  router.get('/user_info/<id>', userService.getUserInfo);
  router.post('/upload', userService.uploadRecord);
  router.get('/record/<id>/<date>', userService.getRecord);
  router.get('/ranking', userService.getRanking);

  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(router);

  final server = await io.serve(handler, '0.0.0.0', 8080);

  print('Server listening on port ${server.port}');
}
