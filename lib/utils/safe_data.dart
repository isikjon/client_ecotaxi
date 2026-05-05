/// Класс-утилита для безопасной работы с данными из Map (JSON).
/// Предотвращает краши при отсутствии ключей или неверном типе данных.
class SafeData {
  /// Безопасно получить строку. Если ключ отсутствует или значение null, вернет [defaultValue].
  static String getString(Map<String, dynamic>? data, String key, {String defaultValue = ''}) {
    if (data == null || !data.containsKey(key)) return defaultValue;
    final value = data[key];
    if (value == null) return defaultValue;
    return value.toString();
  }

  /// Безопасно получить число (int).
  static int getInt(Map<String, dynamic>? data, String key, {int defaultValue = 0}) {
    if (data == null || !data.containsKey(key)) return defaultValue;
    final value = data[key];
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// Безопасно получить число с плавающей точкой (double).
  static double getDouble(Map<String, dynamic>? data, String key, {double defaultValue = 0.0}) {
    if (data == null || !data.containsKey(key)) return defaultValue;
    final value = data[key];
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  /// Безопасно получить булево значение (bool).
  static bool getBool(Map<String, dynamic>? data, String key, {bool defaultValue = false}) {
    if (data == null || !data.containsKey(key)) return defaultValue;
    final value = data[key];
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      if (lower == 'true' || lower == '1') return true;
      if (lower == 'false' || lower == '0') return false;
    }
    if (value is int) return value == 1;
    return defaultValue;
  }

  /// Безопасно получить вложенный Map.
  static Map<String, dynamic> getMap(Map<String, dynamic>? data, String key) {
    if (data == null || !data.containsKey(key)) return {};
    final value = data[key];
    if (value is Map<String, dynamic>) return value;
    return {};
  }

  /// Безопасно получить список.
  static List<T> getList<T>(Map<String, dynamic>? data, String key) {
    if (data == null || !data.containsKey(key)) return [];
    final value = data[key];
    if (value is List) {
      try {
        return List<T>.from(value);
      } catch (e) {
        print('⚠️ Error casting list for key $key: $e');
        return [];
      }
    }
    return [];
  }
}
