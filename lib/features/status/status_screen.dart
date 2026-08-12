import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/colors.dart';
import '../../app/providers.dart';
import '../../widgets/avatar.dart';
import 'status_model.dart';
import 'status_composer.dart';
import 'status_viewer.dart';

/// Status: my own updates on top, contacts' below — never mixed.
class StatusScreen extends ConsumerWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = KScheme.of(context);
    final feed = ref.watch(statusFeedProvider);
    final me = ref.watch(activePersonaProvider).valueOrNull;

    return Scaffold(
      backgroundColor: s.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: KColors.teal,
          onRefresh: () async =>
              ref.read(statusRefreshProvider.notifier).state++,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: [
                    const Text('Status',
                        style: TextStyle(
                            color: KColors.teal,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5)),
                    const Spacer(),
                  ],
                ),
              ),
              // Keep the previous feed on screen while a refresh runs,
              // otherwise the page blanks and redraws like a web page.
              feed.maybeWhen(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: true,
                loading: () => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                      child: CircularProgressIndicator(color: KColors.teal)),
                ),
                orElse: () => const SizedBox.shrink(),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.all(30),
                  child: Center(
                      child: Text('Could not load status',
                          style: TextStyle(color: s.muted))),
                ),
                data: (f) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(
                      title: 'MY STATUS',
                      trailing: f.hasMine ? '${f.myViews} views' : null,
                    ),
                    if (f.hasMine)
                      _MyStatusCard(
                        feed: f,
                        meSeed: me?.username ?? 'me',
                        photo: me?.avatar,
                        onOpen: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) =>
                              StatusViewer(items: f.mine, mine: true),
                        )),
                        onAdd: () => StatusComposer.open(context, ref),
                      )
                    else
                      _EmptyMyStatus(
                          onTap: () => StatusComposer.open(context, ref)),
                    Container(
                      height: 8,
                      margin: const EdgeInsets.only(top: 18),
                      color: s.panel2,
                    ),
                    _SectionLabel(
                      title: 'RECENT UPDATES',
                      trailing:
                          f.unseenCount > 0 ? '${f.unseenCount} new' : null,
                    ),
                    if (f.others.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 40, 24, 60),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.blur_circular_outlined,
                                size: 42, color: s.faint),
                            const SizedBox(height: 12),
                            Text('No recent updates',
                                style: TextStyle(
                                    color: s.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 5),
                            Text(
                                'Updates from your contacts show up here for 24 hours.',
                                textAlign: TextAlign.center,
                                style:
                                    TextStyle(color: s.muted, fontSize: 13.5)),
                          ],
                        ),
                      )
                    else
                      _OthersGrid(feed: f),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final String? trailing;
  const _SectionLabel({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 9),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  color: s.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          const Spacer(),
          if (trailing != null)
            Text(trailing!,
                style: const TextStyle(
                    color: KColors.teal,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// My own status — its own teal card with counts and an add button.
class _MyStatusCard extends StatelessWidget {
  final StatusFeed feed;
  final String meSeed;
  final String? photo;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  const _MyStatusCard({
    required this.feed,
    required this.meSeed,
    required this.photo,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final latest = feed.mine.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [KColors.teal, KColors.teal2],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: KColors.teal.withOpacity(0.28),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            GestureDetector(
              onTap: onOpen,
              child: _Thumb(item: latest),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: GestureDetector(
                onTap: onOpen,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your status',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                        '${feed.mine.length} update${feed.mine.length == 1 ? '' : 's'} · ${latest.timeLeft}',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 12)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text('👁 ${feed.myViews}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: KColors.amber,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded,
                    color: Colors.white, size: 23),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final StatusItem item;
  const _Thumb({required this.item});

  @override
  Widget build(BuildContext context) {
    final bytes = item.isPhoto ? Avatar.decode(item.payload) : null;
    final pair = KColors.avatarPairFor(item.kalId);
    return Container(
      width: 56,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.85), width: 2.5),
        gradient: bytes == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: pair)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover)
          : Center(
              child: Text(
                item.isVoice ? '🎤' : 'Aa',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800),
              ),
            ),
    );
  }
}

class _EmptyMyStatus extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyMyStatus({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = KScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: s.panel2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: s.line, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: KColors.teal,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded,
                    color: Colors.white, size: 25),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add to your status',
                        style: TextStyle(
                            color: s.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Text, photo or voice · disappears in 24 h',
                        style: TextStyle(color: s.muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contacts' updates as portrait cards, grouped per person.
class _OthersGrid extends StatelessWidget {
  final StatusFeed feed;
  const _OthersGrid({required this.feed});

  @override
  Widget build(BuildContext context) {
    final grouped = feed.byPerson;
    final people = grouped.keys.toList()
      ..sort((a, b) {
        final an = grouped[a]!.any((s) => !s.seen) ? 0 : 1;
        final bn = grouped[b]!.any((s) => !s.seen) ? 0 : 1;
        if (an != bn) return an - bn; // unseen first
        return grouped[b]!.last.ts.compareTo(grouped[a]!.last.ts);
      });

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 11,
        crossAxisSpacing: 11,
        childAspectRatio: 9 / 14,
      ),
      itemCount: people.length,
      itemBuilder: (_, i) => _PersonCard(items: grouped[people[i]]!),
    );
  }
}

class _PersonCard extends StatelessWidget {
  final List<StatusItem> items;
  const _PersonCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final latest = items.last;
    final unseen = items.any((s) => !s.seen);
    final bytes = latest.isPhoto ? Avatar.decode(latest.payload) : null;
    final pair = KColors.avatarPairFor(latest.kalId);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StatusViewer(items: items),
      )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Image.memory(bytes, fit: BoxFit.cover)
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: pair,
                  ),
                ),
                child: latest.isText
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(12, 46, 12, 40),
                        child: Text(
                          latest.payload,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.35),
                        ),
                      )
                    : const Center(
                        child: Text('🎤', style: TextStyle(fontSize: 34))),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black54, Colors.transparent],
                  stops: [0.0, 0.55],
                ),
              ),
            ),
            Positioned(
              top: 9,
              left: 9,
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: unseen
                      ? const LinearGradient(
                          colors: [KColors.amber, Colors.white])
                      : null,
                  color: unseen ? null : Colors.white24,
                ),
                child: Avatar(
                  seed: latest.kalId,
                  label: latest.name.isNotEmpty
                      ? latest.name[0].toUpperCase()
                      : '?',
                  size: 32,
                ),
              ),
            ),
            if (latest.kindBadge != null)
              Positioned(
                top: 11,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(latest.kindBadge!,
                      style: const TextStyle(fontSize: 11)),
                ),
              ),
            if (items.length > 1)
              Positioned(
                top: 44,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text('${items.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 9,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(latest.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(latest.ago,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
