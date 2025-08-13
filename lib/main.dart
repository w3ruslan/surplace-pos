import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:esc_pos_printer/esc_pos_printer.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils.dart' as esc;

/* =======================
   Sabitler
   ======================= */
const String _ADMIN_PIN = '6538';
const String _kSavedPrinterIp = 'printer_ip';
const int _kDefaultPosPort = 9100;

/* =======================
   ENTRY
   ======================= */
void main() {
  final appState = AppState();
  runApp(AppScope(notifier: appState, child: const App()));
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Commande Sur Place',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const Home(),
    );
  }
}

/* =======================
   MODELLER & STATE
   ======================= */
class Product {
  String name;
  final List<OptionGroup> groups;
  Product({required this.name, List<OptionGroup>? groups})
      : groups = groups ?? [];
  double priceForSelection(Map<String, List<OptionItem>> picked) {
    double total = 0;
    for (final g in groups) {
      final list = picked[g.id] ?? const [];
      for (final it in list) total += it.price;
    }
    return total;
  }
}

class OptionGroup {
  final String id;
  String title;
  bool multiple; // false=tek, true=çoklu
  int minSelect;
  int maxSelect;
  final List<OptionItem> items;
  OptionGroup({
    required this.id,
    required this.title,
    required this.multiple,
    required this.minSelect,
    required this.maxSelect,
    List<OptionItem>? items,
  }) : items = items ?? [];
}

class OptionItem {
  final String id;
  String label;
  double price;
  OptionItem({required this.id, required this.label, required this.price});
}

class CartLine {
  final Product product;
  final Map<String, List<OptionItem>> picked; // deep copy saklı
  CartLine({required this.product, required this.picked});
  double get total => product.priceForSelection(picked);
}

class SavedOrder {
  final String id;
  final DateTime createdAt;
  final List<CartLine> lines;
  final String customer; // müşteri adı
  SavedOrder({
    required this.id,
    required this.createdAt,
    required this.lines,
    required this.customer,
  });
  double get total => lines.fold(0.0, (s, l) => s + l.total);
}

class AppState extends ChangeNotifier {
  final List<Product> products = [];
  final List<CartLine> cart = [];
  final List<SavedOrder> orders = [];

  void addProduct(Product p) { products.add(p); notifyListeners(); }
  void replaceProductAt(int i, Product p) { products[i] = p; notifyListeners(); }

  void addLineToCart(Product p, Map<String, List<OptionItem>> picked) {
    final deep = { for (final e in picked.entries) e.key: List<OptionItem>.from(e.value) };
    cart.add(CartLine(product: p, picked: deep));
    notifyListeners();
  }
  void removeCartLineAt(int i) { if (i>=0 && i<cart.length) { cart.removeAt(i); notifyListeners(); } }
  void clearCart() { cart.clear(); notifyListeners(); }

  void finalizeCartToOrder({required String customer}) {
    if (cart.isEmpty) return;
    final deepLines = cart.map((l) => CartLine(
      product: l.product,
      picked: { for (final e in l.picked.entries) e.key: List<OptionItem>.from(e.value) },
    )).toList();
    orders.add(SavedOrder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      lines: deepLines,
      customer: customer,
    ));
    cart.clear();
    notifyListeners();
  }
  void clearOrders() { orders.clear(); notifyListeners(); }
}

/* InheritedNotifier: global state erişimi */
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({required AppState notifier, required Widget child, Key? key})
      : super(key: key, notifier: notifier, child: child);
  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope bulunamadı.');
    return scope!.notifier!;
  }
}

/* =======================
   HOME (4 sekme)
   ======================= */
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool _seeded = false;
  int index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;

    final app = AppScope.of(context);
    if (app.products.isEmpty) {
      final sandwich = Product(name: 'Sandwich');
      sandwich.groups.addAll([
        OptionGroup(
          id: 'pain', title: 'Pain', multiple: false, minSelect: 1, maxSelect: 1,
          items: [ OptionItem(id: 'galette', label: 'Galette', price: 0),
                   OptionItem(id: 'pita', label: 'Pain pita', price: 0), ],
        ),
        OptionGroup(
          id: 'viande', title: 'Viande', multiple: false, minSelect: 1, maxSelect: 1,
          items: [ OptionItem(id: 'kebab', label: 'Kebab', price: 0),
                   OptionItem(id: 'steak', label: 'Steak', price: 0),
                   OptionItem(id: 'poulet', label: 'Poulet', price: 0),
                   OptionItem(id: 'legumes', label: 'Légumes grillés', price: 0), ],
        ),
        OptionGroup(
          id: 'supp', title: 'Suppléments (max 3)', multiple: true, minSelect: 0, maxSelect: 3,
          items: [
            OptionItem(id: 'oeuf', label: 'Œuf', price: 1.00),
            OptionItem(id: 'cheddar', label: 'Cheddar', price: 1.00),
            OptionItem(id: 'double_cheddar', label: 'Double cheddar', price: 1.80),
            OptionItem(id: 'bacon', label: 'Bacon', price: 1.50),
            OptionItem(id: 'cornichon', label: 'Cornichons', price: 0.50),
            OptionItem(id: 'oignon', label: 'Oignons', price: 0.50),
            OptionItem(id: 'salade', label: 'Salade', price: 0.30),
          ],
        ),
        OptionGroup(
          id: 'sauces', title: 'Sauces (max 2)', multiple: true, minSelect: 0, maxSelect: 2,
          items: [
            OptionItem(id: 'algerienne', label: 'Algérienne', price: 0),
            OptionItem(id: 'blanche', label: 'Blanche', price: 0),
            OptionItem(id: 'ketchup', label: 'Ketchup', price: 0),
            OptionItem(id: 'mayo', label: 'Mayonnaise', price: 0),
            OptionItem(id: 'harissa', label: 'Harissa', price: 0),
            OptionItem(id: 'bbq', label: 'Barbecue', price: 0),
            OptionItem(id: 'andalouse', label: 'Andalouse', price: 0),
          ],
        ),
        OptionGroup(
          id: 'accompagnement', title: 'Accompagnement', multiple: false, minSelect: 1, maxSelect: 1,
          items: [ OptionItem(id: 'frites', label: 'Avec frites', price: 2.50),
                   OptionItem(id: 'sans_frites', label: 'Sans frites', price: 0), ],
        ),
        OptionGroup(
          id: 'boisson', title: 'Boisson', multiple: false, minSelect: 1, maxSelect: 1,
          items: [ OptionItem(id: 'avec_boisson', label: 'Avec boisson', price: 2.00),
                   OptionItem(id: 'sans_boisson', label: 'Sans boisson', price: 0), ],
        ),
      ]);
      app.addProduct(sandwich);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final totalCart = app.cart.fold(0.0, (s, l) => s + l.total);
    final cartBadge = app.cart.length;

    final pages = [
      const ProductsPage(),
      CreateProductPage(onGoToTab: (i) => setState(() => index = i)),
      const CartPage(),
      const OrdersPage(),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Commande Sur Place')),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Produits'),
          const NavigationDestination(icon: Icon(Icons.add_box_outlined), label: 'Créer'),
          NavigationDestination(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.shopping_bag_outlined),
                if (cartBadge > 0)
                  Positioned(
                    right: -6, top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                      child: Text('$cartBadge', style: const TextStyle(fontSize: 10, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            label: 'Panier (€${totalCart.toStringAsFixed(2)})',
          ),
          const NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Commandes'),
        ],
        onDestinationSelected: (i) async {
          if (i == 1) { final ok = await _askPin(context); if (!ok) return; }
          setState(() => index = i);
        },
      ),
    );
  }
}

/* =======================
   PAGE 1 : PRODUITS
   ======================= */
class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final products = app.products;

    if (products.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.info_outline, size: 48),
          SizedBox(height: 8),
          Text('Aucun produit. Allez à "Créer" pour en ajouter.'),
        ]),
      );
    }

    final width = MediaQuery.of(context).size.width;
    int cross = 2; if (width > 600) cross = 3; if (width > 900) cross = 4;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) => _ProductCard(product: products[i]),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;

    Future<void> openWizard() async {
      final added = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => OrderWizard(product: product)),
      );
      if (added == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ajouté au panier.')));
      }
    }

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: openWizard,
      child: Ink(
        decoration: BoxDecoration(color: color.surfaceVariant, borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              height: 56, width: 56,
              decoration: BoxDecoration(color: color.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.fastfood_rounded, color: color.primary, size: 32),
            ),
            const SizedBox(height: 16),
            Text(product.name, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('${product.groups.length} groupe(s)', style: TextStyle(color: color.onSurfaceVariant)),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                choisirButton(() => openWizard(), context),
                IconButton(
                  tooltip: 'Modifier',
                  onPressed: () async {
                    final ok = await _askPin(context);
                    if (!ok) return;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => CreateProductPage(
                        onGoToTab: (_) {},
                        editIndex: _findProductIndex(context, product),
                      ),
                    ));
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  int _findProductIndex(BuildContext context, Product p) => AppScope.of(context).products.indexOf(p);
}

/* =======================
   PAGE 2 : CRÉER + DÜZENLE (kısa versiyon)
   ======================= */
class CreateProductPage extends StatefulWidget {
  final void Function(int) onGoToTab;
  final int? editIndex;
  const CreateProductPage({super.key, required this.onGoToTab, this.editIndex});
  @override
  State<CreateProductPage> createState() => _CreateProductPageState();
}

class _CreateProductPageState extends State<CreateProductPage> {
  final TextEditingController nameCtrl = TextEditingController(text: 'Sandwich');
  final List<OptionGroup> editingGroups = [];
  int? editingIndex;

  @override
  void initState() {
    super.initState();
    editingIndex = widget.editIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (editingIndex != null) _loadForEdit(editingIndex!);
    });
  }

  void _loadForEdit(int idx) {
    final app = AppScope.of(context);
    if (idx < 0 || idx >= app.products.length) return;
    final p = app.products[idx];
    nameCtrl.text = p.name;
    editingGroups..clear()..addAll(p.groups.map(_copyGroup));
    setState(() => editingIndex = idx);
  }

  OptionGroup _copyGroup(OptionGroup g) => OptionGroup(
    id: g.id, title: g.title, multiple: g.multiple, minSelect: g.minSelect, maxSelect: g.maxSelect,
    items: g.items.map((e) => OptionItem(id: e.id, label: e.label, price: e.price)).toList(),
  );

  void addGroup() {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    editingGroups.add(OptionGroup(id: id, title: 'Nouveau groupe', multiple: false, minSelect: 1, maxSelect: 1));
    setState(() {});
  }

  void saveProduct() {
    final app = AppScope.of(context);
    if (nameCtrl.text.trim().isEmpty) { _snack(context, 'Nom du produit requis.'); return; }
    for (final g in editingGroups) {
      if (g.title.trim().isEmpty) { _snack(context, 'Titre du groupe manquant.'); return; }
      if (g.items.isEmpty) { _snack(context, 'Ajoutez au moins une option dans "${g.title}".'); return; }
      if (g.minSelect < 0 || g.maxSelect < 1 || g.minSelect > g.maxSelect) {
        _snack(context, 'Règles min/max invalides dans "${g.title}".'); return;
      }
      if (!g.multiple && (g.minSelect != 1 || g.maxSelect != 1)) {
        _snack(context, 'Choix unique doit avoir min=1 et max=1 (${g.title}).'); return;
      }
    }
    final p = Product(name: nameCtrl.text.trim(), groups: List.of(editingGroups));
    if (editingIndex == null) { app.addProduct(p); _snack(context, 'Produit créé.'); }
    else { app.replaceProductAt(editingIndex!, p); _snack(context, 'Produit mis à jour.'); }
    nameCtrl.text = ''; editingGroups.clear(); setState(() => editingIndex = null);

    if (Navigator.of(context).canPop()) Navigator.of(context).pop(); else widget.onGoToTab(0);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop(); else widget.onGoToTab(0);
          }, tooltip: 'Retour'),
          const SizedBox(width: 8),
          Text(editingIndex == null ? 'Créer un produit' : 'Modifier un produit',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              nameCtrl.text = ''; editingGroups.clear(); setState(() => editingIndex = null);
              if (Navigator.of(context).canPop()) Navigator.of(context).pop(); else widget.onGoToTab(0);
            },
            icon: const Icon(Icons.close), label: const Text('Annuler'),
          ),
        ]),
        const SizedBox(height: 12),

        if (app.products.isNotEmpty) ...[
          const Text('Produits existants', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: app.products.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = app.products[i];
              return ListTile(
                leading: const Icon(Icons.fastfood_rounded),
                title: Text(p.name),
                subtitle: Text('${p.groups.length} groupe(s)'),
                trailing: FilledButton.tonalIcon(
                  icon: const Icon(Icons.edit), label: const Text('Modifier'),
                  onPressed: () => _loadForEdit(i),
                ),
              );
            },
          ),
          const SizedBox(height: 16), const Divider(), const SizedBox(height: 12),
        ],

        TextField(controller: nameCtrl,
          decoration: const InputDecoration(labelText: 'Nom du produit', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton.icon(onPressed: addGroup, icon: const Icon(Icons.add), label: const Text('Ajouter un groupe')),
          const SizedBox(width: 12),
          OutlinedButton.icon(onPressed: saveProduct, icon: const Icon(Icons.save), label: const Text('Enregistrer')),
        ]),
        const SizedBox(height: 12),

        for (int i = 0; i < editingGroups.length; i++)
          _GroupEditor(
            key: ValueKey(editingGroups[i].id),
            group: editingGroups[i],
            onDelete: () => setState(() => editingGroups.removeAt(i)),
            onChanged: () => setState(() {}),
          ),

        if (editingGroups.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Text('Aucun groupe. Ajoutez "Pain", "Viande", "Suppléments", "Sauces", etc.'),
          ),
      ],
    );
  }
}

class _GroupEditor extends StatefulWidget {
  final OptionGroup group;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  const _GroupEditor({super.key, required this.group, required this.onDelete, required this.onChanged});
  @override
  State<_GroupEditor> createState() => _GroupEditorState();
}

class _GroupEditorState extends State<_GroupEditor> {
  final TextEditingController titleCtrl = TextEditingController();
  final TextEditingController minCtrl = TextEditingController();
  final TextEditingController maxCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    titleCtrl.text = widget.group.title;
    minCtrl.text = widget.group.minSelect.toString();
    maxCtrl.text = widget.group.maxSelect.toString();
  }

  void apply() {
    widget.group.title = titleCtrl.text.trim();
    widget.group.multiple = _mode == 1;
    widget.group.minSelect = int.tryParse(minCtrl.text) ?? 0;
    widget.group.maxSelect = int.tryParse(maxCtrl.text) ?? 1;
    widget.onChanged();
  }

  int get _mode => widget.group.multiple ? 1 : 0;
  set _mode(int v) { if (v == 0) { minCtrl.text = '1'; maxCtrl.text = '1'; } apply(); setState(() {}); }

  void addOption() {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    widget.group.items.add(OptionItem(id: id, label: 'Nouvelle option', price: 0));
    widget.onChanged(); setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Titre du groupe', border: OutlineInputBorder()),
                onChanged: (_) => apply(),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _mode,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Choix unique')),
                DropdownMenuItem(value: 1, child: Text('Choix multiple')),
              ],
              onChanged: (v) { if (v != null) _mode = v; },
            ),
            const SizedBox(width: 8),
            IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: minCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sélection min', border: OutlineInputBorder()),
                onChanged: (_) => apply(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: maxCtrl, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sélection max', border: OutlineInputBorder()),
                onChanged: (_) => apply(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: addOption, icon: const Icon(Icons.add), label: const Text('Ajouter une option')),
          ]),
          const SizedBox(height: 8),
          for (int i = 0; i < g.items.length; i++)
            _OptionEditor(
              key: ValueKey(g.items[i].id),
              item: g.items[i],
              onDelete: () { g.items.removeAt(i); widget.onChanged(); setState(() {}); },
              onChanged: () { widget.onChanged(); setState(() {}); },
            ),
        ]),
      ),
    );
  }
}

class _OptionEditor extends StatefulWidget {
  final OptionItem item;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  const _OptionEditor({super.key, required this.item, required this.onDelete, required this.onChanged});
  @override
  State<_OptionEditor> createState() => _OptionEditorState();
}

class _OptionEditorState extends State<_OptionEditor> {
  final TextEditingController labelCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  @override
  void initState() {
    super.initState();
    labelCtrl.text = widget.item.label;
    priceCtrl.text = widget.item.price.toStringAsFixed(2);
  }
  void apply() {
    widget.item.label = labelCtrl.text.trim();
    widget.item.price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
    widget.onChanged();
  }
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0),
      title: Row(children: [
        Expanded(
          child: TextField(
            controller: labelCtrl,
            decoration: const InputDecoration(labelText: 'Nom de l’option', border: OutlineInputBorder()),
            onChanged: (_) => apply(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: TextField(
            controller: priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Prix (€)', border: OutlineInputBorder()),
            onChanged: (_) => apply(),
          ),
        ),
        IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline)),
      ]),
    );
  }
}

/* =======================
   WIZARD (BUTONLAR İÇERİKTE, BİRAZ DAHA YUKARIDA)
   ======================= */
class OrderWizard extends StatefulWidget {
  final Product product;
  const OrderWizard({super.key, required this.product});
  @override
  State<OrderWizard> createState() => _OrderWizardState();
}

class _OrderWizardState extends State<OrderWizard> {
  int step = 0;
  final Map<String, List<OptionItem>> picked = {};

  void _toggleSingle(OptionGroup g, OptionItem it) { picked[g.id] = [it]; setState(() {}); }
  void _toggleMulti(OptionGroup g, OptionItem it) {
    final list = picked[g.id] ?? [];
    final exists = list.any((e) => e.id == it.id);
    if (exists) { list.removeWhere((e) => e.id == it.id); }
    else { if (list.length >= g.maxSelect) return; list.add(it); }
    picked[g.id] = list; setState(() {});
  }
  bool _validGroup(OptionGroup g) {
    final n = (picked[g.id] ?? const []).length;
    return n >= g.minSelect && n <= g.maxSelect;
  }

  @override
  Widget build(BuildContext context) {
    final groups = widget.product.groups;
    final isSummary = step >= groups.length;
    final total = widget.product.priceForSelection(picked);

    return Scaffold(
      appBar: AppBar(
        title: Text(isSummary ? 'Récapitulatif' : widget.product.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (isSummary) { setState(() => step = groups.isEmpty ? 0 : groups.length - 1); }
            else if (step > 0) { setState(() => step--); }
            else { Navigator.pop(context); }
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: isSummary
                ? _Summary(product: widget.product, picked: picked, total: total)
                : _GroupStep(group: groups[step], picked: picked, toggleSingle: _toggleSingle, toggleMulti: _toggleMulti),
          ),
          // Butonlar içerikte, SafeArea ile; alt çubuktan daha yukarı durur
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: step == 0 ? null : () => setState(() => step--),
                  child: const Text('Précédent'),
                )),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(
                  onPressed: () {
                    if (isSummary) {
                      final app = AppScope.of(context);
                      app.addLineToCart(widget.product, picked);
                      if (!mounted) return; Navigator.pop(context, true); return;
                    }
                    final g = groups[step];
                    if (!_validGroup(g)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Sélection invalide pour "${g.title}".')),
                      );
                      return;
                    }
                    setState(() => step++);
                  },
                  child: Text(isSummary ? 'Ajouter au panier' : 'Suivant'),
                )),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupStep extends StatelessWidget {
  final OptionGroup group;
  final Map<String, List<OptionItem>> picked;
  final void Function(OptionGroup, OptionItem) toggleSingle;
  final void Function(OptionGroup, OptionItem) toggleMulti;

  const _GroupStep({
    required this.group, required this.picked,
    required this.toggleSingle, required this.toggleMulti,
  });

  @override
  Widget build(BuildContext context) {
    final list = picked[group.id] ?? const [];
    final color = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: group.items.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              group.title + (group.multiple ? ' (min ${group.minSelect}, max ${group.maxSelect})' : ''),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          );
        }
        final it = group.items[i - 1];
        final selected = list.any((e) => e.id == it.id);

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => group.multiple ? toggleMulti(group, it) : toggleSingle(group, it),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? color.primaryContainer : color.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? color.primary : color.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    if (it.price != 0)
                      Text('+ €${it.price.toStringAsFixed(2)}', style: TextStyle(color: color.onSurfaceVariant)),
                  ]),
                ),
                group.multiple
                    ? Checkbox(value: selected, onChanged: (_) => toggleMulti(group, it))
                    : Radio<bool>(value: true, groupValue: selected, onChanged: (_) => toggleSingle(group, it)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  final Product product;
  final Map<String, List<OptionItem>> picked;
  final double total;
  const _Summary({required this.product, required this.picked, required this.total});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Récapitulatif — ${product.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        for (final g in product.groups)
          if ((picked[g.id] ?? const <OptionItem>[]).isNotEmpty) ...[
            Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (final it in (picked[g.id] ?? const <OptionItem>[]))
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('• ${it.label}'),
                Text(it.price == 0 ? '€0.00' : '€${it.price.toStringAsFixed(2)}'),
              ]),
            const SizedBox(height: 8),
            const Divider(),
          ],
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('SOUS-TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text('€${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }
}

/* =======================
   PAGE 3 : PANIER
   ======================= */
class CartPage extends StatelessWidget {
  const CartPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final lines = app.cart;
    final total = lines.fold(0.0, (s, l) => s + l.total);

    if (lines.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.shopping_bag_outlined, size: 48),
          SizedBox(height: 8),
          Text('Panier vide. Ajoutez des produits.'),
        ]),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            const Text('Panier', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => app.clearCart(),
              icon: const Icon(Icons.delete_sweep),
              label: const Text('Vider'),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: lines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final l = lines[i];
              return ListTile(
                leading: const Icon(Icons.fastfood),
                title: Text('${l.product.name} • €${l.total.toStringAsFixed(2)}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final g in l.product.groups)
                      if ((l.picked[g.id] ?? const <OptionItem>[]).isNotEmpty) ...[
                        Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        for (final it in (l.picked[g.id] ?? const <OptionItem>[]))
                          Text('• ${it.label}${it.price == 0 ? '' : ' (+€${it.price.toStringAsFixed(2)})'}'),
                      ],
                  ],
                ),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => app.removeCartLineAt(i)),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('€${total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: FilledButton.icon(
            onPressed: () async {
              final name = await _askCustomerName(context);
              if (name == null) return;
              AppScope.of(context).finalizeCartToOrder(customer: name);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Commande validée pour "$name".')),
                );
              }
            },
            icon: const Icon(Icons.check),
            label: const Text('Valider la commande'),
          ),
        ),
      ],
    );
  }
}

/* =======================
   PAGE 4 : COMMANDES + YAZDIRMA
   ======================= */
class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final orders = app.orders.reversed.toList();

    if (orders.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.receipt_long, size: 48),
          SizedBox(height: 8),
          Text('Aucune commande.'),
        ]),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            const Text('Commandes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                final newIp = await _pickPrinterIpDialog(context);
                if (newIp != null && newIp.isNotEmpty) {
                  await _savePrinterIp(newIp);
                  _snack(context, 'Kayıtlı yazıcı: $newIp');
                }
              },
              icon: const Icon(Icons.print),
              label: const Text('Yazıcıyı değiştir'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () async {
                final pinOk = await _askPin(context); if (!pinOk) return;
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Fin de journée ?'),
                    content: const Text('Toutes les commandes seront supprimées. Action irréversible.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
                    ],
                  ),
                );
                if (ok == true) app.clearOrders();
              },
              icon: const Icon(Icons.delete_forever),
              label: const Text('Journée terminée'),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final o = orders[i];
              final who = o.customer.isEmpty ? '' : ' — ${o.customer}';
              return ListTile(
                leading: const Icon(Icons.receipt),
                title: Text('Commande$who • ${o.lines.length} article(s) • €${o.total.toStringAsFixed(2)}'),
                subtitle: Text(
                  '${o.createdAt.hour.toString().padLeft(2, '0')}:${o.createdAt.minute.toString().padLeft(2, '0')} '
                  '${o.createdAt.day.toString().padLeft(2, '0')}/${o.createdAt.month.toString().padLeft(2, '0')}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.print_outlined),
                  onPressed: () => _printOrderWeb(context, o),
                  tooltip: 'Imprimer',
                ),
                onTap: () {
                  showDialog(context: context, builder: (_) {
                    return AlertDialog(
                      title: const Text('Détails de la commande'),
                      content: SizedBox(
                        width: 360,
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            if (o.customer.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('Client: ${o.customer}',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            for (int idx = 0; idx < o.lines.length; idx++) ...[
                              Text('Article ${idx+1}: ${o.lines[idx].product.name}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              for (final g in o.lines[idx].product.groups)
                                if ((o.lines[idx].picked[g.id] ?? const <OptionItem>[]).isNotEmpty) ...[
                                  Text(g.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  for (final it in (o.lines[idx].picked[g.id] ?? const <OptionItem>[]))
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('• ${it.label}'),
                                        Text(it.price == 0 ? '€0.00' : '€${it.price.toStringAsFixed(2)}'),
                                      ],
                                    ),
                                ],
                              const Divider(),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('€${o.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => _printOrderWeb(context, o), child: const Text('Imprimer')),
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
                      ],
                    );
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/* =======================
   AĞ YAZICISI: IP SEÇME / KAYDETME / YAZDIRMA
   ======================= */

Future<void> _savePrinterIp(String ip) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setString(_kSavedPrinterIp, ip);
}

Future<String?> _loadPrinterIp() async {
  final sp = await SharedPreferences.getInstance();
  return sp.getString(_kSavedPrinterIp);
}

Future<List<String>> _scanEscPosPrinters({int port = _kDefaultPosPort, Duration timeout = const Duration(milliseconds: 200)}) async {
  final info = NetworkInfo();
  final wifiIP = await info.getWifiIP(); // ör: 192.168.1.23
  if (wifiIP == null || !wifiIP.contains('.')) return [];
  final parts = wifiIP.split('.');
  final prefix = '${parts[0]}.${parts[1]}.${parts[2]}.';

  final found = <String>[];
  final futures = <Future>[];
  for (int i = 1; i <= 254; i++) {
    final host = '$prefix$i';
    futures.add(Socket.connect(host, port, timeout: timeout).then((s) {
      found.add(host);
      s.destroy();
    }).catchError((_) {}));
  }
  await Future.wait(futures, eagerError: false);
  return found..sort();
}

Future<String?> _pickPrinterIpDialog(BuildContext context) async {
  final ipsFuture = _scanEscPosPrinters();

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      String manual = '';
      return AlertDialog(
        title: const Text('Yazıcı Seç'),
        content: SizedBox(
          width: 360,
          child: FutureBuilder<List<String>>(
            future: ipsFuture,
            builder: (c, snap) {
              final ips = snap.data ?? [];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!snap.hasData)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 12),
                          Expanded(child: Text('Ağ taranıyor… (ESC/POS 9100)')),
                        ],
                      ),
                    ),
                  if (ips.isNotEmpty)
                    SizedBox(
                      height: 180,
                      child: ListView.separated(
                        itemCount: ips.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => ListTile(
                          leading: const Icon(Icons.print),
                          title: Text(ips[i]),
                          onTap: () => Navigator.pop(ctx, ips[i]),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text('Bulunamadıysa IP girin:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'örn. 192.168.1.100',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => manual = v.trim(),
                    onSubmitted: (_) => Navigator.pop(ctx, manual),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, manual), child: const Text('Kaydet')),
        ],
      );
    },
  );
}

Future<void> _printOrderWeb(BuildContext context, SavedOrder o) async {
  try {
    String? ip = await _loadPrinterIp();
    if (ip == null || ip.isEmpty) {
      ip = await _pickPrinterIpDialog(context);
      if (ip == null || ip.isEmpty) {
        _snack(context, 'Yazıcı seçilmedi.');
        return;
      }
      await _savePrinterIp(ip);
    }

    final profile = await esc.CapabilityProfile.load();
    final printer = NetworkPrinter(esc.PaperSize.mm80, profile);
    final res = await printer.connect(ip, port: _kDefaultPosPort);
    if (res != PosPrintResult.success) {
      _snack(context, 'Bağlantı hatası: $res');
      return;
    }

    printer.text('Commande Sur Place',
        styles: esc.PosStyles(
          align: esc.PosAlign.center,
          bold: true,
          height: esc.PosTextSize.size2,
          width: esc.PosTextSize.size2,
        ));
    printer.hr();

    final dt = o.createdAt;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');

    if (o.customer.isNotEmpty) {
      printer.text('Müşteri: ${o.customer}', styles: esc.PosStyles(bold: true));
    }
    printer.text('Saat: $hh:$mm   Tarih: $dd/$mo');
    printer.hr();

    for (int i = 0; i < o.lines.length; i++) {
      final line = o.lines[i];
      printer.text('${i + 1}. ${line.product.name}', styles: esc.PosStyles(bold: true));

      for (final g in line.product.groups) {
        final picks = line.picked[g.id] ?? const <OptionItem>[];
        if (picks.isEmpty) continue;
        printer.text(g.title, styles: esc.PosStyles(underline: true));
        for (final it in picks) {
          final price = it.price == 0 ? '' : '+€${it.price.toStringAsFixed(2)}';
          printer.row([
            esc.PosColumn(text: ' • ${it.label}', width: 10),
            esc.PosColumn(text: price, width: 2, styles: esc.PosStyles(align: esc.PosAlign.right)),
          ]);
        }
      }

      printer.row([
        esc.PosColumn(text: 'Ara toplam', width: 10),
        esc.PosColumn(
          text: '€${line.total.toStringAsFixed(2)}',
          width: 2,
          styles: esc.PosStyles(align: esc.PosAlign.right, bold: true),
        ),
      ]);
      printer.hr(ch: '-');
    }

    printer.row([
      esc.PosColumn(text: 'TOPLAM', width: 8, styles: esc.PosStyles(bold: true, height: esc.PosTextSize.size2)),
      esc.PosColumn(
        text: '€${o.total.toStringAsFixed(2)}',
        width: 4,
        styles: esc.PosStyles(
          align: esc.PosAlign.right,
          bold: true,
          height: esc.PosTextSize.size2,
          width: esc.PosTextSize.size2,
        ),
      ),
    ]);

    printer.hr();
    printer.text('Teşekkürler!', styles: esc.PosStyles(align: esc.PosAlign.center));
    printer.feed(2);
    printer.cut();
    printer.disconnect();

    _snack(context, 'Fiş yazdırıldı.');
  } catch (e) {
    _snack(context, 'Yazdırma hatası: $e');
  }
}

/* =======================
   DİYALOGLAR & UTIL
   ======================= */
Future<bool> _askPin(BuildContext context) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Code PIN requis'),
      content: TextField(
        controller: ctrl, keyboardType: TextInputType.number, obscureText: true, maxLength: 8,
        decoration: const InputDecoration(labelText: 'Entrez le code', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim() == _ADMIN_PIN), child: const Text('Valider')),
      ],
    ),
  );
  if (ok != true) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code incorrect.'))); }
  return ok == true;
}

Future<String?> _askCustomerName(BuildContext context) async {
  final ctrl = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('Nom du client'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl, autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Écrire le nom',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onSubmitted: (_) {
                  if (ctrl.text.trim().isEmpty) {
                    setState(() => error = 'Le nom est requis.');
                  } else {
                    Navigator.pop(ctx, ctrl.text.trim());
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) { setState(() => error = 'Le nom est requis.'); return; }
                Navigator.pop(ctx, name);
              },
              child: const Text('Valider'),
            ),
          ],
        );
      });
    },
  );
}

void _snack(BuildContext ctx, String msg) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
}

/* =======================
   Choisir butonu (kırılma yok)
   ======================= */
Widget choisirButton(VoidCallback onTap, BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  final isTiny = w < 360; // çok dar telefonlar

  if (isTiny) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.shopping_cart_outlined, size: 20),
      label: const SizedBox.shrink(),
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(56, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  return FilledButton.icon(
    onPressed: onTap,
    icon: const Icon(Icons.shopping_cart_outlined, size: 20),
    label: const Text(
      'Choisir',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.fade,
    ),
    style: FilledButton.styleFrom(
      shape: const StadiumBorder(),
      minimumSize: const Size(120, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
  );
}
