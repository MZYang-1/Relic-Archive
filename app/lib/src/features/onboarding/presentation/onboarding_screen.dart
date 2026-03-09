import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'title': '记录每一件物品的故事',
      'description': '不仅仅是照片，更是情感的载体。为你的旧物撰写传记，留住时光的温度。',
      'icon': Icons.auto_stories,
      'color': Color(0xFF8D6E63), // Brown
    },
    {
      'title': '打造你的私人博物馆',
      'description': '分类整理，智能检索。让杂乱的旧物变成井井有条的数字收藏馆。',
      'icon': Icons.museum,
      'color': Color(0xFF5D4037), // Darker Brown
    },
    {
      'title': '全方位鉴赏体验',
      'description': '独创伪 3D 视图，手指滑动即可 360° 查看物品细节，仿佛触手可及。',
      'icon': Icons.thirteen_mp, // Using the same icon as in Pseudo3DViewer
      'color': Color(0xFF3E2723), // Very Dark Brown
    },
    {
      'title': '隐私安全，指纹守护',
      'description': '支持私密收藏馆，通过生物识别技术保护你的珍贵回忆不被窥探。',
      'icon': Icons.fingerprint,
      'color': Color(0xFF1B5E20), // Greenish for security
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemCount: _pages.length,
            itemBuilder: (context, index) {
              final page = _pages[index];
              return Container(
                color: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: (page['color'] as Color).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        page['icon'] as IconData,
                        size: 80,
                        color: page['color'] as Color,
                      ),
                    ),
                    const SizedBox(height: 48),
                    Text(
                      page['title'] as String,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: page['color'] as Color,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      page['description'] as String,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.grey[600],
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 8,
                      width: _currentPage == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? (_pages[_currentPage]['color'] as Color)
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentPage < _pages.length - 1)
                        TextButton(
                          onPressed: _completeOnboarding,
                          child: const Text('跳过'),
                        )
                      else
                        const SizedBox(
                          width: 64,
                        ), // Placeholder to balance layout

                      ElevatedButton(
                        onPressed: () {
                          if (_currentPage < _pages.length - 1) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          } else {
                            _completeOnboarding();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _pages[_currentPage]['color'] as Color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          _currentPage == _pages.length - 1 ? '开始体验' : '下一步',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
