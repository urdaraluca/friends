import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/features/books/data/books_providers.dart';
import 'package:material_ui/material_ui.dart';

/// A book's cover at [width] (2:3), or a placeholder while it loads, when it
/// fails, or when the book has none.
class BookCover extends ConsumerWidget {
  const new({required this.book, required this.width, super.key});

  final Book book;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = book.coverUpdatedAt;
    final bytes = version == null
        ? null
        : ref.watch(bookCoverProvider(book.id, version)).value;
    return CoverFrame(
      width: width,
      child: bytes == null
          ? CoverPlaceholder(available: book.holder == null, width: width)
          : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

/// A cover-shaped (2:3) frame with rounded corners.
class CoverFrame extends StatelessWidget {
  const new({required this.width, required this.child, super.key});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * 1.5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width < 64 ? 4 : 8),
        child: child,
      ),
    );
  }
}

/// What a book without a cover shows: a book icon (an outbound arrow when
/// it is lent out).
class CoverPlaceholder extends StatelessWidget {
  const new({required this.width, this.available = true, super.key});

  final double width;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: available
          ? colors.secondaryContainer
          : colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          available ? Icons.menu_book : Icons.outbound_outlined,
          size: width * 0.45,
          color: available
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A cover the form is about to save: picked [bytes], or a catalogue's
/// [url] to preview.
class CoverPreview extends StatelessWidget {
  const new({required this.width, this.bytes, this.url, super.key});

  final double width;
  final Uint8List? bytes;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final bytes = this.bytes;
    final url = this.url;
    final placeholder = CoverPlaceholder(width: width);
    return CoverFrame(
      width: width,
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover)
          : url != null
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            )
          : placeholder,
    );
  }
}
