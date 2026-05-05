import 'dart:async';
import 'dart:math';

import 'package:eco_taksi/main.dart' show sdkContext, isSdkInitialized;
import 'package:dgis_mobile_sdk_full/dgis.dart' as sdk;
import 'package:eco_taksi/screens/main/widgets/comment_for_driver_box.dart';
import 'package:eco_taksi/screens/main/widgets/order_box.dart';
import 'package:eco_taksi/screens/main/widgets/panel_box.dart';
import 'package:eco_taksi/screens/main/widgets/payment_box.dart';
import 'package:eco_taksi/screens/main/widgets/search_box_bottom.dart';
import 'package:eco_taksi/screens/main/widgets/search_route_bottom.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/location_service.dart';
import '../../services/order_service.dart';
import '../../services/client_websocket_service.dart';
import '../../styles/app_colors.dart';
import '../../styles/app_text_styles.dart';
import '../../styles/app_spacing.dart';
import '../../services/auth_service.dart';
import '../../utils/safe_data.dart';
import '../profile/profile_screen.dart';
import '../orders/searching_driver_screen.dart';
import '../orders/driver_on_way_screen.dart';
import '../orders/trip_in_progress_screen.dart';
import '../orders/order_review_screen.dart';
import '../security/security_screen.dart';
import '../orders/order_history_screen.dart';
import '../support/support_screen.dart';
import '../info/info_screen.dart';
import '../auth/phone_auth_screen.dart';
import '../payment/payment_method_screen.dart';
import 'widgets/order_another_human.dart';

class SimpleMainScreen extends StatefulWidget {
  const SimpleMainScreen({super.key});

  @override
  State<SimpleMainScreen> createState() => _SimpleMainScreenState();
}

class _SimpleMainScreenState extends State<SimpleMainScreen> with TickerProviderStateMixin {
  String _userName = 'Пользователь';
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;
  sdk.SearchManager? _searchManager;

  sdk.Map? _sdkMap;
  StreamSubscription<sdk.Location?>? locationSubscription;
  bool _isSelectingPoint = false;
  sdk.GeoPoint? _selectedPointDestination;
  sdk.GeoPoint? _selectedPointAddress;
  sdk.TrafficRoute? _currentRoute;
  sdk.RouteMapObjectSource? _routeSource;
  String _routeInfo = '';
  Offset? _selectedPointScreenPosition;

  String? _selectedAddress;
  String? _destinationAddress;

  String _routeDistance = '';
  
  double? _destinationLatitude;
  double? _destinationLongitude;


  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final LocationService _locationService = LocationService();

  final _mapWidgetController = sdk.MapWidgetController();

  // Новая логика

  bool _isonShowSearchAddressBottom = false;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _initSdkAndMap();
    _initializeLocation();
    _searchManager = sdk.SearchManager.createOnlineManager(sdkContext);
    _initializeWebSocketAndOrderService();

    // Инициализация анимации пульсации
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Запуск анимации
    _animationController.repeat(reverse: true);
  }

  void _initializeLocation() {
    _locationService.initialize();
    _locationService.addressStream.listen((address) {
      if (mounted) {
        setState(() {
          _selectedAddress = address;
        });
      }
    });
  }

  Future<void> _initSdkAndMap() async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      print("Разрешение на геолокацию не предоставлено");
      return;
    }

    final locationService = sdk.LocationService(sdkContext);


    // Получаем карту асинхронно
    _mapWidgetController.getMapAsync((m) async {
      _sdkMap = m;

      // Добавляем "синюю точку" на карту
      final locationSource = sdk.MyLocationMapObjectSource(
        sdkContext,
        const sdk.MyLocationControllerSettings(
          bearingSource: sdk.BearingSource.satellite,
        ),
      );
      _sdkMap?.addSource(locationSource);

      final loc = await locationService.lastLocation().firstWhere(
        (l) => l != null,
      ).timeout(const Duration(seconds: 5), onTimeout: () => null);

      if (loc != null) {
        final cameraPos = sdk.CameraPosition(
          point: loc.coordinates.value,
          zoom: const sdk.Zoom(15),
        );
        _sdkMap?.camera.moveToCameraPosition(
          cameraPos,
          const Duration(milliseconds: 500),
          sdk.CameraAnimationType.linear,
        );
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeWebSocketAndOrderService() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clientPhone = prefs.getString('client_phone');
      
      if (clientPhone != null && clientPhone.isNotEmpty) {
        await ClientWebSocketService().connect(clientPhone);
        await OrderService().loadCurrentOrderFromPrefs();
        
        final currentOrder = OrderService().currentOrder;
        if (currentOrder != null && mounted) {
          final status = currentOrder['status'];
          print('🔍 [SimpleMain] Active order found with status: $status');
          
          _navigateToOrderScreen(currentOrder, status);
        }
      }
    } catch (e) {
      print('❌ [SimpleMain] Error initializing WebSocket/OrderService: $e');
    }
  }

  void _navigateToOrderScreen(Map<String, dynamic> orderData, String status) {
    Widget? screen;
    
    switch (status) {
      case 'received':
        screen = SearchingDriverScreen(orderData: orderData);
        break;
      case 'accepted':
      case 'navigating_to_a':
      case 'arrived_at_a':
        screen = DriverOnWayScreen(orderData: orderData);
        break;
      case 'navigating_to_b':
        screen = TripInProgressScreen(orderData: orderData);
        break;
      case 'completed':
        screen = OrderReviewScreen(orderData: orderData);
        break;
      default:
        return;
    }
    
    if (screen != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => screen!),
      );
    }
  }

  Future<void> _loadUserName() async {
    try {
      final clientData = await AuthService.getCurrentClient();
      if (clientData != null && mounted) {
        final firstName = SafeData.getString(clientData, 'first_name');
        final lastName = SafeData.getString(clientData, 'last_name');
        setState(() {
          _userName = '$firstName $lastName'.trim();
          if (_userName.isEmpty) {
            _userName = 'Пользователь';
          }
        });
      }
    } catch (e) {
      print('Error loading user name: $e');
    }
  }

  void onShowSearchAddressBottom() => setState(() => _isonShowSearchAddressBottom = !_isonShowSearchAddressBottom);

  @override
  Widget build(BuildContext context) {
    if (!isSdkInitialized) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Инициализация карт...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _buildDrawer(),
      body: GestureDetector(
        onTapDown:  _isSelectingPoint ? _onMapTap : null,
        child: sdk.MapWidget(
          sdkContext: sdkContext,
          mapOptions: sdk.MapOptions(),
          controller: _mapWidgetController,
          child: Stack(
            children: [
              // Верхняя панель с адресом и поиском (скрывается в режиме выбора точки)
              if (!_isSelectingPoint)
                PanelBox(onTap: onShowSearchAddressBottom),


            // Панель выбора точки (показывается только в режиме выбора)
            if (_isSelectingPoint)
              _buildPointSelectionPanel(),

            // Информация о маршруте (показывается после построения маршрута)
            if (_routeInfo.isNotEmpty && !_isSelectingPoint)
              _buildRouteInfoPanel(),

            // Визуальный маркер выбранной точки
            if (_selectedPointScreenPosition != null && _isSelectingPoint)
              _buildMarkerOverlay(),

            // sdk.DashboardWidget(
            //   controller: sdk.DashboardController(navigationManager: sdk.NavigationManager(sdkContext), map: _sdkMap!),
            // ),

            // // Маркер выбранной точки
            // if (_selectedPoint != null && _isSelectingPoint)
            //   _buildSelectedPointMarker(),

              if(_isonShowSearchAddressBottom)...[
                Align(
                  alignment: Alignment.bottomCenter,
                  child: DraggableScrollableSheet(
                    initialChildSize: 0.3,
                    minChildSize: 0.3,
                    maxChildSize: 0.9,
                    shouldCloseOnMinExtent: false,
                    expand: false,
                    builder: (context, scrollController) {
                      print('🔧 === BEFORE PASSING TO SearchRouteBottom ===');
                      print('📍 _selectedPointAddress: $_selectedPointAddress');
                      print('📍 _selectedPointDestination: $_selectedPointDestination');
                      print('📝 _selectedAddress: $_selectedAddress');
                      print('📝 _destinationAddress: $_destinationAddress');
                      print('📏 _routeDistance: $_routeDistance');
                      
                      return SearchRouteBottom(
                        routeDistance: _routeDistance,
                        controller: scrollController,
                        onTap: onSearchBottom,
                        onTapDestinationAddress: onSearchBottom2,
                        onShowCommentBottom: onCommentForDiverBottom,
                        onShowOrderAnotherHumanBottom: onOrderAnotherHumanBottom,
                        onShowPaymentBottom: onOPaymentBoxBottom,
                        onShowOrderBoxBottom: onOrderBoxBottom,
                        sdkContext: sdkContext,
                        selectedAddress: _selectedAddress ?? 'Ош',
                        destinationAddress: _destinationAddress ?? 'Выберите адрес',
                        pickupLatitude: _selectedPointAddress?.latitude.value,
                        pickupLongitude: _selectedPointAddress?.longitude.value,
                        destinationLatitude: _destinationLatitude,
                        destinationLongitude: _destinationLongitude,
                      );
                    },
                  ),
                ),
              ]

            ],
          ),
        ),
      ),
    );
  }

  // void onShowSearchAddressBottom() {
  //   // onSearchBottom();
  //   _scaffoldKey.currentState?.showBottomSheet(
  //     (context) {
  //       return PopScope(
  //         canPop: false,
  //         child: DraggableScrollableSheet(
  //           initialChildSize: 0.3,
  //           minChildSize: 0.3,
  //           maxChildSize: 0.9,
  //           shouldCloseOnMinExtent: false,
  //           expand: false,
  //           builder: (context, scrollController) {
  //             return SearchRouteBottom(
  //               controller: scrollController,
  //               onTap: onSearchBottom,
  //               onShowCommentBottom: onCommentForDiverBottom,
  //               onShowOrderAnotherHumanBottom: onOrderAnotherHumanBottom,
  //               onShowPaymentBottom: onOPaymentBoxBottom,
  //               onShowOrderBoxBottom: onOrderBoxBottom,
  //               sdkContext: sdkContext,
  //               selectedAddress: _selectedAddress ?? 'Ош',
  //             );
  //           },
  //         ),
  //       );
  //     },
  //     backgroundColor: Colors.transparent,
  //     showDragHandle: false,
  //     enableDrag: false,
  //   );
  // }

  void onSearchBottom() {
    showModalBottomSheet(
      isScrollControlled: true,
      useSafeArea: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: SearchBoxBottom(isWherePoint: true),
        );
      },
    ).then((result) {
      print('RESULR: $result');
      if (result != null && result['action'] == 'select_point') {
        // Переключаемся в режим выбора точки
        setState(() {
          _isSelectingPoint = true;
        });
      }else if (result != null && result['where'] == true && result['coordinates'] != null) {
        // Если выбрана точка из поиска, устанавливаем её как выбранную
        setState(() {
          _selectedAddress = result['title'];
          _selectedPointAddress = result['coordinates'];
          _isSelectingPoint = false;
        });
        print('_selectedAddress:$_selectedPointAddress');
        // onShowSearchAddressBottom;

        // Строим маршрут к выбранной точке
       if(_selectedPointDestination != null) _buildRouteToSelectedPoint();
      }
    });
  }

  void onSearchBottom2() {
    showModalBottomSheet(
      isScrollControlled: true,
      useSafeArea: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: SearchBoxBottom(isWherePoint: false),
        );
      },
    ).then((result) {
      print('🔍 === SEARCH RESULT FOR DESTINATION ===');
      print('📦 Full result: $result');
      
      if (result == null) {
        print('⚠️ Result is null');
        return;
      }
      
      print('🎯 where: ${result['where']}');
      print('📝 title: ${result['title']}');
      print('📍 coordinates: ${result['coordinates']}');
      print('🎬 action: ${result['action']}');
      
      // Обрабатываем результат от SearchBoxBottom
      if (result['action'] == 'select_point') {
        print('✅ Switching to point selection mode');
        // Переключаемся в режим выбора точки
        setState(() {
          _isSelectingPoint = true;
        });
      } else if(result['where'] == false && result['coordinates'] != null) {
        print('✅ Setting destination from search:');
        print('   Address: ${result['title']}');
        print('   Coordinates: ${result['coordinates']}');
        final sdk.GeoPoint coords = result['coordinates'];
        setState(() {
          _destinationAddress = result['title'];
          _selectedPointDestination = coords;
          _destinationLatitude = coords.latitude.value;
          _destinationLongitude = coords.longitude.value;
          _isSelectingPoint = false;
        });
        print('✅ Destination set successfully');
        print('   _destinationAddress: $_destinationAddress');
        print('   _selectedPointDestination: $_selectedPointDestination');
        print('   _destinationLatitude: $_destinationLatitude');
        print('   _destinationLongitude: $_destinationLongitude');
        _buildRouteToSelectedPoint();
      } else {
        print('⚠️ Result does not match any condition');
        print('   where == false: ${result['where'] == false}');
        print('   coordinates != null: ${result['coordinates'] != null}');
      }
      print('🏁 === END SEARCH RESULT ===');
    });
  }

  void onCommentForDiverBottom() {
    showModalBottomSheet(
      isScrollControlled: true,
      useSafeArea: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: CommentForDriverBox(),
        );
      },
    );
  }

  void onOrderAnotherHumanBottom() {
    showModalBottomSheet(
      isScrollControlled: true,
      useSafeArea: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: OrderAnotherHuman(),
        );
      },
    );
  }

  void onOPaymentBoxBottom() {
    showModalBottomSheet(
      isScrollControlled: true,
      useSafeArea: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.4,
          child: PaymentBox(),
        );
      },
    );
  }

  // void onOrderBoxBottom() {
  //   showModalBottomSheet(
  //     isScrollControlled: true,
  //     useSafeArea: true,
  //     context: context,
  //     backgroundColor: Colors.transparent,
  //     builder: (context) {
  //       return FractionallySizedBox(
  //         heightFactor: 0.4,
  //         child: OrderBox(),
  //       );
  //     },
  //   );
  // }

  void onOrderBoxBottom() {
    // onSearchBottom();
    _scaffoldKey.currentState?.showBottomSheet(
          (context) {
        return PopScope(
          canPop: false,
          child: DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            shouldCloseOnMinExtent: false,
            expand: false,
            builder: (context, scrollController) {
              return OrderBox();
            },
          ),
        );
      },
      backgroundColor: Colors.transparent,
      showDragHandle: false,
    );
  }


  Widget _buildPointSelectionPanel() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.touch_app,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Нажмите на карту, чтобы выбрать точку',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _cancelPointSelection,
                  icon: const Icon(Icons.close),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            if (_selectedPointDestination != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Выбранная точка: $_destinationAddress',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _confirmPointSelection,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Подтвердить',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelPointSelection,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(color: AppColors.textSecondary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        'Отмена',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }


  void _cancelPointSelection() {
    setState(() {
      _isSelectingPoint = false;
      _selectedPointDestination = null;
      _selectedPointScreenPosition = null;
    });
  }

  void _confirmPointSelection() async {
    if (_selectedPointDestination != null) {
      // Строим маршрут от текущей позиции до выбранной точки
      await _buildRouteToSelectedPoint();
    }

    _cancelPointSelection();
  }

  void _onMapTap(TapDownDetails details) async {
    if (_isSelectingPoint && _sdkMap != null) {
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final localPosition = renderBox.globalToLocal(details.globalPosition);

      // Получаем текущую позицию камеры
      final cameraPosition = _sdkMap!.camera.position;
      final centerPoint = cameraPosition.point;
      final zoom = cameraPosition.zoom.value;

      // Размеры экрана
      final screenSize = MediaQuery.of(context).size;
      final screenCenterX = screenSize.width / 2;
      final screenCenterY = screenSize.height / 2;

      // Смещение от центра экрана в пикселях
      final deltaX = localPosition.dx - screenCenterX;
      final deltaY = localPosition.dy - screenCenterY;

      // Конвертация пикселей в градусы (приближенная формула для Меркатора)
      // Коэффициент зависит от zoom level
      final metersPerPixel = 156543.03392 * cos(centerPoint.latitude.value * pi / 180) / pow(2, zoom);

      // Конвертируем пиксели в метры, затем в градусы
      final deltaLat = -(deltaY * metersPerPixel) / 111111; // 1 градус ≈ 111км
      final deltaLng = (deltaX * metersPerPixel) / (111111 * cos(centerPoint.latitude.value * pi / 180));

      final selectedLat = centerPoint.latitude.value + deltaLat;
      final selectedLng = centerPoint.longitude.value + deltaLng;

      final newPoint = sdk.GeoPoint(
        latitude: sdk.Latitude(selectedLat),
        longitude: sdk.Longitude(selectedLng),
      );

      final address = await _getAddressFromCoordinates(newPoint);

      setState(() {
        _selectedPointDestination = newPoint;
        _destinationAddress = address ?? 'Адрес не найден';
        _destinationLatitude = newPoint.latitude.value;
        _destinationLongitude = newPoint.longitude.value;
        _selectedPointScreenPosition = localPosition;
      });

      print('Выбрана точка: $selectedLat, $selectedLng');
      print('Сохранены координаты: $_destinationLatitude, $_destinationLongitude');
      print('Центр камеры: ${centerPoint.latitude.value}, ${centerPoint.longitude.value}');
      print('Zoom: $zoom');
    }
  }

  Future<String?> _getAddressFromCoordinates(sdk.GeoPoint point) async {
    try {
      // Создаем поисковый запрос по координатам
      final searchQuery = sdk.SearchQueryBuilder
          .fromGeoPoint(point)
          .build();

      // Выполняем поиск
      final sdk.SearchResult result = await _searchManager!.search(searchQuery).value;

      if (result.firstPage != null && result.firstPage!.items.isNotEmpty) {
        final obj = result.firstPage!.items.first;

        // Используем существующий метод для форматирования адреса
        return obj.title;
      }

      return null;
    } catch (e) {
      debugPrint('Ошибка обратного геокодирования: $e');
      return null;
    }
  }


  Future<void> _buildRouteToSelectedPoint() async {
    print('🗺️ === BUILD ROUTE START ===');
    print('📍 _selectedPointDestination: $_selectedPointDestination');
    print('📍 _selectedPointAddress: $_selectedPointAddress');
    
    if (_selectedPointDestination == null || _sdkMap == null) {
      print('❌ Cannot build route: destination=$_selectedPointDestination, map=$_sdkMap');
      return;
    }

    try {
      // Получаем текущую позицию пользователя
      final currentLocation =  await _getCurrentLocation();
      if (currentLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось определить текущее местоположение'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }


      final currentLocal = sdk.GeoPoint(
        latitude: sdk.Latitude(currentLocation.latitude),
        longitude: sdk.Longitude(currentLocation.longitude),
      );

      setState(() {
        _selectedPointAddress = currentLocal;
      });


      // Создаем точки маршрута
      final startPoint = _selectedPointAddress != null ? sdk.RouteSearchPoint(coordinates: _selectedPointAddress!) : sdk.RouteSearchPoint(
        coordinates: currentLocal,
      );

      final finishPoint = sdk.RouteSearchPoint(
        coordinates: _selectedPointDestination!,
      );

      // Настройки маршрута для автомобиля
      final routeSearchOptions = sdk.RouteSearchOptions.car(
        sdk.CarRouteSearchOptions(),
      );

      // Создаем TrafficRouter
      final trafficRouter = sdk.TrafficRouter(sdkContext);

      // Ищем маршрут
      final routesFuture = trafficRouter.findRoute(startPoint, finishPoint, routeSearchOptions);
      final routes = await routesFuture.value;

      if (routes.isNotEmpty) {
        _currentRoute = routes.first;

        // Очищаем предыдущий маршрут если есть
        if (_routeSource != null) {
          _sdkMap!.removeSource(_routeSource!);
        }

        if (_selectedPointDestination != null) {
          final distance = calculateDistanceKm(
            _selectedPointAddress!.latitude.value,
            _selectedPointAddress!.longitude.value,
            _selectedPointDestination!.latitude.value,
            _selectedPointDestination!.longitude.value,
          );

          print('📏 Calculated distance: ${distance.toStringAsFixed(2)} км');
          print('📍 Before setState: _selectedPointDestination = $_selectedPointDestination');
          
          setState(() {
            _routeDistance = distance.toStringAsFixed(2);
          });
          
          print('📍 After setState: _selectedPointDestination = $_selectedPointDestination');
        } else {
          print('⚠️ _selectedPointDestination is null, cannot calculate distance');
        }

        // Создаем источник данных для маршрута
        _routeSource = sdk.RouteMapObjectSource(
          sdkContext,
          sdk.RouteVisualizationType.normal,
        );

        // Добавляем источник на карту
        _sdkMap!.addSource(_routeSource!);

        // Добавляем маршрут на карту
        _routeSource!.addObject(sdk.RouteMapObject(_currentRoute!, true, const sdk.RouteIndex(0)));

        // Получаем информацию о маршруте
        _routeInfo = 'Маршрут построен к точке ${_selectedPointDestination!.latitude.value.toStringAsFixed(4)}, ${_selectedPointDestination!.longitude.value.toStringAsFixed(4)}';

        // Показываем информацию о маршруте
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Маршрут успешно построен'),
            backgroundColor: AppColors.primary,
            duration: const Duration(seconds: 2),
          ),
        );

      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось построить маршрут'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Ошибка построения маршрута: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка построения маршрута: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
    
    print('🏁 === BUILD ROUTE END ===');
    print('📍 Final _selectedPointDestination: $_selectedPointDestination');
    print('📍 Final _selectedPointAddress: $_selectedPointAddress');
    print('📏 Final _routeDistance: $_routeDistance');
  }

  double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // радиус Земли в километрах
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) * cos(_degToRad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c; // результат сразу в км
  }

  double _degToRad(double deg) => deg * pi / 180;

  Future<Position?> _getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
    } catch (e) {
      print('Ошибка получения местоположения: $e');
      return null;
    }
  }


  Widget _buildMarkerOverlay() {
    if (_selectedPointScreenPosition == null) return const SizedBox.shrink();

    return Positioned(
      left: _selectedPointScreenPosition!.dx - 24,
      top: _selectedPointScreenPosition!.dy - 48,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 300),
        tween: Tween(begin: 0.0, end: 1.0),
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                Container(
                  width: 4,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRouteInfoPanel() {
    return Positioned(
      bottom: 100,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.route,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Маршрут построен',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _routeInfo,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _clearRoute,
              icon: const Icon(Icons.close),
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }


  void _clearRoute() {
    if (_routeSource != null && _sdkMap != null) {
      _sdkMap!.removeSource(_routeSource!);
    }
    setState(() {
      _currentRoute = null;
      _routeSource = null;
      _routeInfo = '';
    });
  }


  Future<void> _handleLogout() async {
    // Показываем диалог подтверждения
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход из аккаунта'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      // Показываем индикатор загрузки
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        // Выполняем выход
        await AuthService.logout();

        // Закрываем диалог загрузки
        if (mounted) Navigator.of(context).pop();

        // Перенаправляем на экран авторизации
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const PhoneAuthScreen()),
                (route) => false,
          );
        }
      } catch (e) {
        // Закрываем диалог загрузки
        if (mounted) Navigator.of(context).pop();

        // Показываем ошибку
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка при выходе: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildAnimatedCircle() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 8 * _pulseAnimation.value,
                  spreadRadius: 2 * _pulseAnimation.value,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.8,
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            const SizedBox(height: 20,),
            // Профиль пользователя
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person,
                      color: AppColors.textSecondary,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      _userName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(),

            // Пункты меню
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildDrawerItem('Способ оплаты'),
                  _buildDrawerItem('Безопасность'),
                  _buildDrawerItem('История заказов'),
                  _buildDrawerItem('Настройки'),
                  _buildDrawerItem('Служба поддержки'),
                  _buildDrawerItem('Информация'),
                ],
              ),
            ),

            const Divider(),

            // Выход
            ListTile(
              leading: _buildAnimatedCircle(),
              title: const Text(
                'Выйти',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(context);
                _handleLogout();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(String title) {
    return ListTile(
      leading: _buildAnimatedCircle(),
      title: Text(
        title,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      onTap: () {
        Navigator.pop(context);

        if (title == 'Способ оплаты') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const PaymentMethodScreen(),
            ),
          );
        } else if (title == 'Настройки') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ProfileScreen()),
          ).then((result) {
            // Если профиль был обновлен, перезагружаем данные пользователя
            if (result == true) {
              _loadUserName();
            }
          });
        } else if (title == 'Безопасность') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SecurityScreen()),
          );
        } else if (title == 'История заказов') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OrderHistoryScreen()),
          );
        } else if (title == 'Служба поддержки') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SupportScreen()),
          );
        } else if (title == 'Информация') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const InfoScreen()),
          );
        }
      },
    );
  }

}
