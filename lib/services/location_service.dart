import 'dart:async';
import 'package:eco_taksi/main.dart' show sdkContext;
import 'package:dgis_mobile_sdk_full/dgis.dart' as sdk;
import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  sdk.Context? _sdkContext;
  StreamSubscription<Position>? _positionStream;

  final StreamController<String> _addressController = StreamController<String>.broadcast();
  Stream<String> get addressStream => _addressController.stream;

  String _currentAddress = 'Ош';
  String get currentAddress => _currentAddress;

  Future<void> initialize() async {
    try {
      _sdkContext = sdkContext;
      _addressController.add(_currentAddress);

      await _requestLocationPermission();
      await _startLocationTracking();
    } catch (_) {
      _setAddressFallback();
    }
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _setAddressFallback();
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _setAddressFallback();
      await Geolocator.openAppSettings();
      return;
    }
  }

  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      _setAddressFallback();
      return;
    }

    // Сразу получаем адрес при старте
    await getCurrentLocation();

    // Поток обновлений
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 50,
      ),
    ).listen((position) async {
      await _updateAddressFromCoordinates(position.latitude, position.longitude);
    }, onError: (_) {
      _setAddressFallback();
    });
  }

  Future<void> getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _updateAddressFromCoordinates(position.latitude, position.longitude);
    } catch (_) {
      _setAddressFallback();
    }
  }

  Future<void> _updateAddressFromCoordinates(double latitude, double longitude) async {
    try {
      if (_sdkContext == null) {
        _setAddressFallback();
        return;
      }

      final searchManager = sdk.SearchManager.createOnlineManager(_sdkContext!);

      final searchQuery = sdk.SearchQueryBuilder
          .fromGeoPoint(sdk.GeoPoint(
        latitude: sdk.Latitude(latitude),
        longitude: sdk.Longitude(longitude),
      ))
          .setPageSize(1)
          .build();

      final searchResult = await searchManager.search(searchQuery).value;

      String address = '';

      if (searchResult.firstPage != null && searchResult.firstPage!.items.isNotEmpty) {
        final item = searchResult.firstPage!.items.first;

        if (item.address != null) {
          final components = <String>[];

          // улица + номер дома
          for (final component in item.address!.components) {
            component.match(
              streetAddress: (street) {
                if (street.street.isNotEmpty) {
                  String streetText = street.street;
                  if (street.number.isNotEmpty) streetText += ', ${street.number}';
                  components.add(streetText);
                }
              },
              number: (_) {},
              location: (_) {},
            );
          }

          // район и город
          final adminComponents = item.address!.drillDown
              .where((admin) => admin.type == 'district' || admin.type == 'city')
              .map((admin) => admin.name)
              .where((name) => name.isNotEmpty)
              .toList();

          components.addAll(adminComponents);

          if (components.isNotEmpty) {
            address = components.join(', ');
          }
        }

        // fallback на название объекта
        if (address.isEmpty && item.title.isNotEmpty) {
          address = item.title;
        }
      }

      if (address.isEmpty) _setAddressFallback();
      else {
        _currentAddress = address;
        _addressController.add(_currentAddress);
      }
    } catch (_) {
      _setAddressFallback();
    }
  }

  void _setAddressFallback() {
    _currentAddress = 'Ош';
    _addressController.add(_currentAddress);
  }

  void dispose() {
    _positionStream?.cancel();
    _addressController.close();
  }
}