// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CardView {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CardView);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CardView()';
}


}

/// @nodoc
class $CardViewCopyWith<$Res>  {
$CardViewCopyWith(CardView _, $Res Function(CardView) __);
}


/// Adds pattern-matching-related methods to [CardView].
extension CardViewPatterns on CardView {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CardView_Track value)?  track,TResult Function( CardView_Collection value)?  collection,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CardView_Track() when track != null:
return track(_that);case CardView_Collection() when collection != null:
return collection(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CardView_Track value)  track,required TResult Function( CardView_Collection value)  collection,}){
final _that = this;
switch (_that) {
case CardView_Track():
return track(_that);case CardView_Collection():
return collection(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CardView_Track value)?  track,TResult? Function( CardView_Collection value)?  collection,}){
final _that = this;
switch (_that) {
case CardView_Track() when track != null:
return track(_that);case CardView_Collection() when collection != null:
return collection(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( TrackView track,  String? reason)?  track,TResult Function( CollectionView field0)?  collection,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CardView_Track() when track != null:
return track(_that.track,_that.reason);case CardView_Collection() when collection != null:
return collection(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( TrackView track,  String? reason)  track,required TResult Function( CollectionView field0)  collection,}) {final _that = this;
switch (_that) {
case CardView_Track():
return track(_that.track,_that.reason);case CardView_Collection():
return collection(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( TrackView track,  String? reason)?  track,TResult? Function( CollectionView field0)?  collection,}) {final _that = this;
switch (_that) {
case CardView_Track() when track != null:
return track(_that.track,_that.reason);case CardView_Collection() when collection != null:
return collection(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class CardView_Track extends CardView {
  const CardView_Track({required this.track, this.reason}): super._();
  

 final  TrackView track;
 final  String? reason;

/// Create a copy of CardView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CardView_TrackCopyWith<CardView_Track> get copyWith => _$CardView_TrackCopyWithImpl<CardView_Track>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CardView_Track&&(identical(other.track, track) || other.track == track)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,track,reason);
}

@override
String toString() {
    return 'CardView.track(track: $track, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $CardView_TrackCopyWith<$Res> implements $CardViewCopyWith<$Res> {
  factory $CardView_TrackCopyWith(CardView_Track value, $Res Function(CardView_Track) _then) = _$CardView_TrackCopyWithImpl;
@useResult
$Res call({
 TrackView track, String? reason
});




}
/// @nodoc
class _$CardView_TrackCopyWithImpl<$Res>
    implements $CardView_TrackCopyWith<$Res> {
  _$CardView_TrackCopyWithImpl(this._self, this._then);

  final CardView_Track _self;
  final $Res Function(CardView_Track) _then;

/// Create a copy of CardView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? track = null,Object? reason = freezed,}) {
  return _then(CardView_Track(
track: null == track ? _self.track : track // ignore: cast_nullable_to_non_nullable
as TrackView,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class CardView_Collection extends CardView {
  const CardView_Collection(this.field0): super._();
  

 final  CollectionView field0;

/// Create a copy of CardView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CardView_CollectionCopyWith<CardView_Collection> get copyWith => _$CardView_CollectionCopyWithImpl<CardView_Collection>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CardView_Collection&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'CardView.collection(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $CardView_CollectionCopyWith<$Res> implements $CardViewCopyWith<$Res> {
  factory $CardView_CollectionCopyWith(CardView_Collection value, $Res Function(CardView_Collection) _then) = _$CardView_CollectionCopyWithImpl;
@useResult
$Res call({
 CollectionView field0
});




}
/// @nodoc
class _$CardView_CollectionCopyWithImpl<$Res>
    implements $CardView_CollectionCopyWith<$Res> {
  _$CardView_CollectionCopyWithImpl(this._self, this._then);

  final CardView_Collection _self;
  final $Res Function(CardView_Collection) _then;

/// Create a copy of CardView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(CardView_Collection(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as CollectionView,
  ));
}


}

// dart format on
