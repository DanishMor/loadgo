/// One page of a live list: the newest [items] up to the requested limit and
/// whether older ones may exist (the server returned a full page).
class Paged<T> {
  final List<T> items;
  final bool hasMore;

  const Paged(this.items, {required this.hasMore});

  /// A complete list with nothing further to load.
  const Paged.all(this.items) : hasMore = false;
}

/// How many items each list loads at a time.
const pageSize = 20;
