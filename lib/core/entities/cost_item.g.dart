// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cost_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CostItemImpl _$$CostItemImplFromJson(Map json) => _$CostItemImpl(
      label: json['label'] as String,
      amountBDT: (json['amountBDT'] as num).toInt(),
      category: json['category'] as String,
    );

Map<String, dynamic> _$$CostItemImplToJson(_$CostItemImpl instance) =>
    <String, dynamic>{
      'label': instance.label,
      'amountBDT': instance.amountBDT,
      'category': instance.category,
    };
