import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController _groupNameController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  
  List<Map<String, dynamic>> _friends = [];
  final Set<String> _selectedFriendIds = {};
  
  XFile? _pickedImage; // Ảnh nhóm được chọn
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  // Tải danh sách bạn bè
  Future<void> _loadFriends() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('friends')
          .get();

      List<Map<String, dynamic>> tempFriends = [];

      for (var doc in snapshot.docs) {
        String friendId = doc.id;
        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(friendId).get();
        if (userDoc.exists) {
          Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
          data['uid'] = friendId;
          tempFriends.add(data);
        }
      }

      if (mounted) {
        setState(() {
          _friends = tempFriends;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Chọn ảnh từ thư viện
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 500,   // Resize nhỏ lại để lưu Firestore
        imageQuality: 70, 
      );
      if (image != null) {
        setState(() => _pickedImage = image);
      }
    } catch (e) {
      print("Lỗi chọn ảnh: $e");
    }
  }

  Future<void> _createGroup() async {
    String groupName = _groupNameController.text.trim();
    
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên nhóm')));
      return;
    }

    if (_selectedFriendIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cần chọn ít nhất 2 thành viên')));
      return;
    }

    setState(() => _isCreating = true);

    try {
      List<String> members = [currentUserId, ..._selectedFriendIds];
      String? imageBase64;

      // Chuyển ảnh sang Base64 nếu có
      if (_pickedImage != null) {
        final bytes = await _pickedImage!.readAsBytes();
        imageBase64 = base64Encode(bytes);
      }

      // Tạo nhóm trong collection 'chats'
      await FirebaseFirestore.instance.collection('chats').add({
        'name': groupName,
        'isGroup': true,
        'imageBase64': imageBase64 ?? '', // Lưu ảnh nhóm
        'ownerId': currentUserId,
        'users': members, 
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'lastMessage': 'Đã tạo nhóm "$groupName"',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tạo nhóm thành công!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo nhóm mới'),
        backgroundColor: Colors.deepPurple.shade100,
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroup,
            child: _isCreating 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Tạo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          )
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : Column(
              children: [
                const SizedBox(height: 20),
                
                // --- CHỌN ẢNH NHÓM ---
                GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: _pickedImage != null 
                            ? (kIsWeb 
                                ? NetworkImage(_pickedImage!.path) 
                                : FileImage(File(_pickedImage!.path)) as ImageProvider)
                            : null,
                        child: _pickedImage == null 
                            ? const Icon(Icons.camera_alt, size: 40, color: Colors.grey)
                            : null,
                      ),
                      if (_pickedImage != null)
                        const Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 15,
                            backgroundColor: Colors.deepPurple,
                            child: Icon(Icons.edit, size: 15, color: Colors.white),
                          ),
                        )
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Nhập tên nhóm
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: TextField(
                    controller: _groupNameController,
                    decoration: const InputDecoration(
                      labelText: 'Tên nhóm',
                      prefixIcon: Icon(Icons.group),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Chọn thành viên:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),

                // Danh sách bạn bè để chọn
                Expanded(
                  child: _friends.isEmpty 
                      ? const Center(child: Text("Bạn chưa có bạn bè nào để thêm vào nhóm"))
                      : ListView.builder(
                          itemCount: _friends.length,
                          itemBuilder: (context, index) {
                            final friend = _friends[index];
                            final String uid = friend['uid'];
                            final bool isSelected = _selectedFriendIds.contains(uid);

                            // Hiển thị avatar bạn bè
                            ImageProvider? avatarImg;
                            if (friend['imageBase64'] != null && friend['imageBase64'].toString().isNotEmpty) {
                               try {
                                 avatarImg = MemoryImage(base64Decode(friend['imageBase64']));
                               } catch (_) {}
                            }

                            return CheckboxListTile(
                              value: isSelected,
                              title: Text(friend['name'] ?? 'Unknown'),
                              secondary: CircleAvatar(
                                backgroundImage: avatarImg,
                                child: avatarImg == null ? Text(friend['name'] != null ? friend['name'][0] : '?') : null,
                              ),
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedFriendIds.add(uid);
                                  } else {
                                    _selectedFriendIds.remove(uid);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
