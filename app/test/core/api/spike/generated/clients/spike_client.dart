// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/activity_sort.dart';
import '../models/activity_status.dart';
import '../models/event_kind.dart';
import '../models/spike_item.dart';
import '../models/spike_write.dart';

part 'spike_client.g.dart';

@RestApi()
abstract class SpikeClient {
  factory SpikeClient(Dio dio, {String? baseUrl}) = _SpikeClient;

  /// List Spike Items
  @GET('/api/v1/spike/items')
  Future<List<SpikeItem>> listSpikeItems({
    @Query('from') required DateTime from,
    @Query('sort') ActivitySort? sort = ActivitySort.createdAt,
    @Query('include_subcategories') bool? includeSubcategories = true,
    @Query('status') List<ActivityStatus>? status,
    @Query('kinds') List<EventKind>? kinds,
    @Query('due_before') DateTime? dueBefore,
    @Query('changed_after') DateTime? changedAfter,
  });

  /// Update Spike Item
  @PUT('/api/v1/spike/items/{item_id}')
  Future<SpikeItem> updateSpikeItem({
    @Path('item_id') required String itemId,
    @Body() required SpikeWrite body,
  });
}
