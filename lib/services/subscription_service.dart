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

  /// Concede Plus de prueba. **Solo funciona para las cuentas del dueño de la
  /// app** (el RPC `grant_owner_test_plus` valida el email en el servidor); a
  /// cualquier otro usuario le devuelve un error y no pasa nada. Ya no existe
  /// el "Plus simulado" abierto que cualquiera podía activar.
  Future<bool> grantTestPlus({int days = 30}) async {
    try {
      await Supabase.instance.client
          .rpc('grant_owner_test_plus', params: {'p_days': days});
      await refreshPlusStatus();
      return isPlus.value;
    } catch (e) {
      debugPrint('SubscriptionService grantTestPlus error: $e');
      return false;
    }
  }

  /// Quita el Plus de prueba (solo para cuentas del dueño).
  Future<void> revokeTestPlus() async {
    try {
      await Supabase.instance.client.rpc('revoke_owner_test_plus');
    } catch (e) {
      debugPrint('SubscriptionService revokeTestPlus error: $e');
    }
    await refreshPlusStatus();
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
        isSimulated: token.startsWith('simulated_') ||
            token.startsWith('owner_test_'),
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

      var verified = false;
      if (purchase.status == PurchaseStatus.error) {
        debugPrint('SubscriptionService: error de compra: ${purchase.error}');
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        verified = await _recordPurchase(purchase);
      }

      // Solo se confirma (acknowledge) la compra si el servidor la verificó.
      // Si no, se deja pendiente: se reintenta al reabrir la app y, si nunca
      // se verifica, Google la reembolsa sola a los 3 días.
      if (purchase.pendingCompletePurchase && verified) {
        await _iap.completePurchase(purchase);
      }
    }
    await refreshPlusStatus();
  }

  /// Verifica la compra en el servidor. El cliente **no** puede activar la
  /// suscripción: manda el `purchaseToken` a la Edge Function
  /// `verify-play-purchase`, que lo valida contra la Google Play Developer API
  /// y recién ahí marca la fila como activa (con service_role). La RLS impide
  /// que la app escriba `subscriptions.is_active` o `profiles.is_plus`.
  /// Devuelve true si el servidor confirmó que la compra es válida y activa.
  Future<bool> _recordPurchase(PurchaseDetails purchase) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return false;
    final token = purchase.verificationData.serverVerificationData;
    if (token.isEmpty) return false;
    try {
      final res = await Supabase.instance.client.functions.invoke(
        'verify-play-purchase',
        body: {
          'productId': purchase.productID,
          'purchaseToken': token,
        },
      );
      final data = res.data;
      return data is Map && data['isPlus'] == true;
    } catch (e) {
      debugPrint('SubscriptionService _recordPurchase (verify) error: $e');
      return false;
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
