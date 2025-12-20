import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // kIsWeb, kDebugMode
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart'; // Import Signaling Plugin
import 'features/auth/presentation/pages/auth_page.dart';
import 'features/auth/presentation/pages/profile_page.dart';
import 'features/data/auth_service.dart';
import 'post_detail_page.dart';
import 'features/chat/presentation/pages/friends_page.dart';
import 'features/chat/presentation/pages/call_page.dart'; // Import CallPage để lấy AppID, AppSign
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthService _authService = AuthService();
  final User? user = FirebaseAuth.instance.currentUser;

  String? _userRole;
  bool _isLoadingRole = true;
  String? _userAvatarBase64;

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
    _initZegoCallInvitation(); // Khởi tạo Zego Invitation Service
  }

  // --- Khởi tạo dịch vụ nhận cuộc gọi ---
  void _initZegoCallInvitation() {
    if (user == null) return;

    // Lấy tên hiển thị, nếu không có thì dùng "User"
    String userName = user!.displayName ?? 'User';
    if (userName.isEmpty) userName = 'User';

    ZegoUIKitPrebuiltCallInvitationService().init(
      appID: CallInfo.appId, // Lấy từ CallPage
      appSign: CallInfo.appSign,
      userID: user!.uid,
      userName: userName,
      plugins: [ZegoUIKitSignalingPlugin()],

      // Tùy chỉnh nhạc chuông (nếu cần)
      // ringtoneConfig: const ZegoRingtoneConfig(),
    );
  }

  // Cần hủy dịch vụ khi đăng xuất để tránh lỗi
  Future<void> _deInitZegoCallInvitation() async {
    await ZegoUIKitPrebuiltCallInvitationService().uninit();
  }

  Future<void> _fetchUserRole() async {
    if (user != null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .get();

        if (userDoc.exists && mounted) {
          setState(() {
            _userRole = userDoc.get('role');
            _userAvatarBase64 = userDoc.get('imageBase64');
            _isLoadingRole = false;
          });
        }
      } catch (e) {
        if (kDebugMode) print("Lỗi lấy role: $e");
        if (mounted) setState(() => _isLoadingRole = false);
      }
    }
  }

  Future<void> _signOut() async {
    await _deInitZegoCallInvitation(); // Hủy Zego Service
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthPage()),
      );
    }
  }

  void _goToProfile() {
    Navigator.push(context,
        MaterialPageRoute(builder: (context) => const ProfilePage())).then((_) {
      _fetchUserRole();
    });
  }

  // --- Helper xử lý ảnh Base64 an toàn ---
  Uint8List? _safeBase64Decode(String source) {
    if (source.isEmpty) return null;
    try {
      // Loại bỏ header data:image/png;base64,... nếu có
      if (source.contains(',')) {
        source = source.split(',').last;
      }
      // Loại bỏ khoảng trắng thừa
      source = source.trim().replaceAll('\n', '').replaceAll('\r', '');
      return base64Decode(source);
    } catch (e) {
      print("Lỗi decode ảnh: $e");
      return null;
    }
  }

  Widget _buildSafeImage(String? base64String,
      {double? height, double? width, BoxFit fit = BoxFit.cover}) {
    if (base64String == null || base64String.isEmpty) return const SizedBox();

    final bytes = _safeBase64Decode(base64String);
    if (bytes != null) {
      return Image.memory(
        bytes,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Container(
          height: height,
          width: width,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    } else {
      return Container(
        height: height,
        width: width,
        color: Colors.grey[200],
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }
  }

  // --- LOGIC POST ---

  Future<void> _deletePost(String docId) async {
    bool confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Xác nhận xóa'),
            content: const Text('Bạn có chắc muốn xóa bài viết này không?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Hủy')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child:
                      const Text('Xóa', style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      try {
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(docId)
            .delete();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Đã xóa bài viết'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Lỗi xóa: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showCreateOrEditPostDialog(
      {String? docId, Map<String, dynamic>? initialData}) {
    final titleController =
        TextEditingController(text: initialData?['title'] ?? '');
    final contentController =
        TextEditingController(text: initialData?['content'] ?? '');
    String? currentBase64 = initialData?['imageBase64'];
    XFile? pickedImage;
    bool isUploading = false;
    bool isEditMode = docId != null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> pickImage() async {
              final ImagePicker picker = ImagePicker();
              try {
                final XFile? image = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 800,
                    imageQuality: 70);
                if (image != null) setStateDialog(() => pickedImage = image);
              } catch (e) {
                print("Lỗi chọn ảnh: $e");
              }
            }

            Future<void> submitPost() async {
              if (titleController.text.trim().isEmpty ||
                  contentController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Vui lòng nhập tiêu đề và nội dung')));
                return;
              }
              setStateDialog(() => isUploading = true);
              try {
                String? imageBase64ToSave = currentBase64;
                if (pickedImage != null) {
                  final bytes = await pickedImage!.readAsBytes();
                  imageBase64ToSave = base64Encode(bytes);
                }

                final dataToSave = {
                  'title': titleController.text.trim(),
                  'content': contentController.text.trim(),
                  'imageBase64': imageBase64ToSave ?? '',
                  if (!isEditMode) ...{
                    'userId': user?.uid,
                    'authorName': user?.displayName ?? 'Admin',
                    'authorEmail': user?.email ?? '',
                    'authorRole': _userRole ?? 'user',
                    'createdAt': FieldValue.serverTimestamp(),
                    'likesCount': 0,
                    'commentsCount': 0,
                  } else ...{
                    'updatedAt': FieldValue.serverTimestamp()
                  }
                };
                if (isEditMode) {
                  await FirebaseFirestore.instance
                      .collection('posts')
                      .doc(docId)
                      .update(dataToSave);
                } else {
                  await FirebaseFirestore.instance
                      .collection('posts')
                      .add(dataToSave);
                }
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isEditMode
                          ? 'Cập nhật thành công!'
                          : 'Đăng bài thành công!'),
                      backgroundColor: Colors.green));
                }
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Lỗi: $e'), backgroundColor: Colors.red));
              } finally {
                if (mounted) setStateDialog(() => isUploading = false);
              }
            }

            Widget buildImagePreview() {
              if (pickedImage != null) {
                return kIsWeb
                    ? Image.network(pickedImage!.path, fit: BoxFit.cover)
                    : Image.file(File(pickedImage!.path), fit: BoxFit.cover);
              } else if (currentBase64 != null && currentBase64!.isNotEmpty) {
                // Dùng helper decode an toàn
                return _buildSafeImage(currentBase64);
              }
              return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate,
                        size: 40, color: Colors.deepPurple.shade300),
                    const SizedBox(height: 5),
                    const Text('Chọn ảnh (tối đa 1MB)',
                        style: TextStyle(color: Colors.grey))
                  ]);
            }

            return AlertDialog(
              title: Text(isEditMode ? 'Sửa bài viết' : 'Bài viết mới'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                            labelText: 'Tiêu đề',
                            border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    TextField(
                        controller: contentController,
                        decoration: const InputDecoration(
                            labelText: 'Nội dung',
                            border: OutlineInputBorder()),
                        maxLines: 4),
                    const SizedBox(height: 15),
                    GestureDetector(
                      onTap: pickImage,
                      child: Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade400)),
                        child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: buildImagePreview()),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (!isUploading)
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Hủy')),
                ElevatedButton(
                    onPressed: isUploading ? null : submitPost,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple),
                    child: isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(color: Colors.white))
                        : Text(isEditMode ? 'Cập nhật' : 'Đăng ngay',
                            style: const TextStyle(color: Colors.white))),
              ],
            );
          },
        );
      },
    );
  }

  // --- LOGIC BANNER ---

  Future<void> _addBanner() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1024, imageQuality: 80);

    if (image == null) return;

    // Show dialog nhập tiêu đề (nếu muốn) hoặc xác nhận upload
    if (!mounted) return;

    // Đơn giản là upload luôn sau khi chọn
    try {
      final bytes = await image.readAsBytes();
      final base64Img = base64Encode(bytes);

      await FirebaseFirestore.instance.collection('banners').add({
        'imageBase64': base64Img,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user?.uid,
      });

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Đã thêm banner!'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Lỗi thêm banner: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteBanner(String docId) async {
    bool confirm = await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Xóa Banner"),
            content: const Text("Bạn có chắc chắn muốn xóa banner này?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Hủy")),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child:
                      const Text("Xóa", style: TextStyle(color: Colors.red))),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      try {
        await FirebaseFirestore.instance
            .collection('banners')
            .doc(docId)
            .delete();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Đã xóa banner'), backgroundColor: Colors.green));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Lỗi xóa banner: $e'),
              backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildBannerSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('banners')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();

        // Nếu đang loading mà chưa có data cũ thì hiện loading, không thì thôi
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator()));
        }

        final docs = snapshot.data?.docs ?? [];

        // Nếu không có banner nào và không phải admin -> Ẩn hoặc hiện default
        if (docs.isEmpty) {
          if (_userRole == 'admin') {
            return Container(
              height: 180,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(16)),
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: _addBanner,
                  icon: const Icon(Icons.add),
                  label: const Text("Thêm Banner đầu tiên"),
                ),
              ),
            );
          }
          // Default banner nếu không có data
          return Container(
            width: double.infinity,
            height: 180,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(colors: [
                Colors.deepPurple.shade400,
                Colors.deepPurple.shade200
              ]),
            ),
            child: const Center(
                child: Text("Chào mừng bạn!",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold))),
          );
        }

        return Container(
          height: 180,
          margin: const EdgeInsets.only(bottom: 16),
          child: PageView.builder(
            itemCount: docs.length +
                (_userRole == 'admin'
                    ? 1
                    : 0), // Thêm 1 slot cho nút Add nếu là Admin
            itemBuilder: (context, index) {
              // Nút thêm banner ở cuối list cho Admin
              if (_userRole == 'admin' && index == docs.length) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.grey.shade400,
                        style:
                            BorderStyle.solid), // Changed from dashed to solid
                  ),
                  child: InkWell(
                    onTap: _addBanner,
                    borderRadius: BorderRadius.circular(16),
                    child: const Center(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Icon(Icons.add_circle,
                              size: 40, color: Colors.deepPurple),
                          Text("Thêm Banner")
                        ])),
                  ),
                );
              }

              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final imgBase64 = data['imageBase64'] as String?;

              return Stack(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _buildSafeImage(imgBase64, fit: BoxFit.cover),
                    ),
                  ),
                  // Nút xóa banner cho Admin
                  if (_userRole == 'admin')
                    Positioned(
                      top: 8,
                      right: 12,
                      child: CircleAvatar(
                        backgroundColor: Colors.white.withOpacity(0.7),
                        radius: 16,
                        child: IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.red, size: 16),
                          onPressed: () => _deleteBanner(doc.id),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // --- WIDGET DANH SÁCH BÀI VIẾT (HOME TAB) ---
  Widget _buildHomeTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(child: Text('Lỗi: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());

        final docs = snapshot.data?.docs ?? [];

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length + 1, // +1 for Banner
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildBannerSection();
            }

            final doc = docs[index - 1];
            final data = doc.data() as Map<String, dynamic>;
            final title = data['title'] ?? 'Không tiêu đề';
            final content = data['content'] ?? '';
            final author = data['authorName'] ?? 'Ẩn danh';
            final Timestamp? timestamp = data['createdAt'];
            String dateStr = timestamp != null
                ? DateFormat('dd/MM HH:mm').format(timestamp.toDate())
                : '';
            final imgBase64 = data['imageBase64'] as String?;
            final imgUrl = data['imageUrl'] as String?;

            return Card(
              elevation: 3,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              PostDetailPage(data: data, docId: doc.id)));
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.deepPurple.shade100,
                            child: Text(
                                author.isNotEmpty
                                    ? author[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(author,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              Text(dateStr,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                          const Spacer(),
                          if (_userRole == 'admin')
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert),
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showCreateOrEditPostDialog(
                                      docId: doc.id, initialData: data);
                                } else if (value == 'delete') {
                                  _deletePost(doc.id);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(children: [
                                      Icon(Icons.edit, size: 20),
                                      SizedBox(width: 8),
                                      Text('Sửa')
                                    ])),
                                const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(children: [
                                      Icon(Icons.delete,
                                          size: 20, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Xóa',
                                          style: TextStyle(color: Colors.red))
                                    ])),
                              ],
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Text(content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black54)),
                    ),

                    // HIỂN THỊ ẢNH POST
                    if (imgBase64 != null && imgBase64.isNotEmpty)
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: _buildSafeImage(imgBase64),
                      )
                    else if (imgUrl != null && imgUrl.isNotEmpty)
                      Image.network(imgUrl,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover)
                    else
                      const SizedBox(),

                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  ImageProvider _getUserAvatar() {
    if (_userAvatarBase64 != null && _userAvatarBase64!.isNotEmpty) {
      try {
        final bytes = _safeBase64Decode(_userAvatarBase64!);
        if (bytes != null) return MemoryImage(bytes);
      } catch (_) {}
    }
    return const NetworkImage(
        'https://ui-avatars.com/api/?name=User&background=random');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Trang chủ' : 'Tin nhắn'),
        backgroundColor: Colors.deepPurple.shade100,
        actions: [
          if (!_isLoadingRole)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Chip(
                label: Text(_userRole == 'admin' ? 'ADMIN' : 'USER',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color:
                            _userRole == 'admin' ? Colors.red : Colors.blue)),
                backgroundColor: _userRole == 'admin'
                    ? Colors.red.withOpacity(0.1)
                    : Colors.blue.withOpacity(0.1),
              ),
            ),
          PopupMenuButton<String>(
            offset: const Offset(0, 50),
            icon: CircleAvatar(
              radius: 18,
              backgroundImage: _getUserAvatar(),
            ),
            onSelected: (value) {
              if (value == 'profile')
                _goToProfile();
              else if (value == 'logout') _signOut();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'profile',
                  child: Row(children: [
                    Icon(Icons.person, color: Colors.deepPurple),
                    SizedBox(width: 10),
                    Text('Hồ sơ cá nhân')
                  ])),
              const PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 10),
                    Text('Đăng xuất', style: TextStyle(color: Colors.red))
                  ])),
            ],
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          const FriendsPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Bài viết'),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Tin nhắn'),
        ],
      ),
      floatingActionButton: (_currentIndex == 0 && _userRole == 'admin')
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateOrEditPostDialog(),
              backgroundColor: Colors.deepPurple,
              icon: const Icon(Icons.edit, color: Colors.white),
              label:
                  const Text('Viết bài', style: TextStyle(color: Colors.white)),
            )
          : null,
    );
  }
}
