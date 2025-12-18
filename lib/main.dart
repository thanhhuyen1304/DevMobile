import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'features/auth/presentation/pages/auth_page.dart';

// Key điều hướng toàn cục để Zego có thể điều khiển app từ bên ngoài
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Gán navigatorKey cho Zego Service TRƯỚC KHI RUN APP
  ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);

  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyDDdtP5JE4z6gGCqqR79_KeA-ne9cloGeo",
          authDomain: "chatappfinal-620d3.firebaseapp.com",
          projectId: "chatappfinal-620d3",
          storageBucket: "chatappfinal-620d3.firebasestorage.app",
          messagingSenderId: "713648515500",
          appId: "1:713648515500:web:eb9168b0bb91ed53d2f209",
          measurementId: "G-CWMR96TZVZ",
        ),
      );
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    if (kDebugMode) {
      print('Firebase init error: $e');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App Đồ Án',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.grey.shade50,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          primary: Colors.deepPurple, 
          secondary: Colors.amber,    
          background: Colors.grey.shade50, 
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          },
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: MaterialStateProperty.all(Colors.deepPurple.withOpacity(0.5)),
        ),
        useMaterial3: true,
      ),
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        physics: const BouncingScrollPhysics(),
      ),
      builder: (BuildContext context, Widget? child) {
        return Stack(
          children: [
            child!,
            // Widget này xử lý màn hình chờ cuộc gọi và mini-overlay khi đang gọi
            ZegoUIKitPrebuiltCallMiniOverlayPage(
              contextQuery: () {
                return navigatorKey.currentState!.context;
              },
            ),
          ],
        );
      },
      home: const AuthPage(),
    );
  }
}
