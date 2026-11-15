import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/glass.dart';
import '../services/subscription_service.dart';

const _kNavy = Color(0xFF12213F);

/// Pantalla para ver el estado de la suscripción Plus del usuario (fecha de
/// inicio, próximo cobro) y cancelarla.
class ManageSubscriptionPage extends StatefulWidget {
  const ManageSubscriptionPage({super.key});

  @override
  State<ManageSubscriptionPage> createState() => _ManageSubscriptionPageState();
}

class _ManageSubscriptionPageState extends State<ManageSubscriptionPage> {
  SubscriptionInfo? _info;
  bool _loading = true;
  bool _cancelling = false;

  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await SubscriptionService.instance.getMySubscriptionInfo();
    if (mounted) {
      setState(() {
        _info = info;
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return '${local.day} de ${_meses[local.month - 1]} de ${local.year}';
  }

  Future<void> _cancel() async {
    final info = _info;
    if (info == null) return;

    if (!info.isSimulated) {
      // Suscripción real: Google no permite cancelarla desde la app, solo
      // desde Play Store.
      final uri = Uri.parse(
        'https://play.google.com/store/account/subscriptions?sku=${info.productId}&package=com.pedalea.app',
      );
      if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '¿Cancelar Pedalea Plus?',
          style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
        ),
        content: const Text(
          'Perderás el acceso a las funciones Plus de inmediato.',
          style: TextStyle(fontFamily: 'Poppins', color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver', style: TextStyle(fontFamily: 'Poppins', color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar suscripción', style: TextStyle(fontFamily: 'Poppins', color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancelling = true);
    await SubscriptionService.instance.revokeTestPlus();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: kPageGradient,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: glassDecoration(radius: 12),
                        child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Mi suscripción',
                      style: TextStyle(
                        fontFamily: 'Poppins', color: Colors.white,
                        fontWeight: FontWeight.w600, fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.amber))
                    : _info == null
                        ? const Center(
                            child: Text(
                              'No encontramos tu suscripción.',
                              style: TextStyle(fontFamily: 'Poppins', color: Colors.white60),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Color(0xFF2A2000), _kNavy],
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 44),
                                      const SizedBox(height: 10),
                                      Text(
                                        _info!.isYearly ? 'Plan Anual' : 'Plan Mensual',
                                        style: const TextStyle(
                                          fontFamily: 'Poppins', color: Colors.white,
                                          fontSize: 20, fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Container(
                                  decoration: glassDecoration(radius: 18),
                                  child: Column(children: [
                                    _infoRow(Icons.calendar_today_outlined, 'Te suscribiste el',
                                        _formatDate(_info!.purchasedAt)),
                                    Divider(height: 1, color: Colors.white.withOpacity(0.06), indent: 46, endIndent: 16),
                                    _infoRow(
                                      Icons.event_repeat_outlined,
                                      _info!.isSimulated ? 'Vigente hasta el' : 'Próximo cobro',
                                      _info!.expiresAt != null ? _formatDate(_info!.expiresAt!) : '—',
                                    ),
                                  ]),
                                ),
                                const Spacer(),
                                SizedBox(
                                  height: 52,
                                  child: OutlinedButton(
                                    onPressed: _cancelling ? null : _cancel,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.redAccent,
                                      side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    ),
                                    child: _cancelling
                                        ? const SizedBox(
                                            width: 20, height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                                          )
                                        : Text(
                                            _info!.isSimulated
                                                ? 'Cancelar suscripción'
                                                : 'Gestionar en Google Play',
                                            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber.withOpacity(0.7), size: 17),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontFamily: 'Poppins', color: Colors.white38, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Poppins', color: Colors.white,
              fontSize: 14, fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
