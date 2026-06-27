import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class MapPickerPage extends StatefulWidget {
  const MapPickerPage({super.key});

  @override
  State<MapPickerPage> createState() => _MapPickerPageState();
}

class _MapPickerPageState extends State<MapPickerPage> {
  LatLng? _pickedLocation;
  final MapController _mapController = MapController();
  bool _isGettingLocation = false;

  static const LatLng _kInitialPosition = LatLng(34.0522, -118.2437); // Default to Los Angeles

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getCurrentLocation();
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied';
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw 'Location permissions are permanently denied, we cannot request permissions.';
      } 

      Position position = await Geolocator.getCurrentPosition();
      final currentLatLng = LatLng(position.latitude, position.longitude);
      
      _mapController.move(currentLatLng, 15);
      setState(() {
        _pickedLocation = currentLatLng;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('შეცდომა: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('მდებარეობის არჩევა (OSM)'),
        actions: [
          if (_pickedLocation != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context, '${_pickedLocation!.latitude.toStringAsFixed(6)}, ${_pickedLocation!.longitude.toStringAsFixed(6)}');
              },
              child: const Text('დადასტურება', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            )
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _kInitialPosition,
              initialZoom: 12,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag | 
                       InteractiveFlag.pinchZoom | 
                       InteractiveFlag.doubleTapZoom | 
                       InteractiveFlag.flingAnimation |
                       InteractiveFlag.pinchMove,
              ),
              onTap: (tapPosition, latLng) {
                setState(() {
                  _pickedLocation = latLng;
                });
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.untitled',
              ),
              if (_pickedLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pickedLocation!,
                      width: 80,
                      height: 80,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pickedLocation == null)
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'დააჭირეთ რუკას წერტილის ასარჩევად ან გამოიყენეთ თქვენი მდებარეობა.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  onPressed: _isGettingLocation ? null : _getCurrentLocation,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                  icon: _isGettingLocation 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location),
                  label: Text(_isGettingLocation ? 'მდებარეობის დადგენა...' : 'ჩემი მდებარეობა'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
