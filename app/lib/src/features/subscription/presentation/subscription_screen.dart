import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  static const Set<String> _productIds = {
    'relic_archive_premium_monthly_v2',
    'relic_archive_premium_yearly_v2',
  };

  static final Uri _privacyPolicyUrl = Uri.parse(
    'https://relicarchive.app/privacy',
  );
  static final Uri _termsUrl = Uri.parse(
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
  );

  final InAppPurchase _iap = InAppPurchase.instance;
  late final StreamSubscription<List<PurchaseDetails>> _sub;

  bool _available = false;
  bool _loading = true;
  String? _error;

  List<ProductDetails> _products = const [];
  bool _purchaseInFlight = false;

  @override
  void initState() {
    super.initState();
    _sub = _iap.purchaseStream.listen(_onPurchaseUpdate);
    _init();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final available = await _iap.isAvailable();
      if (!mounted) return;
      setState(() => _available = available);
      if (!available) {
        setState(() {
          _loading = false;
          _error = '当前设备不可用内购服务';
        });
        return;
      }

      final response = await _iap.queryProductDetails(_productIds);
      if (!mounted) return;
      if (response.error != null) {
        final err = response.error!;
        final isNoResponse = err.code == 'storekit_no_response';
        final isNotAvailable =
            err.code == 'storekit_not_available' ||
            err.code == 'storekit_network_error';
        setState(() {
          _loading = false;
          _error = isNoResponse
              ? 'App Store 未返回订阅商品信息。\n'
                    '请检查：\n'
                    '1) Xcode -> Runner -> Signing & Capabilities 已添加 In-App Purchase\n'
                    '2) App Store Connect 已创建订阅商品 ID：\n'
                    '   - relic_archive_premium_monthly_v2\n'
                    '   - relic_archive_premium_yearly_v2\n'
                    '3) 真机可访问 App Store（网络正常）\n'
                    '4) 若要测试购买，请在系统设置里登录 Sandbox 测试账号\n'
                    '${kDebugMode ? '\n原始错误: $err' : ''}'
              : isNotAvailable
              ? '当前环境无法连接到内购服务，请稍后重试。\n'
                    '${kDebugMode ? '\n原始错误: $err' : ''}'
              : '获取订阅信息失败。\n${kDebugMode ? '\n原始错误: $err' : ''}';
        });
        return;
      }
      if (response.productDetails.isEmpty) {
        setState(() {
          _loading = false;
          _error = '未找到订阅商品，请确认 App Store Connect 商品ID配置';
        });
        return;
      }

      final products = response.productDetails.toList()
        ..sort((a, b) => a.price.compareTo(b.price));
      setState(() {
        _products = products;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '初始化失败: $e';
      });
    }
  }

  Future<void> _buy(ProductDetails product) async {
    setState(() {
      _purchaseInFlight = true;
      _error = null;
    });
    final purchaseParam = PurchaseParam(productDetails: product);
    final ok = await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    if (!ok && mounted) {
      setState(() => _purchaseInFlight = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _purchaseInFlight = true;
      _error = null;
    });
    await _iap.restorePurchases();
  }

  Future<void> _open(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
    }
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.error) {
        if (mounted) {
          setState(() {
            _purchaseInFlight = false;
            _error = p.error?.message ?? '购买失败';
          });
        }
      } else if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        if (mounted) {
          setState(() => _purchaseInFlight = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('购买/恢复成功')));
        }
      } else if (p.status == PurchaseStatus.canceled) {
        if (mounted) setState(() => _purchaseInFlight = false);
      }

      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('会员订阅')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: cs.secondaryContainer,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('解锁会员权益', style: TextStyle(fontSize: 20)),
                SizedBox(height: 8),
                Text('· 更快的 3D 重建队列优先级'),
                Text('· 更高的重建次数与更大素材上限'),
                Text('· 高质量导出与更多主题样式'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading) ...[
            const Center(child: CircularProgressIndicator()),
          ] else if (_error != null) ...[
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _init, child: const Text('重试')),
          ] else ...[
            if (!_available) Text('内购不可用', style: TextStyle(color: cs.error)),
            for (final p in _products)
              Card(
                child: ListTile(
                  title: Text(p.title),
                  subtitle: Text(p.description),
                  trailing: FilledButton(
                    onPressed: _purchaseInFlight ? null : () => _buy(p),
                    child: Text(p.price),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _purchaseInFlight ? null : _restore,
              child: const Text('恢复购买'),
            ),
            const SizedBox(height: 16),
            Text(
              '订阅说明：订阅将自动续费。确认购买后，将向您的 Apple ID 账户收费。'
              '您可以在系统设置中管理或取消订阅。若在当前周期结束前至少 24 小时未取消，订阅将自动续费。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: () => _open(_privacyPolicyUrl),
                  child: const Text('隐私政策'),
                ),
                TextButton(
                  onPressed: () => _open(_termsUrl),
                  child: const Text('用户协议'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
