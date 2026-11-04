import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// Searches TMDB (contract section 19) starting from [query]; resolves to the
/// chosen movie's details, or null when closed.
Future<Movie?> showMovieSearch(BuildContext context, {String query = ''}) =>
    showModalBottomSheet<Movie>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MovieSearchSheet(query: query),
    );

class _MovieSearchSheet extends ConsumerStatefulWidget {
  const new({required this.query});

  final String query;

  @override
  ConsumerState<_MovieSearchSheet> createState() => _MovieSearchSheetState();
}

class _MovieSearchSheetState extends ConsumerState<_MovieSearchSheet> {
  late final _query = TextEditingController(text: widget.query);
  List<MovieSearchResult>? _results;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.query.trim().isNotEmpty) unawaited(_search());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await apiCall(
        () => ref.read(moviesClientProvider).searchMovies(query: query),
      );
      if (mounted) setState(() => _results = results);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(MovieSearchResult result) async {
    setState(() => _busy = true);
    try {
      final movie = await apiCall(
        () => ref.read(moviesClientProvider).getMovie(tmdbId: result.tmdbId),
      );
      if (mounted) Navigator.of(context).pop(movie);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = _results;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.findMovie, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              autofocus: widget.query.isEmpty,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: l10n.movieTitle,
                suffixIcon: IconButton(
                  tooltip: l10n.search,
                  icon: const Icon(Icons.search),
                  onPressed: _busy ? null : () => unawaited(_search()),
                ),
              ),
              onSubmitted: (_) => unawaited(_search()),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (results != null && results.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(l10n.noMoviesFound),
              ),
            if (results != null && results.isNotEmpty)
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final result in results)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _Poster(url: result.posterUrl),
                        title: Text(
                          [result.title, ?result.year?.toString()].join(' · '),
                        ),
                        subtitle: result.overview == null
                            ? null
                            : Text(
                                result.overview!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: _busy ? null : () => unawaited(_choose(result)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              l10n.tmdbAttribution,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const new({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const placeholder = SizedBox(
      width: 40,
      height: 60,
      child: Icon(Icons.movie_outlined),
    );
    final url = this.url;
    if (url == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        url,
        width: 40,
        height: 60,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }
}
