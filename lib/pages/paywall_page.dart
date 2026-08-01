import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/subscription_service.dart';
import 'plus_unlocked_page.dart';

const _kNavy = Color(0xFF12213F);
const _kGreen = Color(0xFFC9FF5C);

/// Pantalla de planes ("paywall"). Se abre cuando el usuario intenta usar
/// una función que requiere Pedalea Plus, o desde el perfil/menú.
class PaywallPage extends StatefulWidget {
  final String? reason; // texto opcional: por qué llegó aquí
  const PaywallPage({super.key, this.reason});

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  final _service = SubscriptionService.instance;
  bool _buying = false;
  String _selectedProductId = SubscriptionProductIds.yearly;

  @override
  void initState() {
    super.initState();
    _service.isPlus.addListener(_onPlusChanged);
  }

  @override
  void dispose() {
    _service.isPlus.removeListener(_onPlusChanged);
    super.dispose();
  }

  void _onPlusChanged() {
    if (!mounted || !_service.isPlus.value) return;
    // La compra se confirmó mientras esta pantalla estaba abierta:
    // muestra el tutorial de "lo que desbloqueaste" y cierra el paywall.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const PlusUnlockedPage()),
    );
  }

  Future<void> _buy(ProductDetails product) async {
    setState(() => _buying = true);
    try {
      await _service.buy(product);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar la compra: $e',
                style: TextStyle(fontFamily: 'Poppins', )),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  /// Fallback mientras no haya productos reales de Play Console: activa
  /// Plus en modo simulado, para poder seguir probando/desarrollando.
  Future<void> _buyFallback() async {
    setState(() => _buying = true);
    try {
      await _service.setSimulatedPlus(true, productId: _selectedProductId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Aún no hay productos configurados en Play Console: se activó Plus en modo simulado.',
              style: TextStyle(fontFamily: 'Poppins', ),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _service.products;
    ProductDetails? findProduct(String id) {
      for (final p in products) {
        if (p.id == id) return p;
      }
      return null;
    }

    final hasRealProducts = products.isNotEmpty;
    final monthly = findProduct(SubscriptionProductIds.monthly);
    final yearly = findProduct(SubscriptionProductIds.yearly);
    final selected = _selectedProductId == SubscriptionProductIds.yearly ? yearly : monthly;

    return Scaffold(
      backgroundColor: _kNavy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _service.restorePurchases();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Buscando compras anteriores...',
                        style: TextStyle(fontFamily: 'Poppins', )),
                  ),
                );
              }
            },
            child: Text(
              'Restaurar',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white.withOpacity(0.5)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kGreen.withOpacity(0.12),
                    border: Border.all(color: _kGreen.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded,
                      color: _kGreen, size: 36),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Pedalea Plus',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white,
                  fontSize: 26, fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.reason ?? 'Dale un plus a tu pedalear',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white.withOpacity(0.5),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 28),
              ..._benefits.map(_benefitRow),
              const SizedBox(height: 28),
              _planCard(
                title: yearly?.title.replaceAll(RegExp(r'\(.*\)'), '').trim() ?? 'Plan anual',
                price: yearly?.price ?? '\$39.990 CLP/año',
                badge: 'Ahorra ~33%',
                isSelected: _selectedProductId == SubscriptionProductIds.yearly,
                onTap: () => setState(
                    () => _selectedProductId = SubscriptionProductIds.yearly),
              ),
              const SizedBox(height: 12),
              _planCard(
                title: monthly?.title.replaceAll(RegExp(r'\(.*\)'), '').trim() ?? 'Plan mensual',
                price: monthly?.price ?? '\$4.990 CLP/mes',
                badge: null,
                isSelected: _selectedProductId == SubscriptionProductIds.monthly,
                onTap: () => setState(
                    () => _selectedProductId = SubscriptionProductIds.monthly),
              ),
              if (!hasRealProducts) ...[
                const SizedBox(height: 10),
                Text(
                  'Precios de referencia — aún no hay productos configurados en Play Console.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Poppins', color: Colors.orange.withOpacity(0.8),
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _buying
                      ? null
                      : (hasRealProducts
                          ? (selected == null ? null : () => _buy(selected))
                          : _buyFallback),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: _buying
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2),
                        )
                      : const Text('Suscribirme'),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Puedes cancelar cuando quieras desde Google Play.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white.withOpacity(0.3),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  static const _benefits = [
    ('📸', 'Comparte tus viajes y estadísticas en historias'),
    ('📊', 'Estadísticas avanzadas e histórico completo'),
    ('🗺️', 'Rutas multiparada ilimitadas'),
    ('🎉', 'Eventos ilimitados (gratis: hasta 2)'),
    ('🔒', 'Crea y únete a eventos privados con contraseña'),
    ('🚫', 'Sin publicidad'),
    ('🏅', 'Insignia distintiva en tu perfil y en el chat'),
    ('📡', 'Mapas offline (próximamente)'),
  ];

  Widget _benefitRow((String, String) item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(item.$1, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.$2,
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard({
    required String title,
    required String price,
    required String? badge,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? _kGreen.withOpacity(0.1) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _kGreen : Colors.white.withOpacity(0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? _kGreen : Colors.white38,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontFamily: 'Poppins', color: Colors.white,
                      fontSize: 15, fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      badge,
                      style: TextStyle(fontFamily: 'Poppins', color: _kGreen,
                        fontSize: 12, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              price,
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
