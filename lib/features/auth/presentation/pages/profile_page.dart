import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final User? user = FirebaseAuth.instance.currentUser;
  final _formKey = GlobalKey<FormState>();
  
  // Controllers cho thông tin cá nhân
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController(); // Mới
  final TextEditingController _addressController = TextEditingController(); // Mới
  
  String? _currentImageBase64;
  XFile? _pickedImage;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // Tải thông tin user từ Firestore
  Future<void> _loadUserData() async {
    if (user == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      if (userDoc.exists) {
        Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _emailController.text = data['email'] ?? user!.email ?? '';
          _phoneController.text = data['phone'] ?? ''; // Load SĐT
          _addressController.text = data['address'] ?? ''; // Load Địa chỉ
          _currentImageBase64 = data['imageBase64'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải thông tin: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // Chọn ảnh từ thư viện
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500,
        imageQuality: 60,
      );
      
      if (image != null) {
        setState(() {
          _pickedImage = image;
        });
      }
    } catch (e) {
      print("Lỗi chọn ảnh: $e");
    }
  }

  // Lưu thông tin cá nhân (Không bao gồm mật khẩu)
  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (user == null) return;

    setState(() => _isSaving = true);

    try {
      String? imageBase64ToSave = _currentImageBase64;

      if (_pickedImage != null) {
        final bytes = await _pickedImage!.readAsBytes();
        imageBase64ToSave = base64Encode(bytes);
      }

      // Cập nhật Firestore (Thêm phone, address)
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'imageBase64': imageBase64ToSave ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await user!.updateDisplayName(_nameController.text.trim());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật hồ sơ thành công!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi cập nhật: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- HÀM ĐỔI MẬT KHẨU ---
  void _showChangePasswordDialog() {
    final oldPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();
    final formPassKey = GlobalKey<FormState>();
    bool isUpdatingPass = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            
            Future<void> changePassword() async {
              if (!formPassKey.currentState!.validate()) return;
              
              setStateDialog(() => isUpdatingPass = true);
              
              try {
                String email = user!.email!;
                String oldPass = oldPassController.text;
                String newPass = newPassController.text;

                // 1. Xác thực lại người dùng bằng mật khẩu cũ
                AuthCredential credential = EmailAuthProvider.credential(
                  email: email, 
                  password: oldPass
                );
                
                await user!.reauthenticateWithCredential(credential);

                // 2. Nếu đúng mật khẩu cũ, tiến hành cập nhật mật khẩu mới
                await user!.updatePassword(newPass);

                if (mounted) {
                  Navigator.pop(context); // Tắt dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đổi mật khẩu thành công!'), backgroundColor: Colors.green),
                  );
                }
              } on FirebaseAuthException catch (e) {
                String errorMsg = 'Lỗi đổi mật khẩu';
                if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
                  errorMsg = 'Mật khẩu cũ không chính xác';
                } else if (e.code == 'weak-password') {
                  errorMsg = 'Mật khẩu mới quá yếu';
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
                );
              } finally {
                 if (mounted) setStateDialog(() => isUpdatingPass = false);
              }
            }

            return AlertDialog(
              title: const Text('Đổi mật khẩu'),
              content: Form(
                key: formPassKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: oldPassController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Mật khẩu cũ', border: OutlineInputBorder()),
                      validator: (val) => val!.isEmpty ? 'Vui lòng nhập mật khẩu cũ' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: newPassController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Mật khẩu mới', border: OutlineInputBorder()),
                      validator: (val) => val!.length < 6 ? 'Mật khẩu phải từ 6 ký tự' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: confirmPassController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Xác nhận mật khẩu mới', border: OutlineInputBorder()),
                      validator: (val) => val != newPassController.text ? 'Mật khẩu không khớp' : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
                ElevatedButton(
                  onPressed: isUpdatingPass ? null : changePassword,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                  child: isUpdatingPass 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Lưu', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Widget hiển thị Avatar
  Widget _buildAvatar() {
    ImageProvider? imageProvider;

    if (_pickedImage != null) {
      if (kIsWeb) {
        imageProvider = NetworkImage(_pickedImage!.path);
      } else {
        imageProvider = FileImage(File(_pickedImage!.path));
      }
    } else if (_currentImageBase64 != null && _currentImageBase64!.isNotEmpty) {
      try {
        Uint8List bytes = base64Decode(_currentImageBase64!);
        imageProvider = MemoryImage(bytes);
      } catch (e) {
        // Lỗi decode
      }
    }

    return Stack(
      children: [
        CircleAvatar(
          radius: 60,
          backgroundColor: Colors.grey.shade200,
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? const Icon(Icons.person, size: 60, color: Colors.grey)
              : null,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _pickImage,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.deepPurple,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ sơ cá nhân'),
        backgroundColor: Colors.deepPurple.shade100,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildAvatar(),
                    const SizedBox(height: 30),
                    
                    // Email (Không sửa được)
                    TextFormField(
                      controller: _emailController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.black12,
                        helperText: 'Email không thể thay đổi'
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Tên
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value!.trim().isEmpty ? 'Vui lòng nhập tên' : null,
                    ),
                    const SizedBox(height: 20),

                    // Số điện thoại
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Địa chỉ
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ',
                        prefixIcon: Icon(Icons.location_on),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Nút đổi mật khẩu
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _showChangePasswordDialog,
                        icon: const Icon(Icons.lock_reset),
                        label: const Text('Đổi mật khẩu'),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Nút Lưu thông tin
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _updateProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Lưu thay đổi', style: TextStyle(fontSize: 18, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
