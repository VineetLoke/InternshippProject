/// Identifies which social media app is being blocked.
enum BlockedApp {
  instagram('com.instagram.android', 'Instagram', 50, '15 min access'),
  reddit('com.reddit.frontpage', 'Reddit', 100, '10 min access'),
  twitter('com.twitter.android', 'Twitter/X', 50, '15 min access');

  const BlockedApp(this.packageName, this.displayName, this.requiredPushups, this.rewardText);

  final String packageName;
  final String displayName;
  final int requiredPushups;
  final String rewardText;
}
