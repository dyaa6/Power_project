// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD_IMph6rl00LwIBRz9sxkB_FFpdfhMokY',
    appId: '1:544271253413:web:7a2a7e2808d03cb102b24c',
    messagingSenderId: '544271253413',
    projectId: 'epower-44f2e',
    authDomain: 'epower-44f2e.firebaseapp.com',
    databaseURL: 'https://epower-44f2e-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'epower-44f2e.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB-SC1mSRRLL--KZps5pZmTTKaagfjSfAg',
    appId: '1:544271253413:android:c6c44562112cd76102b24c',
    messagingSenderId: '544271253413',
    projectId: 'epower-44f2e',
    databaseURL: 'https://epower-44f2e-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'epower-44f2e.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCVyQ-8FmZ4RHcJ9Dwkw3On-IV7Klskbgo',
    appId: '1:544271253413:ios:80d654c4d561f8d002b24c',
    messagingSenderId: '544271253413',
    projectId: 'epower-44f2e',
    databaseURL: 'https://epower-44f2e-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'epower-44f2e.firebasestorage.app',
    iosBundleId: 'com.example.power',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCVyQ-8FmZ4RHcJ9Dwkw3On-IV7Klskbgo',
    appId: '1:544271253413:ios:80d654c4d561f8d002b24c',
    messagingSenderId: '544271253413',
    projectId: 'epower-44f2e',
    databaseURL: 'https://epower-44f2e-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'epower-44f2e.firebasestorage.app',
    iosBundleId: 'com.example.power',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyD_IMph6rl00LwIBRz9sxkB_FFpdfhMokY',
    appId: '1:544271253413:web:2735e4eaf83d63cd02b24c',
    messagingSenderId: '544271253413',
    projectId: 'epower-44f2e',
    authDomain: 'epower-44f2e.firebaseapp.com',
    databaseURL: 'https://epower-44f2e-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'epower-44f2e.firebasestorage.app',
  );
}
