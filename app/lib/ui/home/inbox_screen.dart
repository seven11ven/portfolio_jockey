import 'dart:async';

import 'package:flutter/material.dart';
import 'package:portfolio_jockey/ui/common.dart';
import 'package:portfolio_jockey/vault/inbox.dart';

/// Scenes 7 and 8 (project-mockups/home.html): notices about work the app
/// tidied up, until the user dismisses them. Opening it marks them as read.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(AppScope.read(context).markAllRead());
      }
    });
  }

  Future<void> _clearAll() async {
    final controller = AppScope.read(context);
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => PjDialog(
        title: 'Clear all notices?',
        content: const [Text('They are removed from the inbox. Nothing else changes.')],
        actions: [
          OutlinedButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Clear all')),
        ],
      ),
    );
    if (clear == true) {
      await controller.clearInbox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final notices = AppScope.of(context).inbox;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          if (notices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: OutlinedButton(onPressed: () => unawaited(_clearAll()), child: const Text('Clear all')),
            ),
        ],
      ),
      body: notices.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Muted('No notices. If the app ever has to tidy up after a crash or power cut, it says so here.'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: notices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _NoticeCard(notice: notices[i]),
            ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});

  final InboxNotice notice;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(notice.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(notice.text),
                Muted(formatAgo(notice.at)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: () => unawaited(AppScope.read(context).dismiss(notice.id)),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  );
}
