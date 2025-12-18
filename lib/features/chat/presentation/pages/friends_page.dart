import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'chat_detail_page.dart';
import 'create_group_page.dart'; // Import trang tạo nhóm

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  final TextEditingController _searchController = TextEditingController();
  List<DocumentSnapshot> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // 4 tabs
  }

  // --- LOGIC TÌM KIẾM ---
  Future<void> _searchUsers() async {
    String query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isSearching = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThan: '${query}z')
          .get();

      setState(() {
        _searchResults = snapshot.docs.where((doc) => doc.id != currentUserId).toList();
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
    }
  }

  // Gửi lời mời kết bạn
  Future<void> _sendFriendRequest(String toUserId) async {
    try {
      await FirebaseFirestore.instance.collection('friend_requests').add({
        'fromUserId': currentUserId,
        'toUserId': toUserId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi lời mời!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  // Chấp nhận kết bạn
  Future<void> _acceptFriendRequest(String requestId, String fromUserId) async {
    try {
      await FirebaseFirestore.instance.collection('friend_requests').doc(requestId).update({'status': 'accepted'});

      final batch = FirebaseFirestore.instance.batch();
      
      batch.set(
        FirebaseFirestore.instance.collection('users').doc(currentUserId).collection('friends').doc(fromUserId),
        {'friendId': fromUserId, 'createdAt': FieldValue.serverTimestamp()}
      );

      batch.set(
        FirebaseFirestore.instance.collection('users').doc(fromUserId).collection('friends').doc(currentUserId),
        {'friendId': currentUserId, 'createdAt': FieldValue.serverTimestamp()}
      );

      await batch.commit();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã kết bạn thành công!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Widget _buildAvatar(Map<String, dynamic> data) {
    if (data['imageBase64'] != null && data['imageBase64'].toString().isNotEmpty) {
      try {
        return CircleAvatar(backgroundImage: MemoryImage(base64Decode(data['imageBase64'])));
      } catch (_) {}
    }
    String name = data['name'] ?? '?';
    return CircleAvatar(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Bạn bè'),
            Tab(text: 'Nhóm'),
            Tab(text: 'Lời mời'),
            Tab(text: 'Tìm kiếm'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // TAB 1: DANH SÁCH BẠN BÈ
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).collection('friends').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final friendDocs = snapshot.data!.docs;
                  
                  if (friendDocs.isEmpty) return const Center(child: Text("Chưa có bạn bè nào"));

                  return ListView.builder(
                    itemCount: friendDocs.length,
                    itemBuilder: (context, index) {
                      String friendId = friendDocs[index].id;
                      
                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('users').doc(friendId).get(),
                        builder: (context, userSnapshot) {
                          if (!userSnapshot.hasData) return const ListTile(leading: CircleAvatar(), title: Text("Loading..."));
                          final userData = userSnapshot.data!.data() as Map<String, dynamic>;

                          return ListTile(
                            leading: _buildAvatar(userData),
                            title: Text(userData['name'] ?? 'Unknown'),
                            subtitle: const Text('Nhấn để chat'),
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatDetailPage(
                                  friendId: friendId, 
                                  chatName: userData['name'] ?? 'Unknown',
                                )
                              ));
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),

              // TAB 2: DANH SÁCH NHÓM
              Stack(
                children: [
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .where('isGroup', isEqualTo: true)
                        .where('users', arrayContains: currentUserId)
                        // .orderBy('lastUpdated', descending: true) // TẠM TẮT DÒNG NÀY ĐỂ TRÁNH LỖI INDEX
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Lỗi tải nhóm: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      
                      final groups = snapshot.data!.docs;
                      if (groups.isEmpty) return const Center(child: Text("Bạn chưa tham gia nhóm nào"));

                      return ListView.builder(
                        itemCount: groups.length,
                        itemBuilder: (context, index) {
                          final groupData = groups[index].data() as Map<String, dynamic>;
                          final groupId = groups[index].id;
                          final groupName = groupData['name'] ?? 'Nhóm không tên';
                          final lastMsg = groupData['lastMessage'] ?? '';
                          final imageBase64 = groupData['imageBase64'];

                          ImageProvider? groupAvatar;
                          if (imageBase64 != null && imageBase64.toString().isNotEmpty) {
                             try {
                               groupAvatar = MemoryImage(base64Decode(imageBase64));
                             } catch (_) {}
                          }

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.deepPurple.shade100,
                              backgroundImage: groupAvatar,
                              child: groupAvatar == null ? const Icon(Icons.groups, color: Colors.deepPurple) : null,
                            ),
                            title: Text(groupName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => ChatDetailPage(
                                  chatName: groupName, 
                                  isGroup: true, 
                                  groupId: groupId
                                )
                              ));
                            },
                          );
                        },
                      );
                    },
                  ),
                  
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: FloatingActionButton(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupPage()));
                      },
                      backgroundColor: Colors.deepPurple,
                      child: const Icon(Icons.group_add, color: Colors.white),
                    ),
                  ),
                ],
              ),

              // TAB 3: LỜI MỜI KẾT BẠN
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('friend_requests')
                    .where('toUserId', isEqualTo: currentUserId)
                    .where('status', isEqualTo: 'pending')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final requests = snapshot.data!.docs;

                  if (requests.isEmpty) return const Center(child: Text("Không có lời mời nào"));

                  return ListView.builder(
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final req = requests[index];
                      String fromUserId = req['fromUserId'];

                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('users').doc(fromUserId).get(),
                        builder: (context, userSnapshot) {
                          if (!userSnapshot.hasData) return const SizedBox();
                          final userData = userSnapshot.data!.data() as Map<String, dynamic>;

                          return ListTile(
                            leading: _buildAvatar(userData),
                            title: Text(userData['name'] ?? 'Unknown'),
                            subtitle: const Text('Muốn kết bạn với bạn'),
                            trailing: ElevatedButton(
                              onPressed: () => _acceptFriendRequest(req.id, fromUserId),
                              child: const Text("Chấp nhận"),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),

              // TAB 4: TÌM KIẾM
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Nhập tên người dùng',
                        suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _searchUsers),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_isSearching) const CircularProgressIndicator(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final userData = _searchResults[index].data() as Map<String, dynamic>;
                          final userId = _searchResults[index].id;
                          
                          return ListTile(
                            leading: _buildAvatar(userData),
                            title: Text(userData['name'] ?? 'Unknown'),
                            subtitle: Text(userData['email'] ?? ''),
                            trailing: IconButton(
                              icon: const Icon(Icons.person_add, color: Colors.deepPurple),
                              onPressed: () => _sendFriendRequest(userId),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
