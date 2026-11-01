import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show canvas, ink, leaf;
import 'debtmate_models.dart';
import 'firestore_service.dart';
import 'push_notifications.dart';

final _moneyFormat = NumberFormat.currency(
  locale: 'en_UG',
  symbol: 'UGX ',
  decimalDigits: 0,
);
final _dateFormat = DateFormat('d MMM yyyy');

String _money(double value) => _moneyFormat.format(value);
String _date(DateTime value) => _dateFormat.format(value);

class _NavItem {
  const _NavItem(this.title, this.icon, this.selectedIcon);
  final String title;
  final IconData icon;
  final IconData selectedIcon;
}

const _businessNav = [
  _NavItem('Overview', Icons.space_dashboard_outlined, Icons.space_dashboard),
  _NavItem('Debts', Icons.receipt_long_outlined, Icons.receipt_long),
  _NavItem('Customers', Icons.people_outline, Icons.people),
  _NavItem('Recovery', Icons.track_changes_outlined, Icons.track_changes),
  _NavItem('Reports', Icons.query_stats_outlined, Icons.query_stats),
  _NavItem('Settings', Icons.settings_outlined, Icons.settings),
];

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.auth,
    required this.authUser,
    required this.profile,
    required this.service,
  });

  final FirebaseAuth auth;
  final User authUser;
  final BusinessUser profile;
  final FirestoreService service;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _page = 0;
  String _search = '';
  String _statusFilter = 'All';
  String _sortBy = 'Due date';
  String _reportRange = '30 days';
  late final Stream<List<CustomerRecord>> _customersStream;
  late final Stream<List<DebtRecord>> _debtsStream;
  late final Stream<List<PaymentRecord>> _paymentsStream;

  bool get _customer => widget.profile.isCustomer;
  List<_NavItem> get _navItems => _customer
      ? const [
          _NavItem(
            'Overview',
            Icons.space_dashboard_outlined,
            Icons.space_dashboard,
          ),
          _NavItem('Payments', Icons.payments_outlined, Icons.payments),
        ]
      : _businessNav
            .where((item) => item.title != 'Settings' || widget.profile.isOwner)
            .toList();

  @override
  void initState() {
    super.initState();
    _customersStream = _customer
        ? Stream.value(const [])
        : widget.service.watchCustomers(widget.profile.businessId);
    _debtsStream = _customer && widget.profile.customerId == null
        ? Stream.value(const [])
        : widget.service.watchDebts(
            businessId: widget.profile.businessId,
            customerId: _customer ? widget.profile.customerId : null,
          );
    _paymentsStream = _customer && widget.profile.customerId == null
        ? Stream.value(const [])
        : widget.service.watchPayments(
            businessId: widget.profile.businessId,
            customerId: _customer ? widget.profile.customerId : null,
          );
    if (!_customer) {
      widget.service
          .generateReminderSuggestions(
            businessId: widget.profile.businessId,
            actorUid: widget.authUser.uid,
          )
          .catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CustomerRecord>>(
    stream: _customersStream,
    builder: (context, customerSnapshot) => StreamBuilder<List<DebtRecord>>(
      stream: _debtsStream,
      builder: (context, debtSnapshot) => StreamBuilder<List<PaymentRecord>>(
        stream: _paymentsStream,
        builder: (context, paymentSnapshot) {
          if (customerSnapshot.hasError ||
              debtSnapshot.hasError ||
              paymentSnapshot.hasError) {
            final error =
                customerSnapshot.error ??
                debtSnapshot.error ??
                paymentSnapshot.error;
            return _LoadError(message: error.toString());
          }
          if (customerSnapshot.connectionState == ConnectionState.waiting ||
              debtSnapshot.connectionState == ConnectionState.waiting ||
              paymentSnapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final customers = customerSnapshot.data ?? const <CustomerRecord>[];
          final debts = debtSnapshot.data ?? const <DebtRecord>[];
          final payments = paymentSnapshot.data ?? const <PaymentRecord>[];
          return _buildScaffold(context, customers, debts, payments);
        },
      ),
    ),
  );

  Widget _buildScaffold(
    BuildContext context,
    List<CustomerRecord> customers,
    List<DebtRecord> debts,
    List<PaymentRecord> payments,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 900;
    final items = _navItems;
    if (_page >= items.length && (_customer || !widget.profile.isOwner)) {
      _page = 0;
    }
    final selected = items[_page];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (compact)
              const Icon(Icons.account_balance_wallet_outlined, color: leaf),
            if (compact) const SizedBox(width: 9),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                if (!compact && !_customer)
                  Text(
                    widget.profile.businessName,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF687870),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          if (!compact && !_customer && _page == 1)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: customers.isEmpty
                    ? null
                    : () => _showDebtDialog(context, customers),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Record credit'),
              ),
            ),
          if (!compact && !_customer && _page == 2)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: () => _showCustomerDialog(context),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Add customer'),
              ),
            ),
          if (!_customer && _page == 4)
            IconButton(
              tooltip: 'Export reports',
              onPressed: () => _exportReports(context, debts, payments),
              icon: const Icon(Icons.download_outlined),
            ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: widget.service.watchNotifications(widget.authUser.uid),
            builder: (context, snapshot) {
              final unread =
                  snapshot.data?.docs
                      .where((doc) => doc.data()['readAt'] == null)
                      .length ??
                  0;
              return IconButton(
                tooltip: 'Notifications',
                onPressed: () => _showNotifications(context),
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
              );
            },
          ),
          if (width > 700)
            IconButton(
              tooltip: 'Sign out',
              onPressed: widget.auth.signOut,
              icon: const Icon(Icons.logout),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          if (!compact)
            NavigationRail(
              extended: width >= 1180,
              selectedIndex: _page,
              onDestinationSelected: (index) => setState(() => _page = index),
              labelType: width >= 1180
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              backgroundColor: canvas,
              destinations: [
                for (final item in items)
                  NavigationRailDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon),
                    label: Text(item.title),
                  ),
              ],
            ),
          if (!compact) const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _pageContent(context, customers, debts, payments)),
        ],
      ),
      bottomNavigationBar: compact
          ? NavigationBar(
              selectedIndex: _customer
                  ? _page
                  : _page < 3
                  ? _page
                  : 3,
              onDestinationSelected: (index) {
                if (_customer || index < 3) {
                  setState(() => _page = index);
                } else {
                  _showMoreMenu(context, items);
                }
              },
              destinations: _customer
                  ? const [
                      NavigationDestination(
                        icon: Icon(Icons.space_dashboard_outlined),
                        label: 'Overview',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.payments_outlined),
                        label: 'Payments',
                      ),
                    ]
                  : const [
                      NavigationDestination(
                        icon: Icon(Icons.space_dashboard_outlined),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        label: 'Debts',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.people_outline),
                        label: 'Customers',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.more_horiz),
                        label: 'More',
                      ),
                    ],
            )
          : null,
      floatingActionButton: compact && !_customer && (_page == 1 || _page == 2)
          ? FloatingActionButton(
              onPressed: _page == 1
                  ? customers.isEmpty
                        ? null
                        : () => _showDebtDialog(context, customers)
                  : () => _showCustomerDialog(context),
              tooltip: _page == 1 ? 'Record credit' : 'Add customer',
              child: Icon(
                _page == 1 ? Icons.add_card_outlined : Icons.person_add_alt_1,
              ),
            )
          : null,
    );
  }

  void _showNotifications(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _NotificationInbox(service: widget.service, uid: widget.authUser.uid),
    );
  }

  void _showMoreMenu(BuildContext context, List<_NavItem> items) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 3; index < items.length; index++)
              ListTile(
                leading: Icon(items[index].icon),
                title: Text(items[index].title),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _page = index);
                },
              ),
            if (widget.profile.isOwner)
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () {
                  Navigator.pop(context);
                  widget.auth.signOut();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _pageContent(
    BuildContext context,
    List<CustomerRecord> customers,
    List<DebtRecord> debts,
    List<PaymentRecord> payments,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1500),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            width < 600 ? 16 : 28,
            24,
            width < 600 ? 16 : 28,
            32,
          ),
          child: switch (_page) {
            0 => _overview(context, customers, debts, payments),
            1 when _customer => _customerPayments(payments),
            1 => _debtLedger(context, customers, debts),
            2 => _customerList(context, customers, debts),
            3 => _recoveryPage(context, customers, debts),
            4 => _reports(context, debts, payments),
            _ => _settings(context),
          },
        ),
      ),
    );
  }

  Widget _overview(
    BuildContext context,
    List<CustomerRecord> customers,
    List<DebtRecord> debts,
    List<PaymentRecord> payments,
  ) {
    final balance = debts.fold<double>(
      0,
      (total, debt) => total + debt.balance,
    );
    final overdue = debts
        .where((debt) => debt.isOverdue && debt.balance > 0)
        .toList();
    final overdueValue = overdue.fold<double>(
      0,
      (total, debt) => total + debt.balance,
    );
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month);
    final receivedThisMonth = payments
        .where((payment) => payment.date.isAfter(monthStart))
        .fold<double>(0, (total, payment) => total + payment.amount);
    if (_customer) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeading(
            title: 'Hello, ${widget.profile.name}',
            subtitle: 'Your current balances and recorded repayments.',
          ),
          const SizedBox(height: 20),
          _metrics([
            (
              'Balance due',
              _money(balance),
              Icons.account_balance_wallet_outlined,
              leaf,
            ),
            (
              'Payments recorded',
              payments.length.toString(),
              Icons.receipt_outlined,
              const Color(0xFF557B7A),
            ),
          ]),
          const SizedBox(height: 24),
          _sectionTitle('Your credit accounts'),
          const SizedBox(height: 10),
          if (debts.isEmpty)
            const _EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No linked account yet',
              message: 'Your business will link your DebtMate account to your customer record.',
            ),
          for (final debt in debts)
            _DebtTile(
              debt: debt,
              currency: _money,
              onPayment: null,
              onFollowUp: null,
              onReminder: null,
            ),
          const SizedBox(height: 24),
          _sectionTitle('Recent payments'),
          const SizedBox(height: 10),
          _paymentRows(payments.take(5).toList()),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          title: 'Good ${_greeting()}, ${widget.profile.name.split(' ').first}',
          subtitle: 'Here is your credit position at a glance.',
          trailing: Text(
            DateFormat('EEEE, d MMM').format(DateTime.now()),
            style: const TextStyle(color: Color(0xFF687870)),
          ),
        ),
        const SizedBox(height: 22),
        _metrics([
          (
            'Outstanding',
            _money(balance),
            Icons.account_balance_wallet_outlined,
            leaf,
          ),
          (
            'Overdue',
            _money(overdueValue),
            Icons.schedule,
            const Color(0xFFC2544A),
          ),
          (
            'Received this month',
            _money(receivedThisMonth),
            Icons.south_west,
            const Color(0xFF4E7890),
          ),
          (
            'Customers',
            customers.length.toString(),
            Icons.people_outline,
            const Color(0xFFAE7B34),
          ),
        ]),
        const SizedBox(height: 26),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 950;
            final overduePanel = _Panel(
              title: 'Needs follow-up',
              action: TextButton(
                onPressed: () => setState(() => _page = 3),
                child: const Text('Open recovery'),
              ),
              child: overdue.isEmpty
                  ? const _InlineEmpty(message: 'No overdue balances today.')
                  : Column(
                      children: [
                        for (final debt in overdue.take(5))
                          _CompactDebtLine(
                            debt: debt,
                            onTap: () => setState(() => _page = 3),
                          ),
                      ],
                    ),
            );
            final pacePanel = _Panel(
              title: 'Portfolio mix',
              child: _PortfolioMix(debts: debts),
            );
            if (!wide) {
              return Column(
                children: [overduePanel, const SizedBox(height: 14), pacePanel],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: overduePanel),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: pacePanel),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        _sectionTitle('Latest credit activity'),
        const SizedBox(height: 10),
        if (debts.isEmpty)
          const _EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No credit recorded',
            message: 'Add your first customer and record a credit transaction to begin.',
          ),
        for (final debt in debts.take(5))
          _DebtTile(
            debt: debt,
            currency: _money,
            onPayment: () => _showPaymentDialog(context, debt),
            onFollowUp: () => _showFollowUpDialog(context, debt),
            onReminder: () => _composeReminder(context, debt, customers),
          ),
      ],
    );
  }

  Widget _debtLedger(
    BuildContext context,
    List<CustomerRecord> customers,
    List<DebtRecord> debts,
  ) {
    final filtered = debts.where((debt) {
      final matchesText = '${debt.customerName} ${debt.itemDescription}'
          .toLowerCase()
          .contains(_search.toLowerCase());
      return matchesText &&
          (_statusFilter == 'All' || debt.status == _statusFilter);
    }).toList();
    filtered.sort(
      (a, b) => switch (_sortBy) {
        'Largest balance' => b.balance.compareTo(a.balance),
        'Oldest overdue' => b.daysOverdue.compareTo(a.daysOverdue),
        'Newest' => b.transactionDate.compareTo(a.transactionDate),
        _ => a.dueDate.compareTo(b.dueDate),
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          title: 'Credit ledger',
          subtitle:
              '${debts.length} records · balances update as payments are recorded.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search customer or item',
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                initialValue: _statusFilter,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const ['All', 'Open', 'Partial', 'Overdue', 'Paid']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _statusFilter = value ?? 'All'),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                initialValue: _sortBy,
                decoration: const InputDecoration(labelText: 'Sort by'),
                items:
                    const [
                          'Due date',
                          'Largest balance',
                          'Oldest overdue',
                          'Newest',
                        ]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: (value) =>
                    setState(() => _sortBy = value ?? 'Due date'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (customers.isEmpty)
          const _EmptyState(
            icon: Icons.person_add_alt_1,
            title: 'Add a customer first',
            message: 'Every credit transaction belongs to a customer record.',
          ),
        if (customers.isNotEmpty && filtered.isEmpty)
          const _EmptyState(
            icon: Icons.search_off,
            title: 'No matching debt',
            message: 'Try another search or status filter.',
          ),
        for (final debt in filtered)
          _DebtTile(
            debt: debt,
            currency: _money,
            onPayment: debt.isPaid
                ? null
                : () => _showPaymentDialog(context, debt),
            onFollowUp: debt.isPaid
                ? null
                : () => _showFollowUpDialog(context, debt),
            onReminder: debt.isPaid
                ? null
                : () => _composeReminder(context, debt, customers),
          ),
      ],
    );
  }

  Widget _customerList(
    BuildContext context,
    List<CustomerRecord> customers,
    List<DebtRecord> debts,
  ) {
    final filtered = customers
        .where(
          (customer) => '${customer.name} ${customer.phone} ${customer.email}'
              .toLowerCase()
              .contains(_search.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          title: 'Customers',
          subtitle:
              'Customer details, balances and internal repayment indicators.',
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 340,
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search name or contact',
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          const _EmptyState(
            icon: Icons.people_outline,
            title: 'No customers found',
            message: 'Add a customer to start tracking credit and repayments.',
          ),
        for (final customer in filtered)
          _CustomerTile(
            customer: customer,
            debts: debts
                .where((debt) => debt.customerId == customer.id)
                .toList(),
            onEdit: () => _showCustomerDialog(context, customer: customer),
            onDebt: () =>
                _showDebtDialog(context, customers, customer: customer),
            currency: _money,
          ),
      ],
    );
  }

  Widget _recoveryPage(
    BuildContext context,
    List<CustomerRecord> customers,
    List<DebtRecord> debts,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: widget.service.watchFollowUps(widget.profile.businessId),
    builder: (context, followSnapshot) {
      final followUps = followSnapshot.data?.docs.toList() ?? [];
      followUps.sort(
        (a, b) =>
            dateValue(b.data()['createdAt'])
                .compareTo(dateValue(a.data()['createdAt'])),
      );
      final overdue = debts
          .where((debt) => debt.isOverdue && debt.balance > 0)
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeading(
            title: 'Recovery desk',
            subtitle: 'Prioritise overdue accounts and keep every follow-up traceable.',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  'Overdue accounts',
                  '${overdue.length}',
                  Icons.warning_amber_outlined,
                  const Color(0xFFC2544A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _metricCard(
                  'Open follow-ups',
                  '${followUps.length}',
                  Icons.forum_outlined,
                  const Color(0xFF4E7890),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _sectionTitle('Priority accounts'),
          const SizedBox(height: 10),
          if (overdue.isEmpty)
            const _InlineEmpty(message: 'No overdue balances need attention.'),
          for (final debt in overdue)
            _DebtTile(
              debt: debt,
              currency: _money,
              onPayment: () => _showPaymentDialog(context, debt),
              onFollowUp: () => _showFollowUpDialog(context, debt),
              onReminder: () => _composeReminder(context, debt, customers),
            ),
          const SizedBox(height: 22),
          _sectionTitle('Recent follow-up history'),
          const SizedBox(height: 10),
          if (followSnapshot.hasError)
            _InlineError(message: followSnapshot.error.toString()),
          if (!followSnapshot.hasData && !followSnapshot.hasError)
            const LinearProgressIndicator(),
          if (followSnapshot.hasData && followUps.isEmpty)
            const _InlineEmpty(message: 'Follow-up actions will appear here.'),
          for (final doc in followUps.take(30)) _FollowUpTile(data: doc.data()),
          const SizedBox(height: 22),
          _sectionTitle('Reminder queue'),
          const SizedBox(height: 10),
          _ReminderQueue(
            service: widget.service,
            businessId: widget.profile.businessId,
          ),
        ],
      );
    },
  );

  Widget _customerPayments(List<PaymentRecord> payments) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _PageHeading(
        title: 'Payment history',
        subtitle: 'Recorded payments linked to your customer account.',
      ),
      const SizedBox(height: 18),
      _paymentRows(payments),
    ],
  );

  Widget _reports(
    BuildContext context,
    List<DebtRecord> debts,
    List<PaymentRecord> payments,
  ) {
    final cutoff = switch (_reportRange) {
      '7 days' => DateTime.now().subtract(const Duration(days: 7)),
      '90 days' => DateTime.now().subtract(const Duration(days: 90)),
      'All time' => DateTime.fromMillisecondsSinceEpoch(0),
      _ => DateTime.now().subtract(const Duration(days: 30)),
    };
    final filteredDebts = debts
        .where((debt) => debt.transactionDate.isAfter(cutoff))
        .toList();
    final filteredPayments = payments
        .where((payment) => payment.date.isAfter(cutoff))
        .toList();
    final credit = filteredDebts.fold<double>(
      0,
      (total, debt) => total + debt.totalAmount,
    );
    final paid = filteredPayments.fold<double>(
      0,
      (total, payment) => total + payment.amount,
    );
    final overdue = filteredDebts
        .where((debt) => debt.isOverdue)
        .fold<double>(0, (total, debt) => total + debt.balance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PageHeading(
          title: 'Reports',
          subtitle: 'Filter business activity and export CSV files for further analysis.',
          trailing: IconButton.filledTonal(
            tooltip: 'Export reports',
            onPressed: () => _exportReports(
              context,
              filteredDebts,
              filteredPayments,
              cutoff: cutoff,
            ),
            icon: const Icon(Icons.download_outlined),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            initialValue: _reportRange,
            decoration: const InputDecoration(labelText: 'Date range'),
            items: const ['7 days', '30 days', '90 days', 'All time']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => _reportRange = value ?? '30 days'),
          ),
        ),
        const SizedBox(height: 16),
        _metrics([
          ('Credit recorded', _money(credit), Icons.add_card_outlined, leaf),
          (
            'Payments received',
            _money(paid),
            Icons.south_west,
            const Color(0xFF4E7890),
          ),
          (
            'Overdue balance',
            _money(overdue),
            Icons.schedule,
            const Color(0xFFC2544A),
          ),
          (
            'Accounts with payments',
            filteredDebts
                .where((debt) => debt.amountPaid > 0)
                .length
                .toString(),
            Icons.check_circle_outline,
            const Color(0xFFAE7B34),
          ),
        ]),
        const SizedBox(height: 24),
        _sectionTitle('Debt report'),
        const SizedBox(height: 10),
        for (final debt in filteredDebts)
          _DebtTile(
            debt: debt,
            currency: _money,
            onPayment: null,
            onFollowUp: null,
            onReminder: null,
          ),
        const SizedBox(height: 22),
        _sectionTitle('Payment report'),
        const SizedBox(height: 10),
        _paymentRows(filteredPayments),
        const SizedBox(height: 22),
        _sectionTitle('Recovery report'),
        const SizedBox(height: 10),
        _recoveryReport(cutoff),
      ],
    );
  }

  Widget _recoveryReport(DateTime cutoff) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.service.watchFollowUps(widget.profile.businessId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _InlineError(message: snapshot.error.toString());
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final records =
              snapshot.data!.docs
                  .where(
                    (doc) => dateValue(doc.data()['createdAt']).isAfter(cutoff),
                  )
                  .toList()
                ..sort(
                  (a, b) =>
                      dateValue(b.data()['createdAt'])
                          .compareTo(dateValue(a.data()['createdAt'])),
                );
          if (records.isEmpty) {
            return const _InlineEmpty(
              message: 'No recovery actions in this date range.',
            );
          }
          return Column(
            children: [
              for (final record in records) _FollowUpTile(data: record.data()),
            ],
          );
        },
      );

  Widget _settings(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _PageHeading(
        title: 'Business settings',
        subtitle: 'Manage staff access and review the signed-in account.',
      ),
      const SizedBox(height: 18),
      _Panel(
        title: 'Business profile',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.profile.businessName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Owner account · ${widget.authUser.email ?? widget.authUser.phoneNumber ?? widget.authUser.uid}',
              style: const TextStyle(color: Color(0xFF687870)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _Panel(
        title: 'Add an existing DebtMate user as staff',
        child: _StaffForm(service: widget.service, owner: widget.profile),
      ),
      const SizedBox(height: 18),
      _Panel(
        title: 'Access model',
        child: const Text(
          'Staff can manage customers, credit, payments and recovery for this business. Customer accounts only see records explicitly linked to their account UID.',
        ),
      ),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: widget.auth.signOut,
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ],
  );

  Widget _metrics(List<(String, String, IconData, Color)> values) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1080
              ? 4
              : constraints.maxWidth >= 580
              ? 2
              : 1;
          final itemWidth =
              (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final value in values)
                SizedBox(
                  width: itemWidth,
                  child: _metricCard(value.$1, value.$2, value.$3, value.$4),
                ),
            ],
          );
        },
      );

  Widget _metricCard(String label, String value, IconData icon, Color color) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF687870),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _showCustomerDialog(
    BuildContext context, {
    CustomerRecord? customer,
  }) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: customer?.name ?? '');
    final phone = TextEditingController(text: customer?.phone ?? '');
    final email = TextEditingController(text: customer?.email ?? '');
    final address = TextEditingController(text: customer?.address ?? '');
    final notes = TextEditingController(text: customer?.notes ?? '');
    final portalUid = TextEditingController(text: customer?.portalUserId ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(customer == null ? 'Add customer' : 'Edit customer'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Full name'),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: address,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: portalUid,
                    decoration: const InputDecoration(
                      labelText: 'Customer portal user UID',
                      helperText: 'Optional. Copy the customer account UID from Firebase Authentication.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Save customer'),
          ),
        ],
      ),
    );
    if (result == true && context.mounted) {
      try {
        await widget.service.saveCustomer(
          id: customer?.id,
          businessId: widget.profile.businessId,
          name: name.text,
          phone: phone.text,
          email: email.text,
          address: address.text,
          notes: notes.text,
          portalUserId: portalUid.text,
          actorUid: widget.authUser.uid,
        );
        if (!context.mounted) return;
        _notice(context, 'Customer saved.');
      } catch (error) {
        if (context.mounted) {
          _notice(context, error.toString(), error: true);
        }
      }
    }
    name.dispose();
    phone.dispose();
    email.dispose();
    address.dispose();
    notes.dispose();
    portalUid.dispose();
  }

  Future<void> _showDebtDialog(
    BuildContext context,
    List<CustomerRecord> customers, {
    CustomerRecord? customer,
  }) async {
    if (customers.isEmpty) return;
    final formKey = GlobalKey<FormState>();
    final item = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final total = TextEditingController();
    final deposit = TextEditingController(text: '0');
    final terms = TextEditingController();
    final notes = TextEditingController();
    var selectedCustomer = customer?.id ?? customers.first.id;
    var transactionDate = DateTime.now();
    var dueDate = DateTime.now().add(const Duration(days: 14));
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record credit'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedCustomer,
                      decoration: const InputDecoration(labelText: 'Customer'),
                      items: customers
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.id,
                              child: Text(
                                entry.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          selectedCustomer = value ?? selectedCustomer,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: item,
                      decoration: const InputDecoration(
                        labelText: 'Item or service description',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: quantity,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                            ),
                            validator: _positiveNumber,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: total,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Total amount (UGX)',
                            ),
                            validator: _positiveNumber,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: deposit,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Initial deposit (UGX)',
                      ),
                      validator: (value) => _nonNegativeNumber(value),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _dateField(
                            context,
                            'Transaction date',
                            transactionDate,
                            (value) =>
                                setDialogState(() => transactionDate = value),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _dateField(
                            context,
                            'Due date',
                            dueDate,
                            (value) => setDialogState(() => dueDate = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: terms,
                      decoration: const InputDecoration(
                        labelText: 'Payment terms (optional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: notes,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Record credit'),
            ),
          ],
        ),
      ),
    );
    if (result == true && context.mounted) {
      try {
        final chosen = customers.firstWhere(
          (entry) => entry.id == selectedCustomer,
        );
        await widget.service.createDebt(
          businessId: widget.profile.businessId,
          actorUid: widget.authUser.uid,
          customer: chosen,
          itemDescription: item.text,
          quantity: double.parse(quantity.text),
          totalAmount: double.parse(total.text),
          initialDeposit: double.parse(deposit.text),
          transactionDate: transactionDate,
          dueDate: dueDate,
          terms: terms.text,
          notes: notes.text,
        );
        if (!context.mounted) return;
        _notice(context, 'Credit transaction recorded.');
      } catch (error) {
        if (context.mounted) {
          _notice(context, error.toString(), error: true);
        }
      }
    }
    item.dispose();
    quantity.dispose();
    total.dispose();
    deposit.dispose();
    terms.dispose();
    notes.dispose();
  }

  Future<void> _showPaymentDialog(BuildContext context, DebtRecord debt) async {
    final formKey = GlobalKey<FormState>();
    final amount = TextEditingController(text: debt.balance.toStringAsFixed(0));
    final reference = TextEditingController();
    final notes = TextEditingController();
    var method = 'Cash';
    var date = DateTime.now();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record payment'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${debt.customerName} · ${_money(debt.balance)} remaining',
                      style: const TextStyle(color: Color(0xFF687870)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount received (UGX)',
                    ),
                    validator: (value) {
                      final parsed = double.tryParse(value ?? '');
                      if (parsed == null || parsed <= 0) {
                        return 'Enter a positive amount';
                      }
                      if (parsed > debt.balance) {
                        return 'Cannot exceed ${_money(debt.balance)}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                    ),
                    items:
                        const ['Cash', 'Mobile money', 'Bank transfer', 'Other']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setDialogState(() => method = value ?? 'Cash'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'Reference (optional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _dateField(
                    context,
                    'Payment date',
                    date,
                    (value) => setDialogState(() => date = value),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: notes,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save payment'),
            ),
          ],
        ),
      ),
    );
    if (result == true && context.mounted) {
      try {
        await widget.service.recordPayment(
          debtId: debt.id,
          actorUid: widget.authUser.uid,
          amount: double.parse(amount.text),
          method: method,
          reference: reference.text,
          notes: notes.text,
          date: date,
        );
        if (!context.mounted) return;
        _notice(context, 'Payment recorded and balance updated.');
      } catch (error) {
        if (context.mounted) {
          _notice(context, error.toString(), error: true);
        }
      }
    }
    amount.dispose();
    reference.dispose();
    notes.dispose();
  }

  Future<void> _showFollowUpDialog(
    BuildContext context,
    DebtRecord debt,
  ) async {
    final formKey = GlobalKey<FormState>();
    final notes = TextEditingController();
    final promisedAmount = TextEditingController();
    var outcome = 'Contacted';
    DateTime? promisedDate;
    DateTime? nextDate;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Follow up · ${debt.customerName}'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: outcome,
                    decoration: const InputDecoration(labelText: 'Outcome'),
                    items:
                        const [
                              'Contacted',
                              'No answer',
                              'Promise to pay',
                              'Disputed',
                              'Escalated',
                              'Other',
                            ]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setDialogState(() => outcome = value ?? 'Contacted'),
                  ),
                  if (outcome == 'Promise to pay') ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: promisedAmount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Promised amount (UGX)',
                      ),
                      validator: (value) => outcome == 'Promise to pay'
                          ? _positiveNumber(value)
                          : null,
                    ),
                    const SizedBox(height: 10),
                    _nullableDateField(
                      context,
                      'Promised payment date',
                      promisedDate,
                      (value) => setDialogState(() => promisedDate = value),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _nullableDateField(
                    context,
                    'Next follow-up date',
                    nextDate,
                    (value) => setDialogState(() => nextDate = value),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Call or visit notes',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save follow-up'),
            ),
          ],
        ),
      ),
    );
    if (result == true && context.mounted) {
      try {
        await widget.service.recordFollowUp(
          businessId: widget.profile.businessId,
          actorUid: widget.authUser.uid,
          debt: debt,
          outcome: outcome,
          notes: notes.text,
          promisedDate: promisedDate,
          promisedAmount: promisedAmount.text.isEmpty
              ? null
              : double.tryParse(promisedAmount.text),
          nextFollowUpAt: nextDate,
        );
        if (!context.mounted) return;
        _notice(context, 'Follow-up saved.');
      } catch (error) {
        if (context.mounted) {
          _notice(context, error.toString(), error: true);
        }
      }
    }
    notes.dispose();
    promisedAmount.dispose();
  }

  Future<void> _composeReminder(
    BuildContext context,
    DebtRecord debt,
    List<CustomerRecord> customers,
  ) async {
    final customer = customers
        .where((entry) => entry.id == debt.customerId)
        .firstOrNull;
    if (customer == null) {
      _notice(
        context,
        'Customer contact details are unavailable.',
        error: true,
      );
      return;
    }
    final channel = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sms_outlined),
              title: const Text('Text message'),
              subtitle: Text(customer.phone),
              onTap: customer.phone.isEmpty
                  ? null
                  : () => Navigator.pop(context, 'sms'),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Email'),
              subtitle: Text(customer.email),
              onTap: customer.email.isEmpty
                  ? null
                  : () => Navigator.pop(context, 'email'),
            ),
          ],
        ),
      ),
    );
    if (channel == null || !context.mounted) return;
    final message =
        'Hello ${customer.name}, this is a reminder that ${_money(debt.balance)} remains outstanding for ${debt.itemDescription}. The due date is ${_date(debt.dueDate)}. Please contact us if you have questions.';
    final uri = channel == 'sms'
        ? Uri(
            scheme: 'sms',
            path: customer.phone,
            queryParameters: {'body': message},
          )
        : Uri(
            scheme: 'mailto',
            path: customer.email,
            queryParameters: {
              'subject': 'Payment reminder from ${widget.profile.businessName}',
              'body': message,
            },
          );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!context.mounted) return;
      if (launched) {
        await widget.service.recordReminderAction(
          businessId: widget.profile.businessId,
          actorUid: widget.authUser.uid,
          debt: debt,
          channel: channel,
          phone: customer.phone,
          email: customer.email,
          message: message,
        );
        if (context.mounted) {
          _notice(
            context,
            'Message composer opened. Delivery is not confirmed until sent.',
          );
        }
      } else {
        _notice(context, 'No compatible messaging app was found.', error: true);
      }
    } catch (error) {
      if (context.mounted) {
        _notice(
          context,
          'Could not open the message composer: $error',
          error: true,
        );
      }
    }
  }

  Future<void> _exportReports(
    BuildContext context,
    List<DebtRecord> debts,
    List<PaymentRecord> payments, {
    DateTime? cutoff,
  }) async {
    try {
      final followUpSnapshot = await widget.service.db
          .collection('followUps')
          .where('businessId', isEqualTo: widget.profile.businessId)
          .get();
      final followUps = followUpSnapshot.docs.where(
        (doc) =>
            cutoff == null ||
            dateValue(doc.data()['createdAt']).isAfter(cutoff),
      );
      final rows = <List<dynamic>>[
        [
          'Record type',
          'Date',
          'Customer',
          'Description / method',
          'Total / amount (UGX)',
          'Paid (UGX)',
          'Balance (UGX)',
          'Due date',
          'Status / outcome',
          'Reference / notes',
        ],
        ...debts.map(
          (debt) => [
            'Credit',
            _date(debt.transactionDate),
            debt.customerName,
            debt.itemDescription,
            debt.totalAmount,
            debt.amountPaid,
            debt.balance,
            _date(debt.dueDate),
            debt.status,
            '',
          ],
        ),
        ...payments.map(
          (payment) => [
            'Payment',
            _date(payment.date),
            payment.customerName,
            payment.method,
            payment.amount,
            payment.amount,
            '',
            '',
            '',
            payment.reference,
          ],
        ),
        ...followUps.map((doc) {
          final data = doc.data();
          final promisedDate = data['promisedDate'] == null
              ? ''
              : _date(dateValue(data['promisedDate']));
          return [
            'Recovery',
            _date(dateValue(data['createdAt'])),
            data['customerName'] ?? '',
            data['outcome'] ?? '',
            data['promisedAmount'] ?? '',
            '',
            '',
            promisedDate,
            data['outcome'] ?? '',
            data['notes'] ?? '',
          ];
        }),
      ];
      await FileSaver.instance.saveFile(
        name:
            'debtmate-report-${DateFormat('yyyyMMdd').format(DateTime.now())}',
        bytes: Uint8List.fromList(utf8.encode(Csv().encode(rows))),
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );
      if (context.mounted) _notice(context, 'CSV report exported.');
    } catch (error) {
      if (context.mounted) {
        _notice(context, 'Report export failed: $error', error: true);
      }
    }
  }

  Widget _dateField(
    BuildContext context,
    String label,
    DateTime value,
    ValueChanged<DateTime> onChanged,
  ) => InkWell(
    onTap: () async {
      final selected = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (selected != null) onChanged(selected);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_month_outlined),
      ),
      child: Text(_date(value)),
    ),
  );

  Widget _nullableDateField(
    BuildContext context,
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged,
  ) => InkWell(
    onTap: () async {
      final selected = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now().add(const Duration(days: 7)),
        firstDate: DateTime.now(),
        lastDate: DateTime(2100),
      );
      if (selected != null) onChanged(selected);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null)
              IconButton(
                tooltip: 'Clear date',
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close, size: 18),
              ),
            const Icon(Icons.calendar_month_outlined),
            const SizedBox(width: 12),
          ],
        ),
      ),
      child: Text(value == null ? 'Not set' : _date(value)),
    ),
  );

  String _greeting() {
    final hour = DateTime.now().hour;
    return hour < 12
        ? 'morning'
        : hour < 17
        ? 'afternoon'
        : 'evening';
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.title,
    required this.subtitle,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: Color(0xFF687870)),
            ),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

Widget _sectionTitle(String title) => Text(
  title,
  style: const TextStyle(fontSize: 16, color: ink, fontWeight: FontWeight.w700),
);

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _PortfolioMix extends StatelessWidget {
  const _PortfolioMix({required this.debts});
  final List<DebtRecord> debts;

  @override
  Widget build(BuildContext context) {
    final open = debts
        .where((debt) => debt.balance > 0 && !debt.isOverdue)
        .length;
    final overdue = debts.where((debt) => debt.isOverdue).length;
    final paid = debts.where((debt) => debt.isPaid).length;
    final total = debts.length;
    return Column(
      children: [
        for (final entry in [
          ('Open', open, leaf),
          ('Overdue', overdue, const Color(0xFFC2544A)),
          ('Paid', paid, const Color(0xFF4E7890)),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    entry.$1,
                    style: const TextStyle(color: Color(0xFF687870)),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : entry.$2 / total,
                      minHeight: 8,
                      backgroundColor: canvas,
                      color: entry.$3,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${entry.$2}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({
    required this.debt,
    required this.currency,
    required this.onPayment,
    required this.onFollowUp,
    required this.onReminder,
  });
  final DebtRecord debt;
  final String Function(double) currency;
  final VoidCallback? onPayment;
  final VoidCallback? onFollowUp;
  final VoidCallback? onReminder;

  @override
  Widget build(BuildContext context) {
    final color = debt.isPaid
        ? const Color(0xFF4E7890)
        : debt.isOverdue
        ? const Color(0xFFC2544A)
        : debt.amountPaid > 0
        ? const Color(0xFFAE7B34)
        : leaf;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 660;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  debt.customerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  debt.itemDescription,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF687870)),
                ),
                const SizedBox(height: 5),
                Text(
                  'Due ${_date(debt.dueDate)}${debt.isOverdue ? ' · ${debt.daysOverdue} days late' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: debt.isOverdue ? color : const Color(0xFF687870),
                  ),
                ),
              ],
            );
            final amount = Column(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text(
                  currency(debt.balance),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'of ${currency(debt.totalAmount)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF687870),
                  ),
                ),
                const SizedBox(height: 4),
                _StatusLabel(text: debt.status, color: color),
              ],
            );
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onReminder != null)
                  IconButton(
                    tooltip: 'Send reminder',
                    onPressed: onReminder,
                    icon: const Icon(Icons.notifications_active_outlined),
                  ),
                if (onFollowUp != null)
                  IconButton(
                    tooltip: 'Record follow-up',
                    onPressed: onFollowUp,
                    icon: const Icon(Icons.forum_outlined),
                  ),
                if (onPayment != null)
                  IconButton(
                    tooltip: 'Record payment',
                    onPressed: onPayment,
                    icon: const Icon(Icons.add_card_outlined),
                  ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 10),
                      amount,
                    ],
                  ),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 5, child: details),
                Expanded(flex: 2, child: amount),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompactDebtLine extends StatelessWidget {
  const _CompactDebtLine({required this.debt, required this.onTap});
  final DebtRecord debt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      debt.customerName,
      style: const TextStyle(fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '${debt.itemDescription} · ${debt.daysOverdue} days overdue',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Text(
      _money(debt.balance),
      style: const TextStyle(
        color: Color(0xFFC2544A),
        fontWeight: FontWeight.w700,
      ),
    ),
    onTap: onTap,
  );
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({
    required this.customer,
    required this.debts,
    required this.onEdit,
    required this.onDebt,
    required this.currency,
  });
  final CustomerRecord customer;
  final List<DebtRecord> debts;
  final VoidCallback onEdit;
  final VoidCallback onDebt;
  final String Function(double) currency;

  @override
  Widget build(BuildContext context) {
    final balance = debts.fold<double>(
      0,
      (total, debt) => total + debt.balance,
    );
    final risk = riskCategory(debts);
    final riskColor = risk == 'High'
        ? const Color(0xFFC2544A)
        : risk == 'Moderate'
        ? const Color(0xFFAE7B34)
        : leaf;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            return Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFE5F0EB),
                  foregroundColor: leaf,
                  child: Text(
                    customer.name.isEmpty
                        ? '?'
                        : customer.name.substring(0, 1).toUpperCase(),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          customer.phone,
                          customer.email,
                        ].where((entry) => entry.isNotEmpty).join(' · '),
                        maxLines: compact ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF687870),
                        ),
                      ),
                      if (compact) ...[
                        const SizedBox(height: 8),
                        _StatusLabel(
                          text: '$risk repayment risk',
                          color: riskColor,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${debts.length} accounts · ${currency(balance)} due',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF687870),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!compact) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        currency(balance),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      Text(
                        '${debts.length} accounts',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF687870),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 18),
                  _StatusLabel(text: '$risk risk', color: riskColor),
                ],
                IconButton(
                  tooltip: 'Record credit',
                  onPressed: onDebt,
                  icon: const Icon(Icons.add_card_outlined),
                ),
                IconButton(
                  tooltip: 'Edit customer',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
    ),
  );
}

class _FollowUpTile extends StatelessWidget {
  const _FollowUpTile({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final promised = data['promisedDate'] == null
        ? null
        : dateValue(data['promisedDate']);
    final next = data['nextFollowUpAt'] == null
        ? null
        : dateValue(data['nextFollowUpAt']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.forum_outlined, color: leaf),
        title: Text(
          '${data['customerName'] ?? 'Customer'} · ${data['outcome'] ?? 'Follow-up'}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            data['notes'],
            if (promised != null) 'Promise ${_date(promised)}',
            if (next != null) 'Next ${_date(next)}',
          ].whereType<String>().where((item) => item.isNotEmpty).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: data['promisedAmount'] == null
            ? null
            : Text(
                _money(numberValue(data['promisedAmount'])),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}

class _ReminderQueue extends StatelessWidget {
  const _ReminderQueue({required this.service, required this.businessId});
  final FirestoreService service;
  final String businessId;

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.watchReminders(businessId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _InlineError(message: snapshot.error.toString());
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final docs = snapshot.data!.docs.toList()
            ..sort(
              (a, b) =>
                  dateValue(b.data()['createdAt'])
                      .compareTo(dateValue(a.data()['createdAt'])),
            );
          if (docs.isEmpty) {
            return const _InlineEmpty(
              message: 'No payment reminders have been generated.',
            );
          }
          return Column(
            children: [
              for (final doc in docs.take(20))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      doc.data()['status'] == 'composed'
                          ? Icons.outgoing_mail
                          : Icons.notifications_none,
                      color: leaf,
                    ),
                    title: Text(
                      doc.data()['customerName'] as String? ?? 'Customer',
                    ),
                    subtitle: Text(
                      doc.data()['message'] as String? ?? 'Payment reminder',
                    ),
                    trailing: _StatusLabel(
                      text: doc.data()['status'] as String? ?? 'ready',
                      color: doc.data()['status'] == 'composed'
                          ? leaf
                          : const Color(0xFFAE7B34),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

Widget _paymentRows(List<PaymentRecord> payments) {
  if (payments.isEmpty) {
    return const _EmptyState(
      icon: Icons.payments_outlined,
      title: 'No payments recorded',
      message:
          'Payment history will appear when a business records a repayment.',
    );
  }
  return Column(
    children: [
      for (final payment in payments.take(80))
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE6F0EB),
              foregroundColor: leaf,
              child: Icon(Icons.south_west, size: 19),
            ),
            title: Text(
              payment.customerName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${_date(payment.date)} · ${payment.method}${payment.reference.isEmpty ? '' : ' · ${payment.reference}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              _money(payment.amount),
              style: const TextStyle(fontWeight: FontWeight.w700, color: leaf),
            ),
          ),
        ),
    ],
  );
}

class _StaffForm extends StatefulWidget {
  const _StaffForm({required this.service, required this.owner});
  final FirestoreService service;
  final BusinessUser owner;

  @override
  State<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends State<_StaffForm> {
  final _formKey = GlobalKey<FormState>();
  final _uid = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _uid.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.service.addStaff(
        owner: widget.owner,
        uid: _uid.text,
        name: _name.text,
        email: _email.text,
      );
      if (mounted) _notice(context, 'Staff account linked to this business.');
      _uid.clear();
      _name.clear();
      _email.clear();
    } catch (error) {
      if (mounted) _notice(context, error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'The staff member must register first. Find their UID in Firebase Authentication.',
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _uid,
          decoration: const InputDecoration(labelText: 'Firebase user UID'),
          validator: _required,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth > 540
              ? Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                        ),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(
                          labelText: 'Email (optional)',
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email (optional)',
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.person_add_alt_1),
            label: Text(_saving ? 'Linking...' : 'Add staff'),
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF789188), size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: Color(0xFF687870))),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _NotificationInbox extends StatefulWidget {
  const _NotificationInbox({required this.service, required this.uid});

  final FirestoreService service;
  final String uid;

  @override
  State<_NotificationInbox> createState() => _NotificationInboxState();
}

class _NotificationInboxState extends State<_NotificationInbox> {
  bool _enablingPush = false;
  String? _pushStatus;

  Future<void> _enablePush() async {
    setState(() => _enablingPush = true);
    try {
      final status = await PushNotifications.enableForUser(
        service: widget.service,
        uid: widget.uid,
      );
      if (mounted) setState(() => _pushStatus = status);
    } catch (error) {
      if (mounted) setState(() => _pushStatus = error.toString());
    } finally {
      if (mounted) setState(() => _enablingPush = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.75,
    child: SafeArea(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: widget.service.watchNotifications(widget.uid),
        builder: (context, snapshot) {
          final docs =
              snapshot.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final unread = docs.where((doc) => doc.data()['readAt'] == null);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Notifications',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(color: ink, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (unread.isNotEmpty)
                      TextButton(
                        onPressed: () => widget.service
                            .markAllNotificationsRead(widget.uid, docs),
                        child: const Text('Mark all read'),
                      ),
                    IconButton(
                      tooltip: 'Enable browser notifications',
                      onPressed: _enablingPush ? null : _enablePush,
                      icon: _enablingPush
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.notifications_active_outlined),
                    ),
                  ],
                ),
              ),
              if (_pushStatus != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _pushStatus!,
                      style: const TextStyle(color: Color(0xFF687870)),
                    ),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: snapshot.hasError
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_notificationLoadError(snapshot.error!)),
                        ),
                      )
                    : !snapshot.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : docs.isEmpty
                    ? const Center(
                        child: Text(
                          'You\'re all caught up.',
                          style: TextStyle(color: Color(0xFF687870)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1, indent: 72),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final isUnread = data['readAt'] == null;
                          final createdAt = data['createdAt'];
                          final createdLabel = createdAt is Timestamp
                              ? DateFormat('d MMM, h:mm a')
                                    .format(createdAt.toDate())
                              : '';
                          return ListTile(
                            leading: Icon(
                              data['type'] == 'payment'
                                  ? Icons.payments_outlined
                                  : data['type'] == 'account'
                                  ? Icons.person_outline
                                  : Icons.notifications_active_outlined,
                              color: isUnread ? leaf : const Color(0xFF82918A),
                            ),
                            title: Text(
                              data['title'] as String? ?? 'Notification',
                              style: TextStyle(
                                fontWeight: isUnread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              [
                                data['message'] as String? ?? '',
                                createdLabel,
                              ].where((part) => part.isNotEmpty).join('\n'),
                            ),
                            isThreeLine: true,
                            trailing: isUnread
                                ? const Icon(Icons.circle, size: 9, color: leaf)
                                : null,
                            onTap: isUnread
                                ? () => widget.service.markNotificationRead(
                                    widget.uid,
                                    doc.id,
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

String _notificationLoadError(Object error) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'Firestore blocked access to notifications. Deploy the latest security rules for this project with:\n\nfirebase deploy --only firestore:rules --project dabtmateapp';
  }
  return error.toString();
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: leaf, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF687870)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 34,
                color: Color(0xFFC2544A),
              ),
              const SizedBox(height: 12),
              const Text(
                'Could not load your records',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF687870)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _notice(BuildContext context, String message, {bool error = false}) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFFB5433C) : ink,
      ),
    );

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;
String? _positiveNumber(String? value) {
  final parsed = double.tryParse(value ?? '');
  return parsed == null || parsed <= 0
      ? 'Enter a number greater than zero'
      : null;
}

String? _nonNegativeNumber(String? value) {
  final parsed = double.tryParse(value ?? '');
  return parsed == null || parsed < 0
      ? 'Enter zero or a positive number'
      : null;
}
