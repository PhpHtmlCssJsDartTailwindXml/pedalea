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
  final _service = SubscriptionService.instance; // suscripción Plus
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

  /// Mientras no haya productos reales en Play Console, este botón solo
  /// funciona para las cuentas del dueño de la app (Plus de prueba, validado
  /// en el servidor). Para cualquier otro usuario no hace nada: ya no existe
  /// el "Plus simulado" abierto.
  Future<void> _buyFallback() async {
    setState(() => _buying = true);
    try {
      final ok = await _service.grantTestPlus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Plus de prueba activado.'
                  : 'Los planes todavía no están disponibles. Vuelve pronto.',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: ok ? Colors.green : Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  /// Precio mensual equivalente del plan anual ("$1.666/mes"), para que la
  /// comparación con el mensual sea directa.
  String _perMonth(ProductDetails? yearly) {
    final raw = yearly?.rawPrice ?? 19990;
    final symbol = yearly?.currencySymbol ?? '\$';
    final v = (raw / 12).round();
    final txt = v.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    return '$symbol$txt/mes';
  }

  /// "AHORRA 33%" del anual frente a 12 meses del mensual.
  String _savingsBadge(ProductDetails? monthly, ProductDetails? yearly) {
    final m = monthly?.rawPrice ?? 1990;
    final y = yearly?.rawPrice ?? 19990;
    if (m <= 0) return 'MEJOR PRECIO';
    final pct = ((1 - y / (m * 12)) * 100).round();
    return pct > 0 ? 'AHORRA $pct%' : 'MEJOR PRECIO';
  }

  @override
  Widget build(BuildContext context) {
    final products = _service.products;
    final hasRealProducts = products.isNotEmpty;
    // Precio del plan base (no el $0 de una oferta de prueba).
    final monthly = _service.basePlan(SubscriptionProductIds.monthly);
    final yearly = _service.basePlan(SubscriptionProductIds.yearly);
    final monthlyTrial = _service.trialOffer(SubscriptionProductIds.monthly);
    final yearlyTrial = _service.trialOffer(SubscriptionProductIds.yearly);
    final isYearly = _selectedProductId == SubscriptionProductIds.yearly;
    final base = isYearly ? yearly : monthly;
    final trial = isYearly ? yearlyTrial : monthlyTrial;
    final trialDays = trial == null ? null : SubscriptionService.trialDays(trial);
    // Si Play ofrece prueba gratis a este usuario, se compra esa oferta.
    final selected = trial ?? base;
    String trialNote(ProductDetails? t) {
      final d = t == null ? null : SubscriptionService.trialDays(t);
      return d == null ? '' : ' · $d días gratis';
    }

    return Scaffold(
      backgroundColor: _kNavy,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Barra superior
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await _service.restorePurchases();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Buscando compras anteriores...',
                                style: TextStyle(fontFamily: 'Poppins')),
                          ),
                        );
                      }
                    },
                    child: Text(
                      'Restaurar compra',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  _hero(),
                  const SizedBox(height: 26),
                  _sectionTitle('Lo que cambia con Plus'),
                  const SizedBox(height: 10),
                  _comparisonTable(),
                  const SizedBox(height: 26),
                  _sectionTitle('Solo para Plus'),
                  const SizedBox(height: 10),
                  _exclusiveGrid(),
                  const SizedBox(height: 26),
                  _sectionTitle('Elige tu plan'),
                  const SizedBox(height: 10),
                  _planCard(
                    title: 'Anual',
                    price: yearly?.price ?? '\$19.990',
                    period: '/año',
                    subtitle: 'Equivale a ${_perMonth(yearly)}${trialNote(yearlyTrial)}',
                    badge: _savingsBadge(monthly, yearly),
                    isSelected: isYearly,
                    onTap: () => setState(() =>
                        _selectedProductId = SubscriptionProductIds.yearly),
                  ),
                  const SizedBox(height: 10),
                  _planCard(
                    title: 'Mensual',
                    price: monthly?.price ?? '\$1.990',
                    period: '/mes',
                    subtitle: 'Flexible, sin compromiso${trialNote(monthlyTrial)}',
                    badge: null,
                    isSelected: !isYearly,
                    onTap: () => setState(() =>
                        _selectedProductId = SubscriptionProductIds.monthly),
                  ),
                  if (!hasRealProducts) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Precios de referencia. Los planes no se pudieron cargar desde Google Play.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.orange.withOpacity(0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  _trustRow(),
                ],
              ),
            ),
            // Botón fijo abajo
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(
                color: _kNavy,
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
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
                        disabledBackgroundColor: _kGreen.withOpacity(0.4),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: _buying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2),
                            )
                          : Text(trialDays != null
                              ? 'Prueba Plus $trialDays días gratis'
                              : isYearly
                                  ? 'Hazte Plus por ${yearly?.price ?? '\$19.990'} al año'
                                  : 'Hazte Plus por ${monthly?.price ?? '\$1.990'} al mes'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    trialDays != null
                        ? 'Luego ${base?.price ?? (isYearly ? '\$19.990' : '\$1.990')} ${isYearly ? 'al año' : 'al mes'}. '
                            'Cancela antes de que termine la prueba y no pagas nada.'
                        : 'Cancela cuando quieras desde Google Play. Sin letra chica.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Encabezado ──────────────────────────────────────────────────────────
  Widget _hero() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _kGreen.withOpacity(0.12),
            border: Border.all(color: _kGreen.withOpacity(0.35)),
          ),
          child: const Icon(Icons.workspace_premium_rounded,
              color: _kGreen, size: 32),
        ),
        const SizedBox(height: 14),
        const Text(
          'PEDALEA PLUS',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: _kGreen,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pedalea sin límites',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.reason ??
              'Rutas, momentos, bicis y eventos sin tope, más funciones que el plan gratis no tiene.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white.withOpacity(0.6),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Text(
        t.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Poppins',
          color: Colors.white.withOpacity(0.45),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      );

  // ── Gratis vs Plus ──────────────────────────────────────────────────────
  static const _limits = [
    (Icons.alt_route_rounded, 'Planificar rutas', '2 al día', 'Ilimitadas'),
    (Icons.photo_camera_outlined, 'Publicar momentos', '2 al día', 'Ilimitados'),
    (Icons.pedal_bike_rounded, 'Mis bicis', '1 bici', 'Todas'),
    (Icons.event_outlined, 'Eventos activos', 'Hasta 2', 'Ilimitados'),
  ];

  Widget _comparisonTable() {
    final dim = Colors.white.withOpacity(0.45);
    TextStyle head(Color c) => TextStyle(
          fontFamily: 'Poppins',
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Expanded(child: SizedBox()),
                SizedBox(
                    width: 72,
                    child: Text('GRATIS',
                        textAlign: TextAlign.center, style: head(dim))),
                SizedBox(
                    width: 84,
                    child: Text('PLUS',
                        textAlign: TextAlign.center, style: head(_kGreen))),
              ],
            ),
          ),
          for (final r in _limits)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
              child: Row(
                children: [
                  Icon(r.$1, size: 18, color: Colors.white70),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.$2,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      r.$3,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: 'Poppins', color: dim, fontSize: 12.5),
                    ),
                  ),
                  SizedBox(
                    width: 84,
                    child: Text(
                      r.$4,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: _kGreen,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Funciones exclusivas ────────────────────────────────────────────────
  static const _exclusives = [
    (Icons.local_fire_department_outlined, 'Mapa de calor',
        'Mira las calles donde más has pedaleado.'),
    (Icons.satellite_alt_outlined, 'Mapas premium',
        'Satélite, exterior y minimalista.'),
    (Icons.ios_share_rounded, 'Comparte en historias',
        'Tus viajes y estadísticas como imagen.'),
    (Icons.lock_outline_rounded, 'Eventos privados',
        'Crea y únete a rodadas con contraseña.'),
    (Icons.palette_outlined, 'Temas premium',
        'Colores de acento y degradados.'),
    (Icons.military_tech_outlined, 'Medalla Plus',
        'Destaca en tu perfil, chats y momentos.'),
  ];

  Widget _exclusiveGrid() {
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final e in _exclusives)
              Container(
                width: w,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(e.$1, color: _kGreen, size: 22),
                    const SizedBox(height: 10),
                    Text(
                      e.$2,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      e.$3,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Planes ──────────────────────────────────────────────────────────────
  Widget _planCard({
    required String title,
    required String price,
    required String period,
    required String subtitle,
    required String? badge,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? _kGreen.withOpacity(0.08)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _kGreen : Colors.white.withOpacity(0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? _kGreen : Colors.white38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _kGreen,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.black,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: price,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  TextSpan(
                    text: period,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trustRow() {
    Widget item(IconData i, String t) => Expanded(
          child: Column(
            children: [
              Icon(i, size: 18, color: Colors.white.withOpacity(0.5)),
              const SizedBox(height: 6),
              Text(
                t,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(Icons.verified_user_outlined, 'Pago seguro\ncon Google Play'),
        item(Icons.event_busy_outlined, 'Cancela cuando\nquieras'),
        item(Icons.favorite_border_rounded, 'Apoyas una app\nhecha en Chile'),
      ],
    );
  }
}
