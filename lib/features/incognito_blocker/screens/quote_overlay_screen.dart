import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../model/quote_model.dart';

/// Full-screen quote overlay that replaces blocked app content.
///
/// Dark-themed, calm, and not aggressive. Cannot be dismissed by Back/Home.
///
/// This widget is used both as an in-app screen (when triggered by the
/// accessibility service) and rendered by the system overlay.
class QuoteOverlayScreen extends StatelessWidget {
  const QuoteOverlayScreen({
    super.key,
    required this.quote,
    this.appName = '',
    this.onRequestAccess,
    this.pushupCount = 100,
    this.rewardText = '10 min access',
  });

  final QuoteModel quote;
  final String appName;
  final VoidCallback? onRequestAccess;
  final int pushupCount;
  final String rewardText;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.overlayBackground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // App icon / header
              const Icon(Icons.lock_outline, size: 56, color: AppColors.accent),
              const SizedBox(height: 16),
              const Text(
                AppStrings.quoteOverlayTitle,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                AppStrings.quoteOverlaySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 48),
              // Quote card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.format_quote,
                      size: 32,
                      color: AppColors.accent,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      quote.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontStyle: FontStyle.italic,
                        color: AppColors.overlayQuote,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: 40,
                      height: 2,
                      color: AppColors.accent.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '— ${quote.author}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.overlayAuthor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      quote.category.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 2,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              // Action buttons
              if (onRequestAccess != null) ...[
                ElevatedButton.icon(
                  onPressed: onRequestAccess,
                  icon: const Icon(Icons.fitness_center, size: 20),
                  label: Text(
                    'Do $pushupCount Pushups for $rewardText',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (appName.contains('Chrome')) ...[
                const Text(
                  AppStrings.quoteCloseChrome,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const SizedBox(height: 16),
              // Subtle fade-in animation hint
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 1200),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: child,
                  );
                },
                child: const Text(
                  AppStrings.quoteCloseApp,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}