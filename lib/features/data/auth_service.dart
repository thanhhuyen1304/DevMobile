import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Đăng ký bằng Email + Password
  Future<User?> signUpWithEmail({
    required String name,
    required String email,
    required String password,
    String role = 'user', // Thêm tham số role, mặc định là 'user'
  }) async {
    try {
      // Validate
      if (email.trim().isEmpty || password.isEmpty) {
        throw FirebaseAuthException(
            code: 'invalid-input', message: 'Email hoặc mật khẩu rỗng');
      }
      if (password.length < 6) {
        throw FirebaseAuthException(
            code: 'weak-password', message: 'Mật khẩu quá yếu');
      }

      if (kDebugMode) {
        print('SignUp: Creating user with email: $email, role: $role');
      }

      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password.trim(),
      );

      User? user = result.user;

      if (user != null) {
        if (kDebugMode) {
          print('SignUp: User created, saving to Firestore: ${user.uid}');
        }
        // Lưu thông tin user lên Firestore
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': name.trim(),
          'email': email.trim().toLowerCase(),
          'role': role, // Lưu role vào Firestore
          'photoUrl': '',
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'fcmToken': '',
        });

        // Cập nhật displayName
        await user.updateDisplayName(name.trim());
      }

      return user;
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print('SignUp Error: ${e.code} - ${e.message}');
      }
      throw _handleAuthException(e);
    } catch (e) {
      if (kDebugMode) {
        print('SignUp Generic Error: $e');
      }
      throw Exception('Lỗi đăng ký: ${e.toString()}');
    }
  }

  // Đăng nhập Email
  Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      if (email.trim().isEmpty || password.isEmpty) {
        throw FirebaseAuthException(
            code: 'invalid-input', message: 'Email hoặc mật khẩu rỗng');
      }

      if (kDebugMode) {
        print('SignIn: Logging in with email: $email');
      }

      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );

      // Cập nhật trạng thái online
      if (result.user != null) {
        await _firestore.collection('users').doc(result.user!.uid).update({
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }

      return result.user;
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print('SignIn Error: ${e.code} - ${e.message}');
      }
      throw _handleAuthException(e);
    }
  }

  // Đăng xuất
  Future<void> signOut() async {
    try {
      String? uid = _auth.currentUser?.uid;
      if (uid != null) {
        await _firestore.collection('users').doc(uid).update({
          'isOnline': false,
          'lastSeen': FieldValue.serverTimestamp(),
        });
      }
      await _auth.signOut();
    } catch (e) {
      if (kDebugMode) {
        print('SignOut Error: $e');
      }
    }
  }

  // Xử lý lỗi
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'Mật khẩu quá yếu, phải ít nhất 6 ký tự';
      case 'email-already-in-use':
        return 'Email này đã được dùng để đăng ký';
      case 'invalid-email':
        return 'Email không hợp lệ';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email hoặc mật khẩu sai';
      case 'operation-not-allowed':
        return 'Email/Password chưa được bật trong Firebase Console';
      case 'too-many-requests':
        return 'Quá nhiều yêu cầu, vui lòng thử lại sau';
      default:
        return 'Lỗi: ${e.message ?? "Không xác định"}';
    }
  }
}
