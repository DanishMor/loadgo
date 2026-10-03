import 'package:flutter/material.dart';

import '../../core/models/paged.dart';
import '../../main.dart';
import 'live_stream.dart';

typedef PagedStreamFactory<Item> = Stream<Paged<Item>> Function(int limit);

/// [LiveStream] over a growing page. [builder] gets the items plus a
/// ready-made "Load more" button (null when everything is loaded) to place
/// at the end of its list.
class PagedLiveStream<Item> extends StatefulWidget {
  final PagedStreamFactory<Item> stream;
  final Widget Function(BuildContext context, List<Item> items, Widget? loadMore) builder;
  final bool compact;

  const PagedLiveStream({super.key, required this.stream, required this.builder, this.compact = false});

  @override
  State<PagedLiveStream<Item>> createState() => _PagedLiveStreamState<Item>();
}

class _PagedLiveStreamState<Item> extends State<PagedLiveStream<Item>> {
  int _limit = pageSize;

  @override
  Widget build(BuildContext context) {
    return LiveStream<Paged<Item>>(
      stream: () => widget.stream(_limit),
      resubscribeKey: _limit,
      compact: widget.compact,
      builder: (context, page) => widget.builder(
        context,
        page.items,
        page.hasMore
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _limit += pageSize),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(tr(context, 'loadMore')),
                ),
              )
            : null,
      ),
    );
  }
}
