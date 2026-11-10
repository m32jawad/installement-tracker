import 'package:flutter/material.dart';

import 'collect_payment.dart';
import 'customers.dart';
import 'dashboard.dart';
import 'items.dart';
import 'payments.dart';
import 'reports.dart';
import 'sales.dart';

/// Bottom tabs: Home, Customers, Sales, Payments, Reports + quick-action button.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _pages = [
    DashboardScreen(),
    CustomersScreen(),
    SalesScreen(),
    PaymentsScreen(),
    ReportsScreen(),
  ];

  Future<void> _quickActions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget tile(String key, IconData icon, String label, String sub) => ListTile(
              leading: CircleAvatar(child: Icon(icon)),
              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
              subtitle: Text(sub),
              onTap: () => Navigator.pop(ctx, key),
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            tile('sale', Icons.add_shopping_cart, 'New Sale', 'Customer + item + installment plan'),
            tile('collect', Icons.payments_outlined, 'Collect Payment', 'Record an installment received'),
            tile('customer', Icons.person_add_alt_1, 'Add Customer', 'Name, phone, CNIC, guarantor'),
            tile('item', Icons.phone_android, 'Add Item', 'Phone / product with IMEI and photos'),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'sale':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const NewSaleWizard()));
      case 'collect':
        await collectPaymentFlow(context);
      case 'customer':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerForm()));
      case 'item':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const ItemForm()));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: _pages),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'quick',
          onPressed: _quickActions,
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Customers'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Sales'),
            NavigationDestination(
                icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Payments'),
            NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Reports'),
          ],
        ),
      );
}
