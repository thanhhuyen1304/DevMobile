import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PostDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;

  const PostDetailPage({super.key, required this.data, required this.docId});

  // Helper decode Base64 an toàn
  Uint8List? _safeBase64Decode(String source) {
    if (source.isEmpty) return null;
    try {
      if (source.contains(',')) {
        source = source.split(',').last;
      }
      source = source.trim().replaceAll('\n', '').replaceAll('\r', '');
      return base64Decode(source);
    } catch (e) {
      print("Lỗi decode ảnh chi tiết: $e");
      return null;
    }
  }

  // Helper hiển thị ảnh
  Widget _buildPostImage() {
    final String? imageBase64 = data['imageBase64'];
    final String? imageUrl = data['imageUrl'];

    if (imageBase64 != null && imageBase64.isNotEmpty) {
      final bytes = _safeBase64Decode(imageBase64);
      if (bytes != null) {
        return Image.memory(bytes, width: double.infinity, fit: BoxFit.cover);
      }
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(imageUrl, width: double.infinity, fit: BoxFit.cover);
    }
    return const SizedBox();
  }

  @override
  Widget build(BuildContext context) {
    final title = data['title'] ?? 'Không có tiêu đề';
    final content = data['content'] ?? '';
    final author = data['authorName'] ?? 'Ẩn danh';
    final Timestamp? timestamp = data['createdAt'];

    String dateStr = '';
    if (timestamp != null) {
      dateStr = DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết bài viết'),
        backgroundColor: Colors.deepPurple.shade100,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ảnh lớn
            _buildPostImage(),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tiêu đề
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Thông tin tác giả
                  Row(
                    children: [
                      const Icon(Icons.person, size: 20, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(author, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      const Icon(Icons.access_time, size: 16, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(dateStr, style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const Divider(height: 30),

                  // Nội dung chính
                  Text(
                    content,
                    style: const TextStyle(fontSize: 16, height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
