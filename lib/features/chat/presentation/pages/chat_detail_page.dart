import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // kIsWeb
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart'; // Import để format thời gian
import 'package:zego_uikit/zego_uikit.dart'; // Import ZegoUIKit
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart'; // Import Zego

class ChatDetailPage extends StatefulWidget {
  final String? friendId;
  final String chatName;
  final bool isGroup;
  final String? groupId;

  const ChatDetailPage({
    super.key, 
    this.friendId, 
    required this.chatName,
    this.isGroup = false,
    this.groupId,
  });

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  final TextEditingController _msgController = TextEditingController();
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  late String chatId;
  String _currentChatName = '';
  
  // Biến lưu tin nhắn đang trả lời
  Map<String, dynamic>? _replyMessage;

  @override
  void initState() {
    super.initState();
    _currentChatName = widget.chatName;

    if (widget.isGroup) {
      chatId = widget.groupId!;
      _listenToGroupChanges();
    } else {
      List<String> ids = [currentUserId, widget.friendId!];
      ids.sort(); 
      chatId = ids.join("_");
    }
  }

  void _listenToGroupChanges() {
    FirebaseFirestore.instance.collection('chats').doc(chatId).snapshots().listen((snapshot) {
      if (snapshot.exists && mounted) {
        setState(() {
          _currentChatName = snapshot.get('name');
        });
      }
    });
  }

  // Helper function to send system message (for call logs)
  void _sendSystemMessage(String content, {String type = 'system'}) async {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages').add({
      'senderId': currentUserId,
      'senderName': 'System',
      'content': content,
      'createdAt': FieldValue.serverTimestamp(),
      'isEdited': false,
      'type': type // Loại tin nhắn hệ thống
    });
  }

  void _sendMessage() async {
    if (_msgController.text.trim().isEmpty) return;

    String msg = _msgController.text.trim();
    _msgController.clear();

    String senderName = FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown';

    // Tạo data tin nhắn
    Map<String, dynamic> msgData = {
      'senderId': currentUserId,
      'senderName': senderName,
      'content': msg,
      'createdAt': FieldValue.serverTimestamp(),
      'isEdited': false,
    };

    // Nếu đang trả lời, thêm thông tin reply
    if (_replyMessage != null) {
      msgData['replyTo'] = {
        'content': _replyMessage!['content'],
        'senderName': _replyMessage!['senderName'],
      };
      // Reset trạng thái reply
      setState(() => _replyMessage = null);
    }

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(msgData);

    Map<String, dynamic> updateData = {
      'lastMessage': msg,
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    if (!widget.isGroup) {
      updateData['users'] = [currentUserId, widget.friendId];
    }

    await FirebaseFirestore.instance.collection('chats').doc(chatId).set(
      updateData, 
      SetOptions(merge: true)
    );
  }

  // Chọn tin nhắn để trả lời (Vuốt sang phải hoặc nhấn giữ -> Trả lời)
  void _setReplyMessage(Map<String, dynamic> msg) {
    setState(() {
      _replyMessage = msg;
    });
  }

  // --- CÁC HÀM XỬ LÝ KHÁC (GIỮ NGUYÊN) ---
  void _showGroupSettings() {
    final nameController = TextEditingController(text: _currentChatName);
    XFile? pickedImage;
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> pickImage() async {
              final ImagePicker picker = ImagePicker();
              try {
                final XFile? image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 500, imageQuality: 70);
                if (image != null) setStateDialog(() => pickedImage = image);
              } catch (_) {}
            }

            Future<void> updateGroup() async {
              if (nameController.text.trim().isEmpty) return;

              Map<String, dynamic> dataToUpdate = {
                'name': nameController.text.trim(),
              };

              if (pickedImage != null) {
                final bytes = await pickedImage!.readAsBytes();
                String base64Image = base64Encode(bytes);
                dataToUpdate['imageBase64'] = base64Image;
              }

              await FirebaseFirestore.instance.collection('chats').doc(chatId).update(dataToUpdate);

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cập nhật nhóm thành công!')));
              }
            }

            return AlertDialog(
              title: const Text('Cài đặt nhóm'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: pickImage,
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage: pickedImage != null 
                          ? (kIsWeb ? NetworkImage(pickedImage!.path) : FileImage(File(pickedImage!.path)) as ImageProvider)
                          : null,
                      child: pickedImage == null ? const Icon(Icons.camera_alt, color: Colors.grey) : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Chạm để đổi ảnh', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Tên nhóm', border: OutlineInputBorder()),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
                ElevatedButton(onPressed: updateGroup, child: const Text('Lưu')),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteMessage(String msgId) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa tin nhắn'),
        content: const Text('Bạn có chắc muốn xóa tin nhắn này không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa', style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages').doc(msgId).delete();
    }
  }

  Future<void> _editMessage(String msgId, String oldContent) async {
    TextEditingController editController = TextEditingController(text: oldContent);
    String? newContent = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sửa tin nhắn'),
        content: TextField(controller: editController, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          TextButton(onPressed: () => Navigator.pop(context, editController.text.trim()), child: const Text('Lưu')),
        ],
      ),
    );

    if (newContent != null && newContent.isNotEmpty && newContent != oldContent) {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages').doc(msgId).update({'content': newContent, 'isEdited': true});
    }
  }

  void _showMessageOptions(String msgId, String content, bool isMe, Map<String, dynamic> msgData) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply, color: Colors.green),
              title: const Text('Trả lời'),
              onTap: () {
                Navigator.pop(context);
                _setReplyMessage(msgData);
              },
            ),
            if (isMe) ...[
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Chỉnh sửa'),
                onTap: () {
                  Navigator.pop(context);
                  _editMessage(msgId, content);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Xóa tin nhắn'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(msgId);
                },
              ),
            ]
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_currentChatName, style: const TextStyle(fontSize: 16)),
            if (widget.isGroup)
              const Text('Nhóm chat', style: TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
        backgroundColor: Colors.deepPurple.shade100,
        actions: [
          // Nút gọi Video - Sử dụng ZegoSendCallInvitationButton
          if (!widget.isGroup && widget.friendId != null)
             ZegoSendCallInvitationButton(
               isVideoCall: true,
               resourceID: "zegouikit_call", // Resource ID cho thông báo (cần setup trên dashboard nếu dùng offline notification)
               invitees: [
                 ZegoUIKitUser(
                   id: widget.friendId!,
                   name: widget.chatName, // Tên người được mời
                 )
               ],
               iconSize: const Size(40, 40),
               buttonSize: const Size(40, 40),
               icon: ButtonIcon(icon: const Icon(Icons.videocam, color: Colors.deepPurple)),
               
               // SỬA LẠI: Xử lý callback khi bấm nút gọi
               onPressed: (String code, String message, List<String> errorInvitees) {
                 if (errorInvitees.isNotEmpty) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text('${widget.chatName} hiện không thể nhận cuộc gọi.')),
                   );
                 }
               },
             ),
            
          if (widget.isGroup)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showGroupSettings,
              tooltip: 'Cài đặt nhóm',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages').orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) return const Center(child: Text("Hãy bắt đầu cuộc trò chuyện!"));

                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == currentUserId;
                    final content = data['content'] ?? '';
                    final bool isEdited = data['isEdited'] ?? false;
                    final String senderName = data['senderName'] ?? '';
                    final Map<String, dynamic>? replyTo = data['replyTo'];
                    final Timestamp? timestamp = data['createdAt'];
                    final String msgType = data['type'] ?? 'text'; // Loại tin nhắn

                    String timeStr = '';
                    if (timestamp != null) {
                      timeStr = DateFormat('HH:mm').format(timestamp.toDate());
                    }

                    // --- XỬ LÝ HIỂN THỊ TIN NHẮN CUỘC GỌI ---
                    if (msgType == 'call' || msgType == 'system_call') {
                      return Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                msgType == 'system_call' ? Icons.phone_forwarded : Icons.video_call, 
                                color: Colors.deepPurple, 
                                size: 20
                              ),
                              const SizedBox(width: 8),
                              Text(
                                content, 
                                style: const TextStyle(fontSize: 12, color: Colors.black87)
                              ),
                              const SizedBox(width: 5),
                              Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                      );
                    }

                    // --- TIN NHẮN THƯỜNG ---
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => _showMessageOptions(doc.id, content, isMe, data),
                        // Thêm chức năng vuốt để reply (đơn giản hóa bằng LongPress cho nhanh)
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          child: Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              // Tên người gửi trong nhóm
                              if (widget.isGroup && !isMe)
                                Padding(padding: const EdgeInsets.only(left: 12, bottom: 2), child: Text(senderName, style: TextStyle(fontSize: 10, color: Colors.grey.shade600))),
                              
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isMe ? Colors.deepPurple : Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Phần hiển thị tin nhắn được Reply
                                    if (replyTo != null)
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        margin: const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border(left: BorderSide(color: isMe ? Colors.white : Colors.deepPurple, width: 4))
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(replyTo['senderName'] ?? 'Unknown', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isMe ? Colors.white70 : Colors.deepPurple)),
                                            Text(replyTo['content'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: isMe ? Colors.white70 : Colors.black54)),
                                          ],
                                        ),
                                      ),

                                    // Nội dung chính
                                    Text(content, style: TextStyle(color: isMe ? Colors.white : Colors.black, fontSize: 16)),
                                    
                                    // Footer: Đã sửa + Thời gian
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (isEdited) 
                                          Padding(
                                            padding: const EdgeInsets.only(right: 4),
                                            child: Text('(đã sửa)', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: isMe ? Colors.white70 : Colors.black54)),
                                          ),
                                        Text(timeStr, style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.black54)),
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // KHU VỰC TRẢ LỜI TIN NHẮN (Hiển thị khi đang reply)
          if (_replyMessage != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.grey.shade200,
              child: Row(
                children: [
                  const Icon(Icons.reply, color: Colors.deepPurple),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Đang trả lời ${_replyMessage!['senderName']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text(_replyMessage!['content'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => _replyMessage = null),
                  )
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.all(10),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(child: TextField(controller: _msgController, decoration: const InputDecoration(hintText: 'Nhập tin nhắn...', border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))), contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 10)))),
                const SizedBox(width: 10),
                IconButton(onPressed: _sendMessage, icon: const Icon(Icons.send, color: Colors.deepPurple))
              ],
            ),
          )
        ],
      ),
    );
  }
}
