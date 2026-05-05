import 'package:eco_taksi/main.dart' show sdkContext;
import 'package:flutter/material.dart';
import 'package:dgis_mobile_sdk_full/dgis.dart' as sdk;
import 'package:eco_taksi/styles/app_colors.dart';

class SearchBoxBottom extends StatefulWidget {
  const SearchBoxBottom({super.key, required this.isWherePoint});

  final bool isWherePoint;

  @override
  State<SearchBoxBottom> createState() => _SearchBoxBottomState();
}

class _SearchBoxBottomState extends State<SearchBoxBottom> {
  late final sdk.SearchManager _searchManager;
  final TextEditingController _textController = TextEditingController();
  List<sdk.DirectoryObject> _searchResults = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchManager = sdk.SearchManager.createOnlineManager(sdkContext);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final qr = query.trim();
    if (qr.isEmpty || qr.length < 2) {
      setState(() {
        _searchResults.clear();
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Координаты центра Оша
      const oshCenter = sdk.GeoPoint(
        latitude: sdk.Latitude(40.5283),
        longitude: sdk.Longitude(72.7985),
      );

      // Ограничивающий прямоугольник для Оша
      const oshBounds = sdk.GeoRect(
        southWestPoint: sdk.GeoPoint(
          latitude: sdk.Latitude(40.4800),
          longitude: sdk.Longitude(72.7200),
        ),
        northEastPoint: sdk.GeoPoint(
          latitude: sdk.Latitude(40.5800),
          longitude: sdk.Longitude(72.8800),
        ),
      );

      // Создаем поисковый запрос
      final searchQuery = sdk.SearchQueryBuilder
          .fromQueryText(qr)
          .setRadius(const sdk.Meter(15000)) // Радиус поиска 15 км
          .setAreaOfInterest(oshBounds) // Приоритетная область поиска
          .setAllowedResultTypes([
        sdk.ObjectType.building,
        sdk.ObjectType.branch,
        sdk.ObjectType.road,
        sdk.ObjectType.admDivCity,
        sdk.ObjectType.parking,
        sdk.ObjectType.street,
      ])
          .setPageSize(10) // Максимум 10
          .build();

      // Выполняем поиск
      final sdk.SearchResult result = await _searchManager.search(searchQuery).value;

      if (result.firstPage != null && result.firstPage!.items.isNotEmpty) {
        // Показываем все результаты без фильтрации
        setState(() {
          _searchResults = result.firstPage!.items;
        });
      } else {
        setState(() {
          _searchResults.clear();
        });
      }
    } catch (e) {
      debugPrint('Ошибка при поиске: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка при поиске'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _searchResults.clear();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getAddressString(sdk.DirectoryObject obj) {
    if (obj.address != null) {
      final List<String> parts = [];

      // Получаем компоненты адреса (улица, номер дома)
      for (final comp in obj.address!.components) {
        comp.match(
          streetAddress: (street) {
            if (street.street.isNotEmpty) {
              String s = street.street;
              if (street.number.isNotEmpty) {
                s += ', ${street.number}';
              }
              parts.add(s);
            }
          },
          number: (s) {},
          location: (s) {},
        );
      }

      // Добавляем административные единицы в правильном порядке
      // Порядок: settlement (населенный пункт) -> district (район) -> region (область) -> city (город)
      final drillDown = obj.address!.drillDown;

      // Сначала добавляем населенный пункт (село, поселок и т.д.)
      final settlement = drillDown
          .where((d) => d.type == 'settlement' || d.type == 'village')
          .map((d) => d.name)
          .toList();
      parts.addAll(settlement);

      // Затем район
      final district = drillDown
          .where((d) => d.type == 'district' || d.type == 'district_area')
          .map((d) => d.name)
          .toList();
      parts.addAll(district);

      // Затем область/регион
      final region = drillDown
          .where((d) => d.type == 'region' || d.type == 'province')
          .map((d) => d.name)
          .toList();
      parts.addAll(region);

      // И город (если есть и это не повтор)
      final city = drillDown
          .where((d) => d.type == 'city')
          .map((d) => d.name)
          .toList();
      parts.addAll(city);

      if (parts.isNotEmpty) {
        return parts.join(', ');
      }
    }
    return obj.title;
  }

  sdk.GeoPoint? _getObjectCoordinates(sdk.DirectoryObject obj) {
    // Проверяем, есть ли конкретный вход/подъезд
    final entranceId = obj.id?.entranceId ?? 0;
    if (entranceId != 0 && obj.entrances.isNotEmpty) {
      try {
        final entrance = obj.entrances
            .firstWhere((e) => e.id.entranceId == entranceId);
        return entrance.geometry?.entrancePoints.firstOrNull;
      } catch (e) {
        // Fallback на markerPosition если вход не найден
      }
    }
    // Используем позицию маркера по умолчанию
    return obj.markerPosition?.point;
  }

  IconData _getIconForObjectType(sdk.ObjectType type) {
    switch (type) {
      case sdk.ObjectType.building:
        return Icons.business;
      case sdk.ObjectType.branch:
        return Icons.store;
      case sdk.ObjectType.admDivCity:
        return Icons.location_city;
      case sdk.ObjectType.road:
      case sdk.ObjectType.street:
        return Icons.route;
      case sdk.ObjectType.parking:
        return Icons.local_parking;
      default:
        return Icons.place;
    }
  }

  void _onResultTap(sdk.DirectoryObject obj) {
    final coords = _getObjectCoordinates(obj);
    final addr = _getAddressString(obj);
    Navigator.pop(context, {
      'where': widget.isWherePoint,
      'title': obj.title,
      'address': addr,
      'coordinates': coords,
      'directoryObject': obj,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Поле поиска
          TextField(
            controller: _textController,
            decoration: InputDecoration(
              hintText: 'Введите адрес...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _textController.text.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _textController.clear();
                  setState(() {
                    _searchResults.clear();
                  });
                },
              )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (value) {
              setState(() {}); // Обновляем UI для показа кнопки очистки
              // Debounce поиска
              Future.delayed(const Duration(milliseconds: 500), () {
                if (_textController.text == value && mounted) {
                  _performSearch(value);
                }
              });
            },
            onSubmitted: _performSearch,
          ),
          const SizedBox(height: 8),

          // Кнопка "Указать точку на карте"
          if(widget.isWherePoint == false)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context, {'action': 'select_point'});
              },
              icon: const Icon(Icons.location_on, color: Colors.white),
              label: const Text(
                'Указать точку на карте',
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          // Индикатор загрузки
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),

          // Список результатов
          if (!_isLoading && _searchResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                separatorBuilder: (c, i) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final obj = _searchResults[i];
                  final coords = _getObjectCoordinates(obj);

                  return ListTile(
                    leading: Icon(
                      _getIconForObjectType(obj.types.first),
                      color: AppColors.primary,
                    ),
                    title: Text(obj.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_getAddressString(obj)),
                        if (obj.subtitle.isNotEmpty)
                          Text(
                            obj.subtitle,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    onTap: () => _onResultTap(obj),
                  );
                },
              ),
            ),

          // Сообщение "ничего не найдено"
          if (!_isLoading &&
              _textController.text.isNotEmpty &&
              _searchResults.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Ничего не найдено',
                style: TextStyle(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}