// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/category.dart';
import '../models/category_node.dart';
import '../models/category_order.dart';
import '../models/category_write.dart';

part 'categories_client.g.dart';

@RestApi()
abstract class CategoriesClient {
  factory CategoriesClient(Dio dio, {String? baseUrl}) = _CategoriesClient;

  /// List Categories.
  ///
  /// Top-level categories by position, then name; each with its subcategories in the same.
  /// order.
  @GET('/api/v1/groups/{group_id}/categories')
  Future<List<CategoryNode>> listCategories({
    @Path('group_id') required String groupId,
  });

  /// Create Category.
  ///
  /// Any member. ``position: null`` appends at the end among the siblings.
  @POST('/api/v1/groups/{group_id}/categories')
  Future<Category> createCategory({
    @Path('group_id') required String groupId,
    @Body() required CategoryWrite body,
  });

  /// Reorder Categories.
  ///
  /// Admins. Orders the top-level categories, or one category's subcategories.
  /// ``category_ids`` lists every one of them, exactly once. Returns the whole tree.
  @PUT('/api/v1/groups/{group_id}/categories/order')
  Future<List<CategoryNode>> reorderCategories({
    @Path('group_id') required String groupId,
    @Body() required CategoryOrder body,
  });

  /// Update Category.
  ///
  /// The creator or an admin. ``position: null`` keeps the current position; a field's type.
  /// can't change (remove it and add it back).
  @PUT('/api/v1/categories/{category_id}')
  Future<Category> updateCategory({
    @Path('category_id') required String categoryId,
    @Body() required CategoryWrite body,
  });

  /// Delete Category.
  ///
  /// The creator or an admin. A subcategory's activities move to its parent; deleting a.
  /// top-level category deletes its subcategories and leaves their activities uncategorized.
  @DELETE('/api/v1/categories/{category_id}')
  Future<void> deleteCategory({
    @Path('category_id') required String categoryId,
  });
}
