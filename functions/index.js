// Sends an FCM push whenever an in-app notification document is created.
// Deploying Cloud Functions needs the Firebase Blaze plan (see docs/MANUAL_SETUP.md).
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

const STATUS_TITLES = {
  accepted: 'Booking accepted',
  picked_up: 'Load picked up',
  in_transit: 'Load in transit',
  delivered: 'Load delivered',
  cancelled: 'Booking cancelled',
};

function titleFor(n) {
  switch (n.type) {
    case 'load_accepted': return 'A driver accepted your load';
    case 'status_changed': return STATUS_TITLES[n.status] || 'Booking update';
    case 'rating_received': return 'You received a new rating';
    case 'booking_cancelled': return 'Booking cancelled by driver';
    default: return 'LoadGo';
  }
}

exports.pushOnNotification = onDocumentCreated('notifications/{id}', async (event) => {
  const n = event.data && event.data.data();
  if (!n || !n.userId) return;
  const db = getFirestore();
  const userRef = db.collection('users').doc(n.userId);
  const tokens = ((await userRef.get()).data() || {}).fcmTokens || [];
  if (tokens.length === 0) return;

  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: titleFor(n), body: n.message || '' },
    data: { type: String(n.type), bookingId: String(n.relatedId || '') },
  });

  // Drop tokens FCM says are no longer valid.
  const dead = [];
  res.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
      dead.push(tokens[i]);
    }
  });
  if (dead.length) await userRef.update({ fcmTokens: FieldValue.arrayRemove(...dead) });
});
