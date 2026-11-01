const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const DAY_MS = 24 * 60 * 60 * 1000;
const TIME_ZONE = 'Africa/Kampala';

function calendarDay(date) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: TIME_ZONE,
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map(({ type, value }) => [type, value]));
  return Date.UTC(Number(values.year), Number(values.month) - 1, Number(values.day));
}

async function sendPush(uid, notification) {
  const devices = await db.collection('users').doc(uid).collection('devices').get();
  const tokens = devices.docs
    .map((device) => device.data().token)
    .filter((token) => typeof token === 'string' && token.length > 0);
  if (tokens.length === 0) return;

  for (let start = 0; start < tokens.length; start += 500) {
    const batch = tokens.slice(start, start + 500);
    const result = await admin.messaging().sendEachForMulticast({
      tokens: batch,
      notification: {
        title: notification.title,
        body: notification.message,
      },
      data: {
        notificationId: notification.id,
        type: notification.type,
      },
    });
    const removals = [];
    result.responses.forEach((response, index) => {
      const code = response.error?.code;
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        removals.push(
          devices.docs.find((device) => device.data().token === batch[index])
            ?.ref.delete(),
        );
      }
    });
    await Promise.all(removals.filter(Boolean));
  }
}

async function createNotification(uid, notification) {
  if (!uid) return;
  const ref = db
    .collection('users')
    .doc(uid)
    .collection('notifications')
    .doc(notification.id);
  try {
    await ref.create({
      type: notification.type,
      title: notification.title,
      message: notification.message,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      readAt: null,
    });
  } catch (error) {
    if (error.code === 6 || error.code === 'already-exists') return;
    throw error;
  }
  await sendPush(uid, notification);
}

async function notifyBusiness(businessId, notification, extraUids = []) {
  const users = await db.collection('users').where('businessId', '==', businessId).get();
  const recipientUids = new Set(extraUids.filter(Boolean));
  for (const user of users.docs) {
    if (['owner', 'staff'].includes(user.data().role)) recipientUids.add(user.id);
  }
  await Promise.all(
    [...recipientUids].map((uid) => createNotification(uid, notification)),
  );
}

exports.accountCreated = onDocumentCreated('users/{uid}', async (event) => {
  const profile = event.data?.data();
  if (!profile) return;
  await createNotification(event.params.uid, {
    id: 'account-welcome',
    type: 'account',
    title: 'Welcome to DebtMate',
    message: 'Your account is ready. You can now manage your credit records.',
  });
});

exports.paymentRecorded = onDocumentCreated('payments/{paymentId}', async (event) => {
  const payment = event.data?.data();
  if (!payment?.businessId) return;
  const customerSnapshot = payment.customerId
    ? await db.collection('customers').doc(payment.customerId).get()
    : null;
  const customer = customerSnapshot?.data();
  const amount = Number(payment.amount || 0).toLocaleString('en-UG');
  await notifyBusiness(payment.businessId, {
    id: `payment-${event.params.paymentId}`,
    type: 'payment',
    title: 'Payment recorded',
    message: `A payment of UGX ${amount} was recorded for ${payment.customerName || 'a customer'}.`,
  }, [customer?.portalUserId]);
});

exports.creditRecorded = onDocumentCreated('debts/{debtId}', async (event) => {
  const debt = event.data?.data();
  if (!debt?.businessId) return;
  await notifyBusiness(debt.businessId, {
    id: `debt-${event.params.debtId}`,
    type: 'debt',
    title: 'Credit recorded',
    message: `A credit record was added for ${debt.customerName || 'a customer'}.`,
  });
});

exports.dailyDebtAlerts = onSchedule(
  { schedule: 'every day 08:00', timeZone: TIME_ZONE, timeoutSeconds: 540 },
  async () => {
    const now = new Date();
    const today = calendarDay(now);
    const cutoff = admin.firestore.Timestamp.fromDate(new Date(now.getTime() + 4 * DAY_MS));
    const debts = await db.collection('debts').where('dueDate', '<=', cutoff).get();

    await Promise.all(debts.docs.map(async (document) => {
      const debt = document.data();
      const dueDate = debt.dueDate?.toDate?.();
      const balance = Number(debt.balance || 0);
      if (!debt.businessId || !dueDate || balance <= 0) return;

      const daysUntilDue = Math.round((calendarDay(dueDate) - today) / DAY_MS);
      if (daysUntilDue > 3) return;
      const overdue = daysUntilDue < 0;
      const dayKey = new Date(today).toISOString().slice(0, 10);
      const title = overdue ? 'Payment overdue' : 'Payment due soon';
      const timing = overdue
        ? `${Math.abs(daysUntilDue)} day(s) overdue`
        : daysUntilDue === 0
        ? 'due today'
        : `due in ${daysUntilDue} day(s)`;
      const notification = {
        id: `${overdue ? 'overdue' : 'due'}-${document.id}-${dayKey}`,
        type: overdue ? 'overdue' : 'due',
        title,
        message: `UGX ${balance.toLocaleString('en-UG')} for ${debt.customerName || 'a customer'} is ${timing}.`,
      };
      const customerSnapshot = debt.customerId
        ? await db.collection('customers').doc(debt.customerId).get()
        : null;
      await notifyBusiness(debt.businessId, notification, [
        customerSnapshot?.data()?.portalUserId,
      ]);
    }));
  },
);