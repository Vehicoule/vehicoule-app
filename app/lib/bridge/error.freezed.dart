// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CoreError {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError()';
}


}

/// @nodoc
class $CoreErrorCopyWith<$Res>  {
$CoreErrorCopyWith(CoreError _, $Res Function(CoreError) __);
}


/// Adds pattern-matching-related methods to [CoreError].
extension CoreErrorPatterns on CoreError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CoreError_Network value)?  network,TResult Function( CoreError_ProviderWall value)?  providerWall,TResult Function( CoreError_RateLimited value)?  rateLimited,TResult Function( CoreError_BudgetExceeded value)?  budgetExceeded,TResult Function( CoreError_NotFound value)?  notFound,TResult Function( CoreError_Expired value)?  expired,TResult Function( CoreError_Internal value)?  internal,TResult Function( CoreError_Offline value)?  offline,TResult Function( CoreError_InvalidFeed value)?  invalidFeed,TResult Function( CoreError_NoPlugin value)?  noPlugin,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CoreError_Network() when network != null:
return network(_that);case CoreError_ProviderWall() when providerWall != null:
return providerWall(_that);case CoreError_RateLimited() when rateLimited != null:
return rateLimited(_that);case CoreError_BudgetExceeded() when budgetExceeded != null:
return budgetExceeded(_that);case CoreError_NotFound() when notFound != null:
return notFound(_that);case CoreError_Expired() when expired != null:
return expired(_that);case CoreError_Internal() when internal != null:
return internal(_that);case CoreError_Offline() when offline != null:
return offline(_that);case CoreError_InvalidFeed() when invalidFeed != null:
return invalidFeed(_that);case CoreError_NoPlugin() when noPlugin != null:
return noPlugin(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CoreError_Network value)  network,required TResult Function( CoreError_ProviderWall value)  providerWall,required TResult Function( CoreError_RateLimited value)  rateLimited,required TResult Function( CoreError_BudgetExceeded value)  budgetExceeded,required TResult Function( CoreError_NotFound value)  notFound,required TResult Function( CoreError_Expired value)  expired,required TResult Function( CoreError_Internal value)  internal,required TResult Function( CoreError_Offline value)  offline,required TResult Function( CoreError_InvalidFeed value)  invalidFeed,required TResult Function( CoreError_NoPlugin value)  noPlugin,}){
final _that = this;
switch (_that) {
case CoreError_Network():
return network(_that);case CoreError_ProviderWall():
return providerWall(_that);case CoreError_RateLimited():
return rateLimited(_that);case CoreError_BudgetExceeded():
return budgetExceeded(_that);case CoreError_NotFound():
return notFound(_that);case CoreError_Expired():
return expired(_that);case CoreError_Internal():
return internal(_that);case CoreError_Offline():
return offline(_that);case CoreError_InvalidFeed():
return invalidFeed(_that);case CoreError_NoPlugin():
return noPlugin(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CoreError_Network value)?  network,TResult? Function( CoreError_ProviderWall value)?  providerWall,TResult? Function( CoreError_RateLimited value)?  rateLimited,TResult? Function( CoreError_BudgetExceeded value)?  budgetExceeded,TResult? Function( CoreError_NotFound value)?  notFound,TResult? Function( CoreError_Expired value)?  expired,TResult? Function( CoreError_Internal value)?  internal,TResult? Function( CoreError_Offline value)?  offline,TResult? Function( CoreError_InvalidFeed value)?  invalidFeed,TResult? Function( CoreError_NoPlugin value)?  noPlugin,}){
final _that = this;
switch (_that) {
case CoreError_Network() when network != null:
return network(_that);case CoreError_ProviderWall() when providerWall != null:
return providerWall(_that);case CoreError_RateLimited() when rateLimited != null:
return rateLimited(_that);case CoreError_BudgetExceeded() when budgetExceeded != null:
return budgetExceeded(_that);case CoreError_NotFound() when notFound != null:
return notFound(_that);case CoreError_Expired() when expired != null:
return expired(_that);case CoreError_Internal() when internal != null:
return internal(_that);case CoreError_Offline() when offline != null:
return offline(_that);case CoreError_InvalidFeed() when invalidFeed != null:
return invalidFeed(_that);case CoreError_NoPlugin() when noPlugin != null:
return noPlugin(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  network,TResult Function()?  providerWall,TResult Function()?  rateLimited,TResult Function()?  budgetExceeded,TResult Function()?  notFound,TResult Function()?  expired,TResult Function( String field0)?  internal,TResult Function()?  offline,TResult Function()?  invalidFeed,TResult Function( Capability field0)?  noPlugin,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CoreError_Network() when network != null:
return network();case CoreError_ProviderWall() when providerWall != null:
return providerWall();case CoreError_RateLimited() when rateLimited != null:
return rateLimited();case CoreError_BudgetExceeded() when budgetExceeded != null:
return budgetExceeded();case CoreError_NotFound() when notFound != null:
return notFound();case CoreError_Expired() when expired != null:
return expired();case CoreError_Internal() when internal != null:
return internal(_that.field0);case CoreError_Offline() when offline != null:
return offline();case CoreError_InvalidFeed() when invalidFeed != null:
return invalidFeed();case CoreError_NoPlugin() when noPlugin != null:
return noPlugin(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  network,required TResult Function()  providerWall,required TResult Function()  rateLimited,required TResult Function()  budgetExceeded,required TResult Function()  notFound,required TResult Function()  expired,required TResult Function( String field0)  internal,required TResult Function()  offline,required TResult Function()  invalidFeed,required TResult Function( Capability field0)  noPlugin,}) {final _that = this;
switch (_that) {
case CoreError_Network():
return network();case CoreError_ProviderWall():
return providerWall();case CoreError_RateLimited():
return rateLimited();case CoreError_BudgetExceeded():
return budgetExceeded();case CoreError_NotFound():
return notFound();case CoreError_Expired():
return expired();case CoreError_Internal():
return internal(_that.field0);case CoreError_Offline():
return offline();case CoreError_InvalidFeed():
return invalidFeed();case CoreError_NoPlugin():
return noPlugin(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  network,TResult? Function()?  providerWall,TResult? Function()?  rateLimited,TResult? Function()?  budgetExceeded,TResult? Function()?  notFound,TResult? Function()?  expired,TResult? Function( String field0)?  internal,TResult? Function()?  offline,TResult? Function()?  invalidFeed,TResult? Function( Capability field0)?  noPlugin,}) {final _that = this;
switch (_that) {
case CoreError_Network() when network != null:
return network();case CoreError_ProviderWall() when providerWall != null:
return providerWall();case CoreError_RateLimited() when rateLimited != null:
return rateLimited();case CoreError_BudgetExceeded() when budgetExceeded != null:
return budgetExceeded();case CoreError_NotFound() when notFound != null:
return notFound();case CoreError_Expired() when expired != null:
return expired();case CoreError_Internal() when internal != null:
return internal(_that.field0);case CoreError_Offline() when offline != null:
return offline();case CoreError_InvalidFeed() when invalidFeed != null:
return invalidFeed();case CoreError_NoPlugin() when noPlugin != null:
return noPlugin(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class CoreError_Network extends CoreError {
  const CoreError_Network(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Network);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError.network()';
}


}




/// @nodoc


class CoreError_ProviderWall extends CoreError {
  const CoreError_ProviderWall(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_ProviderWall);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError.providerWall()';
}


}




/// @nodoc


class CoreError_RateLimited extends CoreError {
  const CoreError_RateLimited(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_RateLimited);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError.rateLimited()';
}


}




/// @nodoc


class CoreError_BudgetExceeded extends CoreError {
  const CoreError_BudgetExceeded(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_BudgetExceeded);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError.budgetExceeded()';
}


}




/// @nodoc


class CoreError_NotFound extends CoreError {
  const CoreError_NotFound(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_NotFound);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError.notFound()';
}


}




/// @nodoc


class CoreError_Expired extends CoreError {
  const CoreError_Expired(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Expired);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError.expired()';
}


}




/// @nodoc


class CoreError_Internal extends CoreError {
  const CoreError_Internal(this.field0): super._();
  

 final  String field0;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_InternalCopyWith<CoreError_Internal> get copyWith => _$CoreError_InternalCopyWithImpl<CoreError_Internal>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Internal&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'CoreError.internal(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $CoreError_InternalCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_InternalCopyWith(CoreError_Internal value, $Res Function(CoreError_Internal) _then) = _$CoreError_InternalCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$CoreError_InternalCopyWithImpl<$Res>
    implements $CoreError_InternalCopyWith<$Res> {
  _$CoreError_InternalCopyWithImpl(this._self, this._then);

  final CoreError_Internal _self;
  final $Res Function(CoreError_Internal) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(CoreError_Internal(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CoreError_Offline extends CoreError {
  const CoreError_Offline(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_Offline);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError.offline()';
}


}




/// @nodoc


class CoreError_InvalidFeed extends CoreError {
  const CoreError_InvalidFeed(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_InvalidFeed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'CoreError.invalidFeed()';
}


}




/// @nodoc


class CoreError_NoPlugin extends CoreError {
  const CoreError_NoPlugin(this.field0): super._();
  

 final  Capability field0;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoreError_NoPluginCopyWith<CoreError_NoPlugin> get copyWith => _$CoreError_NoPluginCopyWithImpl<CoreError_NoPlugin>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoreError_NoPlugin&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'CoreError.noPlugin(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $CoreError_NoPluginCopyWith<$Res> implements $CoreErrorCopyWith<$Res> {
  factory $CoreError_NoPluginCopyWith(CoreError_NoPlugin value, $Res Function(CoreError_NoPlugin) _then) = _$CoreError_NoPluginCopyWithImpl;
@useResult
$Res call({
 Capability field0
});




}
/// @nodoc
class _$CoreError_NoPluginCopyWithImpl<$Res>
    implements $CoreError_NoPluginCopyWith<$Res> {
  _$CoreError_NoPluginCopyWithImpl(this._self, this._then);

  final CoreError_NoPlugin _self;
  final $Res Function(CoreError_NoPlugin) _then;

/// Create a copy of CoreError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(CoreError_NoPlugin(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as Capability,
  ));
}


}

// dart format on
