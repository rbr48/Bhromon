import 'package:freezed_annotation/freezed_annotation.dart';

part 'cost_item.freezed.dart';
part 'cost_item.g.dart';

@freezed
class CostItem with _$CostItem {
  const factory CostItem({
    required String label,
    required int amountBDT,
    required String category,
  }) = _CostItem;

  factory CostItem.fromJson(Map<String, dynamic> json) =>
      _$CostItemFromJson(json);
}
