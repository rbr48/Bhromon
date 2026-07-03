// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'cost_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

CostItem _$CostItemFromJson(Map<String, dynamic> json) {
  return _CostItem.fromJson(json);
}

/// @nodoc
mixin _$CostItem {
  String get label => throw _privateConstructorUsedError;
  int get amountBDT => throw _privateConstructorUsedError;
  String get category => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $CostItemCopyWith<CostItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CostItemCopyWith<$Res> {
  factory $CostItemCopyWith(CostItem value, $Res Function(CostItem) then) =
      _$CostItemCopyWithImpl<$Res, CostItem>;
  @useResult
  $Res call({String label, int amountBDT, String category});
}

/// @nodoc
class _$CostItemCopyWithImpl<$Res, $Val extends CostItem>
    implements $CostItemCopyWith<$Res> {
  _$CostItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? label = null,
    Object? amountBDT = null,
    Object? category = null,
  }) {
    return _then(_value.copyWith(
      label: null == label
          ? _value.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      amountBDT: null == amountBDT
          ? _value.amountBDT
          : amountBDT // ignore: cast_nullable_to_non_nullable
              as int,
      category: null == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CostItemImplCopyWith<$Res>
    implements $CostItemCopyWith<$Res> {
  factory _$$CostItemImplCopyWith(
          _$CostItemImpl value, $Res Function(_$CostItemImpl) then) =
      __$$CostItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String label, int amountBDT, String category});
}

/// @nodoc
class __$$CostItemImplCopyWithImpl<$Res>
    extends _$CostItemCopyWithImpl<$Res, _$CostItemImpl>
    implements _$$CostItemImplCopyWith<$Res> {
  __$$CostItemImplCopyWithImpl(
      _$CostItemImpl _value, $Res Function(_$CostItemImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? label = null,
    Object? amountBDT = null,
    Object? category = null,
  }) {
    return _then(_$CostItemImpl(
      label: null == label
          ? _value.label
          : label // ignore: cast_nullable_to_non_nullable
              as String,
      amountBDT: null == amountBDT
          ? _value.amountBDT
          : amountBDT // ignore: cast_nullable_to_non_nullable
              as int,
      category: null == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CostItemImpl implements _CostItem {
  const _$CostItemImpl(
      {required this.label, required this.amountBDT, required this.category});

  factory _$CostItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$CostItemImplFromJson(json);

  @override
  final String label;
  @override
  final int amountBDT;
  @override
  final String category;

  @override
  String toString() {
    return 'CostItem(label: $label, amountBDT: $amountBDT, category: $category)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CostItemImpl &&
            (identical(other.label, label) || other.label == label) &&
            (identical(other.amountBDT, amountBDT) ||
                other.amountBDT == amountBDT) &&
            (identical(other.category, category) ||
                other.category == category));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, label, amountBDT, category);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CostItemImplCopyWith<_$CostItemImpl> get copyWith =>
      __$$CostItemImplCopyWithImpl<_$CostItemImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CostItemImplToJson(
      this,
    );
  }
}

abstract class _CostItem implements CostItem {
  const factory _CostItem(
      {required final String label,
      required final int amountBDT,
      required final String category}) = _$CostItemImpl;

  factory _CostItem.fromJson(Map<String, dynamic> json) =
      _$CostItemImpl.fromJson;

  @override
  String get label;
  @override
  int get amountBDT;
  @override
  String get category;
  @override
  @JsonKey(ignore: true)
  _$$CostItemImplCopyWith<_$CostItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
