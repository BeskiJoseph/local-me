import 'package:flutter/material.dart';
import '../../widgets/primary_button.dart';
import '../../models/signup_data.dart';
import 'signup_profile.dart';

import 'package:geolocator/geolocator.dart';
import '../../services/geocoding_service.dart';

class SignupLocationScreen extends StatefulWidget {
  final SignupData data;
  const SignupLocationScreen({super.key, required this.data});

  @override
  State<SignupLocationScreen> createState() => _SignupLocationScreenState();
}

class _SignupLocationScreenState extends State<SignupLocationScreen> {
  final locationController = TextEditingController();
  bool _isLoading = false;

  Future<void> _detectLocation() async {
    setState(() => _isLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception(
            'Location permissions are permanently denied, we cannot request permissions.');
      }

      final position = await Geolocator.getCurrentPosition();
      
      try {
        final place = await GeocodingService.getPlace(
           position.latitude, 
           position.longitude
        );

        if (place['full_location'] != null) {
          final locationString = place['full_location']!;
          locationController.text = locationString;
          widget.data.location = locationString; // Save to data
          return;
        } 
      } catch (e) {
         // Fallback
      }

      locationController.text = "Unknown Location";
      widget.data.location = "Unknown Location"; 

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Location")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "We need your location to show you content around you.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 30),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _detectLocation,
                  icon: const Icon(Icons.location_on),
                  label: const Text("Detect My Location"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            TextField(
               controller: locationController,
               decoration: const InputDecoration(
                 hintText: "Or enter manually",
                 border: OutlineInputBorder(),
                 suffixIcon: Icon(Icons.edit_location),
               ),
            ),
            const Spacer(),
            PrimaryButton(
              text: "Next",
              onTap: () {
                if (locationController.text.isEmpty) {
                   ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please set your location')),
                   );
                   return;
                }
                widget.data.location = locationController.text;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SignupProfileScreen(data: widget.data),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
