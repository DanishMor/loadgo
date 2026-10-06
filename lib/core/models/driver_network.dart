import 'package:cloud_firestore/cloud_firestore.dart';

import '../network/network_logic.dart';

/// `driver_links/{pairId}`: a connection request or connection between two drivers.
class DriverLink {
  final String id;
  final List<String> members;
  final String requestedBy;
  final String requesterName;
  final String targetName;
  final bool connected;
  final DateTime? createdAt;

  const DriverLink({required this.id, required this.members, required this.requestedBy, required this.requesterName, required this.targetName, required this.connected, this.createdAt});

  factory DriverLink.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return DriverLink(
      id: doc.id,
      members: List<String>.from(d['members'] as List? ?? const []),
      requestedBy: d['requestedBy'] as String? ?? '',
      requesterName: d['requesterName'] as String? ?? '',
      targetName: d['targetName'] as String? ?? '',
      connected: d['status'] == 'connected',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  String otherUid(String me) => members.firstWhere((m) => m != me, orElse: () => '');
  String otherName(String me) => requestedBy == me ? targetName : requesterName;
  bool incomingFor(String me) => !connected && requestedBy != me;
}

/// `driver_groups/{id}`: trip, route, convoy or fleet group of connected drivers.
class DriverGroup {
  final String id;
  final String name;
  final String kind;
  final String ownerId;
  final List<String> memberIds;

  const DriverGroup({required this.id, required this.name, required this.kind, required this.ownerId, required this.memberIds});

  factory DriverGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return DriverGroup(
      id: doc.id,
      name: d['name'] as String? ?? '',
      kind: d['kind'] as String? ?? 'trip',
      ownerId: d['ownerId'] as String? ?? '',
      memberIds: List<String>.from(d['memberIds'] as List? ?? const []),
    );
  }
}

/// A message in a driver chat or a group chat; may carry a load card.
class NetworkMessage {
  static const maxLength = 500;
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final SharedLoad? loadCard;
  final bool flagged;
  final DateTime? createdAt;

  const NetworkMessage({required this.id, required this.senderId, required this.senderName, required this.text, this.loadCard, this.flagged = false, this.createdAt});

  factory NetworkMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return NetworkMessage(
      id: doc.id,
      senderId: d['senderId'] as String? ?? '',
      senderName: d['senderName'] as String? ?? '',
      text: d['text'] as String? ?? '',
      loadCard: SharedLoad.fromMap(d['loadCard']),
      flagged: d['flagged'] == true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
