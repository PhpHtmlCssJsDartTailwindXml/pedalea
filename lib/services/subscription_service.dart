import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// IDs de producto que deben existir EXACTOS en Play Console
/// (Monetización → Productos → Suscripciones) antes de que las compras
/// funcionen. Ver documentación en README o pedir a Ignacio los pasos.
class SubscriptionProductIds {
  static const monthly = 'pedalea_plus_monthly';
  static const yearly = 'pedalea_plus_yearly';
  static const all = {monthly, yearly};
}

/// Info de la suscripción activa del usuario, para mostrar en "Gestionar
/// suscripción" (fecha de inicio, próximo cobro, si es simulada o real).
class SubscriptionInfo {
  final String productId;
  final DateTime purchasedAt;
  final DateTime? expiresAt;
  final bool isSimulated;
  const SubscriptionInfo({
    required this.productId,
    required this.purchasedAt,
    required this.expiresAt,
    required this.isSimulated,
  });

  bool get isYearly => productId == SubscriptionProductIds.yearly;
}

/// Maneja Google Play Billing: consulta de productos, compra, restauración,
/// y sincroniza el estado "Plus" del usuario con la tabla `subscriptions`
/// de Supabase.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  StreamSubscription<AuthState>? _authSub;
  String? _lastUserId;

  /// true si el usuario tiene una suscripción Plus activa ahora mismo.
  final ValueNotifier<bool> isPlus = ValueNotifier(false);

  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _lastUserId = Supabase.instance.client.auth.currentUser?.id;

    // Sin esto, "isPlus" quedaba pegado con el estado de la cuenta anterior
    // al cerrar sesión e iniciar con otra: refreshPlusStatus() antes solo se
    // llamaba una vez al abrir la app y en flujos de compra, nunca al
    // cambiar de cuenta.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final newUserId = data.session?.user.id;
      if (newUserId != _lastUserId) {
        _lastUserId = newUserId;
        if (newUserId == null) {
          isPlus.value = false;
        } else {
          refreshPlusStatus();
        }
      }
    });

    final available = await _iap.isAvailable();
    if (!available) {
      debugPrint('SubscriptionService: Play Billing no disponible en este dispositivo/emulador.');
      await refreshPlusStatus();
      return;
    }

    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (e) => debugPrint('SubscriptionService purchaseStream error: $e'),
    );

    await _loadProducts();
    await refreshPlusStatus();
  }

  /// Activa/desactiva Plus de forma simulada (mientras no hay productos
  /// reales en Play Console). A diferencia de la versión anterior, esto
  /// SÍ crea una fila real en `subscriptions` con fecha de inicio y de
  /// vencimiento, para que "Gestionar suscripción" muestre datos reales.
  Future<void> setSimulatedPlus(
    bool value, {
    String productId = SubscriptionProductIds.yearly,
  }) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      if (value) {
        final now = DateTime.now();
        final expires = productId == SubscriptionProductIds.monthly
            ? now.add(const Duration(days: 30))
            : now.add(const Duration(days: 365));
        await Supabase.instance.client.from('subscriptions').insert({
          'user_id': uid,
          'product_id': productId,
          'purchase_token': 'simulated_${now.millisecondsSinceEpoch}',
          'is_active': true,
          'purchased_at': now.toIso8601String(),
          'expires_at': expires.toIso8601String(),
        });
        await _syncProfileIsPlus(true);
      } else {
        await Supabase.instance.client
            .from('subscriptions')
            .update({'is_active': false})
            .eq('user_id', uid)
            .like('purchase_token', 'simulated_%');
        await _syncProfileIsPlus(false);
      }
    } catch (e) {
      debugPrint('SubscriptionService setSimulatedPlus error: $e');
    }
    await refreshPlusStatus();
  }

  Future<void> _syncProfileIsPlus(bool value) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'is_plus': value})
          .eq('id', uid);
    } catch (e) {
      debugPrint('SubscriptionService _syncProfileIsPlus error: $e');
    }
  }

  /// Trae los datos de la suscripción activa actual (real o simulada) para
  /// mostrar en la pantalla de "Gestionar suscripción".
  Future<SubscriptionInfo?> getMySubscriptionInfo() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final rows = await Supabase.instance.client
          .from('subscriptions')
          .select('product_id, purchase_token, purchased_at, expires_at')
          .eq('user_id', uid)
          .eq('is_active', true)
          .order('purchased_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      final row = rows.first;
      final purchasedAt = DateTime.tryParse(row['purchased_at'] as String? ?? '') ?? DateTime.now();
      final expiresAt = row['expires_at'] != null
          ? DateTime.tryParse(row['expires_at'] as String)
          : null;
      final token = row['purchase_token'] as String? ?? '';
      return SubscriptionInfo(
        productId: row['product_id'] as String? ?? SubscriptionProductIds.yearly,
        purchasedAt: purchasedAt,
        expiresAt: expiresAt,
        isSimulated: token.startsWith('simulated_'),
      );
    } catch (e) {
      debugPrint('SubscriptionService getMySubscriptionInfo error: $e');
      return null;
    }
  }

  Future<void> _loadProducts() async {
    try {
      final response = await _iap.queryProductDetails(SubscriptionProductIds.all);
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
            'SubscriptionService: productos no encontrados en Play Console: ${response.notFoundIDs}. '
            'Revisa que existan con esos IDs exactos y estén activos.');
      }
      _products = response.productDetails;
    } catch (e) {
      debugPrint('SubscriptionService _loadProducts error: $e');
    }
  }

  Future<void> buy(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) continue;

      if (purchase.status == PurchaseStatus.error) {
        debugPrint('SubscriptionService: error de compra: ${purchase.error}');
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _recordPurchase(purchase);
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
    await refreshPlusStatus();
  }

  /// Guarda la compra en Supabase. Nota: esto confía en el resultado de Play
  /// Billing del lado del cliente; para producción robusta conviene validar
  /// el purchaseToken contra la Google Play Developer API desde un backend
  /// (ej. una Edge Function de Supabase) antes de marcarla como activa.
  Future<void> _recordPurchase(PurchaseDetails purchase) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final now = DateTime.now();
      await Supabase.instance.client.from('subscriptions').upsert({
        'user_id': uid,
        'product_id': purchase.productID,
        'purchase_token': purchase.purchaseID ?? purchase.verificationData.serverVerificationData,
        'is_active': true,
        'purchased_at': now.toIso8601String(),
      }, onConflict: 'purchase_token');
      await _syncProfileIsPlus(true);
    } catch (e) {
      debugPrint('SubscriptionService _recordPurchase error: $e');
    }
  }

  /// Vuelve a consultar si el usuario tiene Plus activo (llamar al abrir
  /// pantallas que dependan de esto, por si cambió en otro dispositivo).
  Future<void> refreshPlusStatus() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      isPlus.value = false;
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('subscriptions')
          .select('is_active, expires_at')
          .eq('user_id', uid)
          .eq('is_active', true);
      final now = DateTime.now();
      final active = rows.any((r) {
        final expiresAt = r['expires_at'] as String?;
        if (expiresAt == null) return true;
        final dt = DateTime.tryParse(expiresAt);
        return dt == null || dt.isAfter(now);
      });
      isPlus.value = active;
    } catch (e) {
      debugPrint('SubscriptionService refreshPlusStatus error: $e');
    }
  }

  void dispose() {
    _purchaseSub?.cancel();
    _authSub?.cancel();
  }
}
