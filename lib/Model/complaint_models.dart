// Models for the Complaints / Problems feature.

DateTime? _date(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
String _str(dynamic v) => v?.toString() ?? '';
bool _bool(dynamic v) => v == true || v?.toString().toLowerCase() == 'true';

/// One row of the complaints inbox.
class Complaint {
  final int id;
  final String title;
  final String status; // OPEN | RESOLVED
  final String snippet;
  final String lastSenderRole; // BA | STAFF | SYSTEM
  final int messageCount;
  final bool unread;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;
  final String locationName;

  const Complaint({
    required this.id,
    required this.title,
    required this.status,
    required this.snippet,
    required this.lastSenderRole,
    required this.messageCount,
    required this.unread,
    required this.createdAt,
    required this.lastMessageAt,
    required this.locationName,
  });

  bool get isOpen => status.toUpperCase() != 'RESOLVED';

  factory Complaint.fromJson(Map<String, dynamic> j) => Complaint(
        id: _int(j['complaint_id']),
        title: _str(j['title']),
        status: _str(j['status']).toUpperCase(),
        snippet: _str(j['snippet']),
        lastSenderRole: _str(j['last_sender_role']).toUpperCase(),
        messageCount: _int(j['message_count']),
        unread: _bool(j['unread']),
        createdAt: _date(j['created_at']),
        lastMessageAt: _date(j['last_message_at']),
        locationName: _str(j['location_name']),
      );
}

/// One bubble in a conversation.
class ComplaintMessage {
  final int id;
  final String senderRole; // BA | STAFF | SYSTEM
  final String senderName;
  final bool isMine;
  final String body;
  final bool hasImage;
  final DateTime? createdAt;

  const ComplaintMessage({
    required this.id,
    required this.senderRole,
    required this.senderName,
    required this.isMine,
    required this.body,
    required this.hasImage,
    required this.createdAt,
  });

  bool get isSystem => senderRole == 'SYSTEM';

  factory ComplaintMessage.fromJson(Map<String, dynamic> j) => ComplaintMessage(
        id: _int(j['message_id']),
        senderRole: _str(j['sender_role']).toUpperCase(),
        senderName: _str(j['sender_name']),
        isMine: _bool(j['is_mine']),
        body: _str(j['body']),
        hasImage: _bool(j['has_image']),
        createdAt: _date(j['created_at']),
      );
}

/// A full conversation (header + messages).
class ComplaintThread {
  final int id;
  final String title;
  final String status;
  final DateTime? createdAt;
  final DateTime? resolvedAt;
  final String locationName;
  final List<ComplaintMessage> messages;

  const ComplaintThread({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.resolvedAt,
    required this.locationName,
    required this.messages,
  });

  bool get isOpen => status.toUpperCase() != 'RESOLVED';

  factory ComplaintThread.fromJson(Map<String, dynamic> j) => ComplaintThread(
        id: _int(j['complaint_id']),
        title: _str(j['title']),
        status: _str(j['status']).toUpperCase(),
        createdAt: _date(j['created_at']),
        resolvedAt: _date(j['resolved_at']),
        locationName: _str(j['location_name']),
        messages: [
          for (final m in (j['messages'] as List? ?? const []))
            if (m is Map) ComplaintMessage.fromJson(Map<String, dynamic>.from(m)),
        ],
      );
}
