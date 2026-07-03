import 'package:freezed_annotation/freezed_annotation.dart';

enum TrustTier {
  @JsonValue('unverified')
  unverified,
  @JsonValue('community')
  community,
  @JsonValue('verified')
  verified,
  @JsonValue('regionExpert')
  regionExpert,
  @JsonValue('pioneer')
  pioneer;

  String get displayName => switch (this) {
    TrustTier.unverified  => 'New Explorer',
    TrustTier.community   => 'Community Explorer',
    TrustTier.verified    => 'Verified Explorer',
    TrustTier.regionExpert => 'Region Expert',
    TrustTier.pioneer     => 'Pioneer',
  };

  /// Bengali display name for the Travel Diary identity system
  String get displayNameBn => switch (this) {
    TrustTier.unverified  => 'নতুন পথিক',
    TrustTier.community   => 'সহযাত্রী',
    TrustTier.verified    => 'বিশ্বস্ত গাইড',
    TrustTier.regionExpert => 'স্থানীয় বিশেষজ্ঞ',
    TrustTier.pioneer     => 'অগ্রদূত',
  };

  double get numericWeight => switch (this) {
    TrustTier.unverified => 0.5,
    TrustTier.community => 0.7,
    TrustTier.verified => 1.0,
    TrustTier.regionExpert => 1.2,
    TrustTier.pioneer => 1.3,
  };

  bool get isVerifiedOrAbove => 
      this == TrustTier.verified || 
      this == TrustTier.regionExpert || 
      this == TrustTier.pioneer;
}
