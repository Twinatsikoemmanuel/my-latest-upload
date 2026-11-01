import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

FirebaseOptions? get firebaseOptionsFromEnvironment {
  if (!kIsWeb) return null;

  return const FirebaseOptions(
    apiKey: 'AIzaSyBdRms-jAY7QBASwaPohEheB76G1TJmCtY',
    appId: '1:133709490525:web:6e5ab6c11a85c384dfa0b4',
    messagingSenderId: '133709490525',
    projectId: 'dabtmateapp',
    authDomain: 'dabtmateapp.firebaseapp.com',
    databaseURL: 'https://dabtmateapp-default-rtdb.firebaseio.com',
    storageBucket: 'dabtmateapp.firebasestorage.app',
    measurementId: 'G-1GZ7DN3M76',
  );
}
