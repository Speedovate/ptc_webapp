import 'package:flutter_test/flutter_test.dart';
import 'package:webapp/models/support_thread.dart';
import 'package:webapp/models/support_message.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/services/support_read_state.dart';

void main() {
  test(
    'menu badge stays zero when own chat is read and another account is unread',
    () {
      final own = SupportThread(
        id: 'own',
        requesterUserId: '20',
        lastSenderUserId: '1',
        lastMessageText: 'Hello',
        lastMessageAt: DateTime.utc(2026, 10, 29),
      );
      final other = own.copyWith(id: 'other', requesterUserId: '21');
      expect(
        unreadSupportThreadCount(
          threads: [own, other],
          viewer: const UserModel(id: '20', role: 'dispatcher'),
          markers: {'own': supportThreadReadMarker(own)},
          canBrowseAllThreads: false,
          markersResolved: true,
        ),
        0,
      );
      // A role allowed to browse both conversations still sees the genuine unread.
      expect(
        unreadSupportThreadCount(
          threads: [own, other],
          viewer: const UserModel(id: '20', role: 'dispatcher'),
          markers: {'own': supportThreadReadMarker(own)},
          canBrowseAllThreads: true,
          markersResolved: true,
        ),
        1,
      );
    },
  );
  SupportThread incoming(int minute, {String sender = '2'}) => SupportThread(
    id: 'chat',
    lastSenderUserId: sender,
    lastMessageText: 'Hello',
    lastMessageAt: DateTime.utc(2026, 10, 29, 9, minute),
  );
  test('unread is suppressed until read markers resolve', () {
    expect(
      isSupportThreadUnread(
        thread: incoming(1),
        currentUserId: '1',
        savedMarker: null,
        markersResolved: false,
      ),
      isFalse,
    );
  });
  test(
    'unread incoming conversation is consistently unread without a marker',
    () {
      expect(
        isSupportThreadUnread(
          thread: incoming(1),
          currentUserId: '1',
          savedMarker: null,
        ),
        isTrue,
      );
    },
  );
  test('own messages and empty conversations do not add an unread count', () {
    expect(
      isSupportThreadUnread(
        thread: incoming(1, sender: '1'),
        currentUserId: '1',
        savedMarker: null,
      ),
      isFalse,
    );
    expect(
      isSupportThreadUnread(
        thread: const SupportThread(id: 'empty'),
        currentUserId: '1',
        savedMarker: null,
      ),
      isFalse,
    );
  });
  test(
    'reading the latest message clears unread but a later message restores it',
    () {
      final marker = supportThreadReadMarker(incoming(2));
      expect(
        isSupportThreadUnread(
          thread: incoming(2),
          currentUserId: '1',
          savedMarker: marker,
        ),
        isFalse,
      );
      expect(
        isSupportThreadUnread(
          thread: incoming(3),
          currentUserId: '1',
          savedMarker: marker,
        ),
        isTrue,
      );
    },
  );
  test(
    'stale cached thread cannot reappear as unread after reading a newer message',
    () {
      expect(
        isSupportThreadUnread(
          thread: incoming(1),
          currentUserId: '1',
          savedMarker: supportThreadReadMarker(incoming(2)),
        ),
        isFalse,
      );
    },
  );
  test('format-only preview changes at the same message time remain read', () {
    final read = supportThreadReadMarker(incoming(2));
    final changed = incoming(
      2,
    ).copyWith(lastMessageText: 'Hello (updated preview)');
    expect(
      isSupportThreadUnread(
        thread: changed,
        currentUserId: '1',
        savedMarker: read,
      ),
      isFalse,
    );
  });
  test('thread and visible attachment message use the same marker', () {
    final at = DateTime.utc(2026, 10, 29);
    final message = SupportMessage(
      senderUserId: '2',
      createdAt: at,
      attachments: const [SupportAttachment(name: 'photo.jpg')],
    );
    final thread = SupportThread(
      lastSenderUserId: '2',
      lastMessageAt: at,
      lastMessageText: 'Sent an attachment',
    );
    expect(supportMessageReadMarker(message), supportThreadReadMarker(thread));
  });
  test(
    'late state refresh and delayed reads cannot roll back message progress',
    () {
      final old = supportThreadReadMarker(incoming(1));
      final latest = supportThreadReadMarker(incoming(2));
      expect(mergeSupportReadMarkers({'chat': latest}, {'chat': old}), {
        'chat': latest,
      });
      final documents = mergeSupportReadDocuments([
        {'id': 'chat', 'marker': latest, 'updated_at': '2026-10-29T10:00:00Z'},
        {'id': 'chat', 'marker': old, 'updated_at': '2026-10-29T11:00:00Z'},
        {'id': 'another', 'marker': old, 'updated_at': '2026-10-29T10:00:00Z'},
      ]);
      expect(documents, hasLength(2));
      expect(documents.first['marker'], latest);
    },
  );
}
