# DebtMate

DebtMate is a responsive, mobile-first Flutter web application for businesses that sell goods or services on credit. Use it in a browser on phones, tablets, and desktop computers. Firebase Authentication handles account access and Cloud Firestore stores tenant-scoped customer, debt, payment, recovery, and reminder records.

## Features

- Email/password authentication, password reset, owner/customer onboarding, and owner-managed staff linking.
- Customer records with search and optional customer-portal account linking.
- Credit entries with item, quantity, transaction date, due date, terms, notes, and an optional initial deposit.
- Atomic partial-payment recording with a balance and status recalculated in the same Firestore transaction.
- Overdue filtering and sorting, follow-up notes, promised payment dates, and internal-history risk categories.
- Dashboard summaries, date-filtered debt/payment reports, CSV export, reminder suggestions, and customer payment history.
- An in-app notification inbox with unread counts and optional browser push for account creation, payment activity, and due/overdue balances.
- Adaptive navigation and layouts for narrow phones, tablets, and wide desktop browsers.

The app does not process money, make loans, contact debtors through collection agents, use credit bureaus, or provide a native Android/iOS application in Phase 1. Firebase client setup in this repository targets the responsive web app.

## Firebase Setup

1. The web app is configured for the `dabtmateapp` Firebase project shown in the supplied Firebase Console screenshot.
2. In **Build → Authentication → Sign-in method**, enable Email/Password sign-in and configure the authorized web domain.
3. The application uses Cloud Firestore for records. Ensure Cloud Firestore is created in this project; the Realtime Database URL in the Firebase web config is not used by the current data layer. Deploy the included security rules and notification functions:

   ```powershell
   firebase login
   firebase deploy --only firestore:rules,functions --project dabtmateapp
   ```

   If the notification inbox shows `permission-denied`, deploy the current Firestore rules with `firebase deploy --only firestore:rules --project dabtmateapp`.

   Cloud Functions and scheduled alerts require the Firebase project to use the Blaze billing plan. Install Node.js 22 and Firebase CLI before deploying functions.

4. Run the web app; its Firebase Web App configuration is already in `lib/firebase_options.dart`:

   ```powershell
   flutter run -d chrome
   ```

   The web Firebase config values identify the Firebase app and are not service-account credentials. Restrict the web API key to the app's authorized domains in Google Cloud/Firebase settings.

5. Register the business owner, then complete the owner profile. Staff members and customers register first; an owner assigns staff by Firebase UID and links customers by Firebase UID from the customer record.

6. To enable browser push, open **Project settings → Cloud Messaging → Web configuration**, generate a Web Push certificate key pair, then run the app with its public key:

   ```powershell
   flutter run -d chrome --dart-define=FIREBASE_VAPID_KEY=YOUR_PUBLIC_VAPID_KEY
   ```

   In the app, open the notification bell and choose the notifications icon to grant browser permission. Production web builds must also be built with the same `--dart-define` value. Each browser must grant permission separately.

Firestore collections are `users`, `businesses`, `customers`, `debts`, `payments`, `followUps`, and `reminders`. User notification inboxes and browser push tokens are stored under `users/{uid}/notifications` and `users/{uid}/devices`. The rules in `firestore.rules` scope business access by `businessId`, customer portal access by the linked `customerId`, and notification access to each signed-in user.

## Reminders

When an owner or staff user opens the app, DebtMate creates in-app reminder suggestions for unpaid records due within three days or already overdue. The recovery screen tracks those suggestions. SMS and email actions open the device/browser's composer and log that it was opened; the app cannot verify delivery. After Cloud Functions are deployed, alerts are added to the inbox and sent to opted-in browsers for new accounts, payments, and daily upcoming/overdue checks. Push delivery requires the web-push key and browser permission; scheduled alerts require Cloud Functions billing.

## Checks

```powershell
flutter analyze
flutter test
flutter build web
```

Native Android/iOS builds are outside this Phase 1 scope and require separate platform Firebase app registrations and generated platform options.