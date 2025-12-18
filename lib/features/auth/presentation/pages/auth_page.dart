// lib/features/auth/presentation/pages/auth_page.dart
import 'package:flutter/foundation.dart'; // Cho kDebugMode
import 'package:flutter/material.dart';
import '../../data/auth_service.dart';
import '../../../../home_page.dart'; // Import HomePage (nếu có)

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  bool isLogin = true;
  bool isLoading = false;
  String selectedRole = 'user'; // Mặc định role là user

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      if (isLogin) {
        // --- ĐĂNG NHẬP ---
        await _authService.signInWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đăng nhập thành công!'), backgroundColor: Colors.green),
          );
          // Chuyển sang HomePage khi đăng nhập thành công
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomePage()),
          );
        }
      } else {
        // --- ĐĂNG KÝ ---
        await _authService.signUpWithEmail(
          name: _nameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          role: selectedRole, // Truyền role đã chọn
        );
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đăng ký thành công! Vui lòng đăng nhập.'), backgroundColor: Colors.green),
          );
          // Chuyển sang form đăng nhập sau khi đăng ký thành công
          setState(() {
            isLogin = true;
            _passwordController.clear(); // Xóa mật khẩu để người dùng nhập lại
          });
        }
      }
    } on Exception catch (e) {
      if (kDebugMode) {
        print('Exception trong _submit: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepPurple.shade600,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30),
            child: Card(
              elevation: 10,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble, size: 80,
                          color: Colors.deepPurple.shade600),
                      const SizedBox(height: 20),
                      Text(
                        isLogin ? 'Chào mừng trở lại!' : 'Tạo tài khoản mới',
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 30),

                      if (!isLogin) ...[
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Họ và tên',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => value!.trim().isEmpty
                              ? 'Vui lòng nhập tên'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        // Dropdown chọn Role
                        DropdownButtonFormField<String>(
                          value: selectedRole,
                          decoration: const InputDecoration(
                            labelText: 'Vai trò',
                            prefixIcon: Icon(Icons.admin_panel_settings),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'user',
                              child: Text('Người dùng (User)'),
                            ),
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('Quản trị viên (Admin)'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => selectedRole = value);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value!.trim().isEmpty
                            ? 'Vui lòng nhập email'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu',
                          prefixIcon: Icon(Icons.lock),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) => value!.length < 6
                            ? 'Mật khẩu phải từ 6 ký tự'
                            : null,
                      ),
                      const SizedBox(height: 30),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple.shade600,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: isLoading
                              ? const CircularProgressIndicator(
                              color: Colors.white)
                              : Text(
                            isLogin ? 'Đăng nhập' : 'Đăng ký',
                            style: const TextStyle(
                                fontSize: 18, color: Colors.white),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      TextButton(
                        onPressed: () =>
                            setState(() => isLogin = !isLogin),
                        child: Text(
                          isLogin
                              ? 'Chưa có tài khoản? Đăng ký ngay'
                              : 'Đã có tài khoản? Đăng nhập',
                          style: const TextStyle(color: Colors.deepPurple),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
