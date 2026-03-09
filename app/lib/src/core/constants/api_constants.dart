import 'dart:io';

String apiBaseUrl() {
  if (Platform.isAndroid) return 'http://10.0.2.2:8000';
  // Replace with your Mac's local IP for iOS device testing
  return 'http://192.168.43.78:8000'; 
}

