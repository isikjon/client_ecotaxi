import 'dart:convert';
import 'package:eco_taksi/services/user_data_service.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../utils/phone_utils.dart';

class ApiService {
  static String get baseUrl => ApiConfig.baseUrl;
  
  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._();
  ApiService._();

  // Регистрация нового клиента
  Future<Map<String, dynamic>> registerClient(Map<String, dynamic> userData) async {
    try {
      // Нормализуем номер телефона в данных пользователя
      if (userData['user'] != null && userData['user']['phoneNumber'] != null) {
        final String originalPhone = userData['user']['phoneNumber'];
        final String normalizedPhone = PhoneUtils.normalizePhoneNumber(originalPhone);
        final String phoneForApi = PhoneUtils.getPhoneForApi(originalPhone);
        userData['user']['phoneNumber'] = normalizedPhone;
        print('📝 Registration - Original phone: $originalPhone');
        print('📝 Registration - Normalized phone: $normalizedPhone');
        print('📝 Registration - Phone for API: $phoneForApi');
        
        // Преобразуем данные в формат snake_case для API
        final Map<String, dynamic> apiData = {
          'phone_number': phoneForApi,
          'first_name': userData['user']['firstName'],
          'last_name': userData['user']['lastName'],
        };
        
        print('Sending registration data: $apiData');
        
        final response = await http.post(
          Uri.parse(ApiConfig.getEndpointUrl('client_register')),
          headers: ApiConfig.defaultHeaders,
          body: json.encode(apiData),
        ).timeout(ApiConfig.connectionTimeout);

        print('Registration response status: ${response.statusCode}');
        print('Registration response body: ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          final responseData = json.decode(response.body);
          return {
            'success': true,
            'data': responseData['data'], // Извлекаем только data из ответа
          };
        } else {
          return {
            'success': false,
            'error': 'Ошибка регистрации: ${response.statusCode}',
            'details': response.body,
          };
        }
      }
      
      return {
        'success': false,
        'error': 'Номер телефона не найден в данных',
      };
    } catch (e) {
      print('Registration error: $e');
      return {
        'success': false,
        'error': 'Ошибка сети: $e',
      };
    }
  }

  // Авторизация клиента (пробуем разные эндпоинты)
  Future<Map<String, dynamic>> loginClient(String phoneNumber, String smsCode) async {
    // Нормализуем номер телефона
    final String normalizedPhone = PhoneUtils.normalizePhoneNumber(phoneNumber);
    final String phoneForApi = PhoneUtils.getPhoneForApi(phoneNumber);
    print('🔑 Original phone: $phoneNumber');
    print('🔑 Normalized phone: $normalizedPhone');
    print('🔑 Phone for API: $phoneForApi');
    
    // Используем правильный эндпоинт для логина
    final List<Map<String, dynamic>> loginEndpoints = [
      {'path': '/api/clients/login', 'params': {'phone_number': phoneForApi, 'sms_code': smsCode}},
    ];

    for (Map<String, dynamic> config in loginEndpoints) {
      try {
        final String endpoint = config['path'];
        final Map<String, dynamic> params = config['params'];
        
        print('🔑 Trying login endpoint: ${ApiConfig.baseUrl}$endpoint');
        print('🔑 Login attempt for: $normalizedPhone with code: $smsCode');
        print('🔑 Using params: $params');
        
        final response = await http.post(
          Uri.parse('${ApiConfig.baseUrl}$endpoint'),
          headers: ApiConfig.defaultHeaders,
          body: json.encode(params),
        ).timeout(ApiConfig.connectionTimeout);

        print('🔑 Login [$endpoint] status: ${response.statusCode}');
        print('🔑 Login [$endpoint] body: ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body);
          
          // Проверяем, действительно ли запрос успешен
          if (data['success'] == true) {
            print('✅ Логин успешен через: $endpoint');
            return {
              'success': true,
              'data': data,
              'isNewUser': data['isNewUser'] ?? data['is_new_user'] ?? false,
              'endpoint': endpoint,
            };
          } else {
            print('❌ Логин неуспешен через: $endpoint - ${data['error']}');
            return {
              'success': false,
              'error': data['error'] ?? 'Ошибка авторизации',
              'details': response.body,
              'endpoint': endpoint,
            };
          }
        } else if (response.statusCode != 404) {
          // Если не 404, значит эндпоинт найден, но есть другая ошибка
          return {
            'success': false,
            'error': 'Ошибка авторизации [$endpoint]: ${response.statusCode}',
            'details': response.body,
            'endpoint': endpoint,
          };
        }
      } catch (e) {
        print('❌ Login error [${config['path']}]: $e');
        continue;
      }
    }
    
    return {
      'success': false,
      'error': 'Не найден рабочий эндпоинт для авторизации. Проверьте документацию API.',
    };
  }

  // Отправка SMS кода через Devino
  Future<Map<String, dynamic>> sendSmsCode(String phoneNumber) async {
    try {
      final normalizedPhone = PhoneUtils.normalizePhoneNumber(phoneNumber);
      print('📱 [ApiService] Отправка SMS через Backend API для: $normalizedPhone');

      final response = await http.post(
        Uri.parse(ApiConfig.getEndpointUrl('sms_send')),
        headers: ApiConfig.defaultHeaders,
        body: json.encode({'phoneNumber': normalizedPhone}),
      ).timeout(ApiConfig.connectionTimeout);

      print('📱 [ApiService] SMS response status: ${response.statusCode}');
      print('📱 [ApiService] SMS response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          print('✅ [ApiService] SMS успешно отправлен через Backend');
          return {
            'success': true,
            'data': responseData,
          };
        } else {
          print('❌ [ApiService] Backend вернул ошибку: ${responseData['detail']}');
          return {
            'success': false,
            'error': responseData['detail'] ?? 'Ошибка отправки SMS',
          };
        }
      } else {
        print('❌ [ApiService] HTTP ошибка: ${response.statusCode}');
        return {
          'success': false,
          'error': 'HTTP ошибка: ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ [ApiService] Критическая ошибка отправки SMS: $e');
      return {
        'success': false,
        'error': 'Ошибка сети: $e',
      };
    }
  }

  // Получить список таксопарков
  Future<Map<String, dynamic>> getParks() async {
    try {
      print('Fetching parks list');
      
      final response = await http.get(
        Uri.parse(ApiConfig.getEndpointUrl('taxiparks')),
        headers: ApiConfig.defaultHeaders,
      ).timeout(ApiConfig.connectionTimeout);

      print('Parks response status: ${response.statusCode}');
      print('Parks response body: ${response.body}');

      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': json.decode(response.body),
        };
      } else {
        return {
          'success': false,
          'error': 'Ошибка загрузки парков: ${response.statusCode}',
          'details': response.body,
        };
      }
    } catch (e) {
      print('Parks fetch error: $e');
      return {
        'success': false,
        'error': 'Ошибка сети: $e',
      };
    }
  }

  // Проверить статус SMS
  Future<Map<String, dynamic>> checkSmsStatus(String phoneNumber) async {
    try {
      // Нормализуем номер телефона
      final String normalizedPhone = PhoneUtils.normalizePhoneNumber(phoneNumber);
      print('📱 SMS Status - Original phone: $phoneNumber');
      print('📱 SMS Status - Normalized phone: $normalizedPhone');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.getEndpointUrl('sms_status')}?phoneNumber=$normalizedPhone'),
        headers: ApiConfig.defaultHeaders,
      ).timeout(ApiConfig.connectionTimeout);

      print('SMS Status response status: ${response.statusCode}');
      print('SMS Status response body: ${response.body}');

      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': json.decode(response.body),
        };
      } else {
        return {
          'success': false,
          'error': 'Ошибка проверки статуса SMS: ${response.statusCode}',
          'details': response.body,
        };
      }
    } catch (e) {
      print('SMS Status check error: $e');
      return {
        'success': false,
        'error': 'Ошибка сети: $e',
      };
    }
  }

  // Тестовое подключение к серверу
  Future<Map<String, dynamic>> testConnection() async {
    try {
      print('📶 Testing connection to server: $baseUrl');
      
      // Проверяем документацию API
      final docsResponse = await http.get(
        Uri.parse('$baseUrl/docs'),
        headers: ApiConfig.defaultHeaders,
      ).timeout(ApiConfig.connectionTimeout);
      
      print('📶 Docs endpoint status: ${docsResponse.statusCode}');
      
      // Проверяем корневой эндпоинт
      final rootResponse = await http.get(
        Uri.parse(baseUrl),
        headers: ApiConfig.defaultHeaders,
      ).timeout(ApiConfig.connectionTimeout);
      
      print('📶 Root endpoint status: ${rootResponse.statusCode}');
      print('📶 Root response: ${rootResponse.body.substring(0, rootResponse.body.length > 200 ? 200 : rootResponse.body.length)}...');
      
      // Проверяем openapi.json для получения списка эндпоинтов
      try {
        final openapiResponse = await http.get(
          Uri.parse('$baseUrl/openapi.json'),
          headers: ApiConfig.defaultHeaders,
        ).timeout(ApiConfig.connectionTimeout);
        
        if (openapiResponse.statusCode == 200) {
          print('📶 OpenAPI spec found! Parsing endpoints...');
          final apiSpec = json.decode(openapiResponse.body);
          final paths = apiSpec['paths'] as Map<String, dynamic>?;
          if (paths != null) {
            print('📶 Available API endpoints:');
            paths.keys.take(10).forEach((path) {
              print('  - $path');
            });
          }
        }
      } catch (e) {
        print('📶 No OpenAPI spec found: $e');
      }

      if (rootResponse.statusCode == 200 || docsResponse.statusCode == 200) {
        return {
          'success': true,
          'data': {
            'status': 'Connected',
            'server': baseUrl,
            'docs_available': docsResponse.statusCode == 200,
            'root_status': rootResponse.statusCode,
          },
        };
      } else {
        return {
          'success': false,
          'error': 'Ошибка подключения: Root(${rootResponse.statusCode}), Docs(${docsResponse.statusCode})',
        };
      }
    } catch (e) {
      print('📶 Connection test error: $e');
      return {
        'success': false,
        'error': 'Ошибка сети: $e',
      };
    }
  }

  // Получить список таксопарков (обновленные эндпоинты)
  Future<Map<String, dynamic>> getTaxiparks() async {
    try {
      print('Fetching taxiparks list from new API');
      
      final response = await http.get(
        Uri.parse(ApiConfig.getEndpointUrl('taxiparks')),
        headers: ApiConfig.defaultHeaders,
      ).timeout(ApiConfig.connectionTimeout);

      print('Taxiparks response status: ${response.statusCode}');
      print('Taxiparks response body: ${response.body}');

      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': json.decode(response.body),
        };
      } else {
        return {
          'success': false,
          'error': 'Ошибка загрузки таксопарков: ${response.statusCode}',
          'details': response.body,
        };
      }
    } catch (e) {
      print('Taxiparks fetch error: $e');
      return {
        'success': false,
        'error': 'Ошибка сети: $e',
      };
    }
  }

  // Обновить профиль клиента
  Future<Map<String, dynamic>> updateClientProfile(Map<String, dynamic> userData) async {
    try {
      print('📝 Updating client profile: $userData');
      
      final response = await http.put(
        Uri.parse(ApiConfig.getEndpointUrl('client_update')),
        headers: ApiConfig.defaultHeaders,
        body: json.encode({
          'first_name': userData['user']['firstName'],
          'last_name': userData['user']['lastName'],
        }),
      ).timeout(ApiConfig.connectionTimeout);

      print('📝 Profile update response status: ${response.statusCode}');
      print('📝 Profile update response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        return {
          'success': true,
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'error': 'Ошибка обновления профиля: ${response.statusCode}',
          'details': response.body,
        };
      }
    } catch (e) {
      print('📝 Profile update error: $e');
      return {
        'success': false,
        'error': 'Ошибка сети: $e',
      };
    }
  }

  // Обновить способ оплаты клиента
  Future<Map<String, dynamic>> updateClientPaymentMethod(int clientId, String paymentMethod) async {
    try {
      print('💳 Updating client payment method: clientId=$clientId, paymentMethod=$paymentMethod');
      
      final response = await http.put(
        Uri.parse(ApiConfig.getEndpointUrl('client_update_payment')),
        headers: ApiConfig.defaultHeaders,
        body: json.encode({
          'client_id': clientId,
          'payment_method': paymentMethod,
        }),
      ).timeout(ApiConfig.connectionTimeout);

      print('💳 Payment method update response status: ${response.statusCode}');
      print('💳 Payment method update response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        return {
          'success': true,
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'error': 'Ошибка обновления способа оплаты: ${response.statusCode}',
          'details': response.body,
        };
      }
    } catch (e) {
      print('💳 Payment method update error: $e');
      return {
        'success': false,
        'error': 'Ошибка сети: $e',
      };
    }
  }

  Future<Map<String, dynamic>> getPartners() async {
    try {
      print('🏢 Getting partners list');
      
      final response = await http.get(
        Uri.parse(ApiConfig.getEndpointUrl('partners')),
        headers: ApiConfig.defaultHeaders,
      ).timeout(ApiConfig.connectionTimeout);

      print('🏢 Partners response status: ${response.statusCode}');
      print('🏢 Partners response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        // API возвращает {"parks": [...], "count": N}
        final parks = responseData['parks'] ?? [];
        
        // Преобразуем данные в нужный формат
        final partnersData = parks.map<Map<String, dynamic>>((park) {
          return {
            'id': park['id'],
            'name': park['name'],
            'commission': park['commission_percent'] ?? 15.0,
            'is_active': true, // API возвращает только активные
            'car_count': 0, // Поле не возвращается API
            'description': park['description'] ?? 'Описание не указано',
            'contact_phone': park['phone'] ?? 'Телефон не указан',
            'contact_email': park['email'] ?? 'Email не указан',
            'city': park['city'] ?? 'Город не указан',
            'address': park['address'] ?? 'Адрес не указан',
            'working_hours': park['working_hours'] ?? 'Часы работы не указаны',
            'created_at': null,
          };
        }).toList();
        
        return {
          'success': true,
          'data': partnersData,
        };
      } else {
        return {
          'success': false,
          'error': 'Ошибка загрузки партнеров: ${response.statusCode}',
          'details': response.body,
        };
      }
    } catch (e) {
      print('🏢 Partners error: $e');
      return {
        'success': false,
        'error': 'Ошибка сети: $e',
      };
    }
  }

  // Получить информацию о API из документации
  static Future<void> printApiInfo() async {
    print('\n🌐 =============== API INFO ===============');
    print('🌐 Base URL: ${ApiConfig.baseUrl}');
    print('🌐 Environment: ${ApiConfig.currentEnvironment}');
    print('🌐 Documentation: ${ApiConfig.baseUrl}/docs');
    print('🌐 Available endpoints:');
    
    ApiConfig.endpoints.forEach((key, value) {
      print('  - $key: ${ApiConfig.baseUrl}$value');
    });
    
    print('🌐 ==========================================\n');
    
    // Тестируем подключение
    final testResult = await ApiService.instance.testConnection();
    if (testResult['success']) {
      print('✅ Server connection: OK');
    } else {
      print('❌ Server connection failed: ${testResult['error']}');
    }
    print('');
  }

  Future<void> deleteAccount() async {
    try {
      await UserDataService.instance.loadFromStorage();
      final userData = UserDataService.instance.userData;
      final phoneNumber = userData['phoneNumber'];

      final encodedPhone = Uri.encodeComponent(phoneNumber);

      final url = Uri.parse(
          '${ApiConfig.getEndpointUrl('delete_account')}?phoneNumber=$encodedPhone'
      );

      final response = await http.delete(
        url,
        headers: ApiConfig.defaultHeaders,
      ).timeout(ApiConfig.connectionTimeout);

      print('✅ deleteAccount response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('✅ deleteAccount success');
      } else {
        print('❌ deleteAccount failed: ${response.body}');
      }
    } catch (e) {
      print('❌ Exception deleting account: $e');
    }
  }

}