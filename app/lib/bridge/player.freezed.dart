// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'player.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlayerCommand {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerCommand);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PlayerCommand()';
}


}

/// @nodoc
class $PlayerCommandCopyWith<$Res>  {
$PlayerCommandCopyWith(PlayerCommand _, $Res Function(PlayerCommand) __);
}


/// Adds pattern-matching-related methods to [PlayerCommand].
extension PlayerCommandPatterns on PlayerCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PlayerCommand_Play value)?  play,TResult Function( PlayerCommand_EnqueueNext value)?  enqueueNext,TResult Function( PlayerCommand_ReplaceNext value)?  replaceNext,TResult Function( PlayerCommand_ClearNext value)?  clearNext,TResult Function( PlayerCommand_Stop value)?  stop,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PlayerCommand_Play() when play != null:
return play(_that);case PlayerCommand_EnqueueNext() when enqueueNext != null:
return enqueueNext(_that);case PlayerCommand_ReplaceNext() when replaceNext != null:
return replaceNext(_that);case PlayerCommand_ClearNext() when clearNext != null:
return clearNext(_that);case PlayerCommand_Stop() when stop != null:
return stop(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PlayerCommand_Play value)  play,required TResult Function( PlayerCommand_EnqueueNext value)  enqueueNext,required TResult Function( PlayerCommand_ReplaceNext value)  replaceNext,required TResult Function( PlayerCommand_ClearNext value)  clearNext,required TResult Function( PlayerCommand_Stop value)  stop,}){
final _that = this;
switch (_that) {
case PlayerCommand_Play():
return play(_that);case PlayerCommand_EnqueueNext():
return enqueueNext(_that);case PlayerCommand_ReplaceNext():
return replaceNext(_that);case PlayerCommand_ClearNext():
return clearNext(_that);case PlayerCommand_Stop():
return stop(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PlayerCommand_Play value)?  play,TResult? Function( PlayerCommand_EnqueueNext value)?  enqueueNext,TResult? Function( PlayerCommand_ReplaceNext value)?  replaceNext,TResult? Function( PlayerCommand_ClearNext value)?  clearNext,TResult? Function( PlayerCommand_Stop value)?  stop,}){
final _that = this;
switch (_that) {
case PlayerCommand_Play() when play != null:
return play(_that);case PlayerCommand_EnqueueNext() when enqueueNext != null:
return enqueueNext(_that);case PlayerCommand_ReplaceNext() when replaceNext != null:
return replaceNext(_that);case PlayerCommand_ClearNext() when clearNext != null:
return clearNext(_that);case PlayerCommand_Stop() when stop != null:
return stop(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String entry,  Source source,  BigInt positionMs,  bool autoplay,  double gainDb)?  play,TResult Function( String entry,  Source source,  double gainDb)?  enqueueNext,TResult Function( String entry,  Source source,  double gainDb)?  replaceNext,TResult Function()?  clearNext,TResult Function()?  stop,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PlayerCommand_Play() when play != null:
return play(_that.entry,_that.source,_that.positionMs,_that.autoplay,_that.gainDb);case PlayerCommand_EnqueueNext() when enqueueNext != null:
return enqueueNext(_that.entry,_that.source,_that.gainDb);case PlayerCommand_ReplaceNext() when replaceNext != null:
return replaceNext(_that.entry,_that.source,_that.gainDb);case PlayerCommand_ClearNext() when clearNext != null:
return clearNext();case PlayerCommand_Stop() when stop != null:
return stop();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String entry,  Source source,  BigInt positionMs,  bool autoplay,  double gainDb)  play,required TResult Function( String entry,  Source source,  double gainDb)  enqueueNext,required TResult Function( String entry,  Source source,  double gainDb)  replaceNext,required TResult Function()  clearNext,required TResult Function()  stop,}) {final _that = this;
switch (_that) {
case PlayerCommand_Play():
return play(_that.entry,_that.source,_that.positionMs,_that.autoplay,_that.gainDb);case PlayerCommand_EnqueueNext():
return enqueueNext(_that.entry,_that.source,_that.gainDb);case PlayerCommand_ReplaceNext():
return replaceNext(_that.entry,_that.source,_that.gainDb);case PlayerCommand_ClearNext():
return clearNext();case PlayerCommand_Stop():
return stop();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String entry,  Source source,  BigInt positionMs,  bool autoplay,  double gainDb)?  play,TResult? Function( String entry,  Source source,  double gainDb)?  enqueueNext,TResult? Function( String entry,  Source source,  double gainDb)?  replaceNext,TResult? Function()?  clearNext,TResult? Function()?  stop,}) {final _that = this;
switch (_that) {
case PlayerCommand_Play() when play != null:
return play(_that.entry,_that.source,_that.positionMs,_that.autoplay,_that.gainDb);case PlayerCommand_EnqueueNext() when enqueueNext != null:
return enqueueNext(_that.entry,_that.source,_that.gainDb);case PlayerCommand_ReplaceNext() when replaceNext != null:
return replaceNext(_that.entry,_that.source,_that.gainDb);case PlayerCommand_ClearNext() when clearNext != null:
return clearNext();case PlayerCommand_Stop() when stop != null:
return stop();case _:
  return null;

}
}

}

/// @nodoc


class PlayerCommand_Play extends PlayerCommand {
  const PlayerCommand_Play({required this.entry, required this.source, required this.positionMs, required this.autoplay, required this.gainDb}): super._();
  

 final  String entry;
 final  Source source;
 final  BigInt positionMs;
 final  bool autoplay;
 final  double gainDb;

/// Create a copy of PlayerCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerCommand_PlayCopyWith<PlayerCommand_Play> get copyWith => _$PlayerCommand_PlayCopyWithImpl<PlayerCommand_Play>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerCommand_Play&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.source, source) || other.source == source)&&(identical(other.positionMs, positionMs) || other.positionMs == positionMs)&&(identical(other.autoplay, autoplay) || other.autoplay == autoplay)&&(identical(other.gainDb, gainDb) || other.gainDb == gainDb));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,source,positionMs,autoplay,gainDb);
}

@override
String toString() {
    return 'PlayerCommand.play(entry: $entry, source: $source, positionMs: $positionMs, autoplay: $autoplay, gainDb: $gainDb)';
}


}

/// @nodoc
abstract mixin class $PlayerCommand_PlayCopyWith<$Res> implements $PlayerCommandCopyWith<$Res> {
  factory $PlayerCommand_PlayCopyWith(PlayerCommand_Play value, $Res Function(PlayerCommand_Play) _then) = _$PlayerCommand_PlayCopyWithImpl;
@useResult
$Res call({
 String entry, Source source, BigInt positionMs, bool autoplay, double gainDb
});




}
/// @nodoc
class _$PlayerCommand_PlayCopyWithImpl<$Res>
    implements $PlayerCommand_PlayCopyWith<$Res> {
  _$PlayerCommand_PlayCopyWithImpl(this._self, this._then);

  final PlayerCommand_Play _self;
  final $Res Function(PlayerCommand_Play) _then;

/// Create a copy of PlayerCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? source = null,Object? positionMs = null,Object? autoplay = null,Object? gainDb = null,}) {
  return _then(PlayerCommand_Play(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as Source,positionMs: null == positionMs ? _self.positionMs : positionMs // ignore: cast_nullable_to_non_nullable
as BigInt,autoplay: null == autoplay ? _self.autoplay : autoplay // ignore: cast_nullable_to_non_nullable
as bool,gainDb: null == gainDb ? _self.gainDb : gainDb // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class PlayerCommand_EnqueueNext extends PlayerCommand {
  const PlayerCommand_EnqueueNext({required this.entry, required this.source, required this.gainDb}): super._();
  

 final  String entry;
 final  Source source;
 final  double gainDb;

/// Create a copy of PlayerCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerCommand_EnqueueNextCopyWith<PlayerCommand_EnqueueNext> get copyWith => _$PlayerCommand_EnqueueNextCopyWithImpl<PlayerCommand_EnqueueNext>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerCommand_EnqueueNext&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.source, source) || other.source == source)&&(identical(other.gainDb, gainDb) || other.gainDb == gainDb));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,source,gainDb);
}

@override
String toString() {
    return 'PlayerCommand.enqueueNext(entry: $entry, source: $source, gainDb: $gainDb)';
}


}

/// @nodoc
abstract mixin class $PlayerCommand_EnqueueNextCopyWith<$Res> implements $PlayerCommandCopyWith<$Res> {
  factory $PlayerCommand_EnqueueNextCopyWith(PlayerCommand_EnqueueNext value, $Res Function(PlayerCommand_EnqueueNext) _then) = _$PlayerCommand_EnqueueNextCopyWithImpl;
@useResult
$Res call({
 String entry, Source source, double gainDb
});




}
/// @nodoc
class _$PlayerCommand_EnqueueNextCopyWithImpl<$Res>
    implements $PlayerCommand_EnqueueNextCopyWith<$Res> {
  _$PlayerCommand_EnqueueNextCopyWithImpl(this._self, this._then);

  final PlayerCommand_EnqueueNext _self;
  final $Res Function(PlayerCommand_EnqueueNext) _then;

/// Create a copy of PlayerCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? source = null,Object? gainDb = null,}) {
  return _then(PlayerCommand_EnqueueNext(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as Source,gainDb: null == gainDb ? _self.gainDb : gainDb // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class PlayerCommand_ReplaceNext extends PlayerCommand {
  const PlayerCommand_ReplaceNext({required this.entry, required this.source, required this.gainDb}): super._();
  

 final  String entry;
 final  Source source;
 final  double gainDb;

/// Create a copy of PlayerCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerCommand_ReplaceNextCopyWith<PlayerCommand_ReplaceNext> get copyWith => _$PlayerCommand_ReplaceNextCopyWithImpl<PlayerCommand_ReplaceNext>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerCommand_ReplaceNext&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.source, source) || other.source == source)&&(identical(other.gainDb, gainDb) || other.gainDb == gainDb));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,source,gainDb);
}

@override
String toString() {
    return 'PlayerCommand.replaceNext(entry: $entry, source: $source, gainDb: $gainDb)';
}


}

/// @nodoc
abstract mixin class $PlayerCommand_ReplaceNextCopyWith<$Res> implements $PlayerCommandCopyWith<$Res> {
  factory $PlayerCommand_ReplaceNextCopyWith(PlayerCommand_ReplaceNext value, $Res Function(PlayerCommand_ReplaceNext) _then) = _$PlayerCommand_ReplaceNextCopyWithImpl;
@useResult
$Res call({
 String entry, Source source, double gainDb
});




}
/// @nodoc
class _$PlayerCommand_ReplaceNextCopyWithImpl<$Res>
    implements $PlayerCommand_ReplaceNextCopyWith<$Res> {
  _$PlayerCommand_ReplaceNextCopyWithImpl(this._self, this._then);

  final PlayerCommand_ReplaceNext _self;
  final $Res Function(PlayerCommand_ReplaceNext) _then;

/// Create a copy of PlayerCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? source = null,Object? gainDb = null,}) {
  return _then(PlayerCommand_ReplaceNext(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as Source,gainDb: null == gainDb ? _self.gainDb : gainDb // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class PlayerCommand_ClearNext extends PlayerCommand {
  const PlayerCommand_ClearNext(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerCommand_ClearNext);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PlayerCommand.clearNext()';
}


}




/// @nodoc


class PlayerCommand_Stop extends PlayerCommand {
  const PlayerCommand_Stop(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerCommand_Stop);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PlayerCommand.stop()';
}


}




/// @nodoc
mixin _$PlayerEvent {

 String get entry;
/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEventCopyWith<PlayerEvent> get copyWith => _$PlayerEventCopyWithImpl<PlayerEvent>(this as PlayerEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PlayerEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent&&(identical(other.entry, _this.entry) || other.entry == _this.entry));
}


@override
int get hashCode {
  final _this = this as PlayerEvent;
  return Object.hash(runtimeType,_this.entry);
}

@override
String toString() {
  final _this = this as PlayerEvent;
  return 'PlayerEvent(entry: ${_this.entry})';
}


}

/// @nodoc
abstract mixin class $PlayerEventCopyWith<$Res>  {
  factory $PlayerEventCopyWith(PlayerEvent value, $Res Function(PlayerEvent) _then) = _$PlayerEventCopyWithImpl;
@useResult
$Res call({
 String entry
});




}
/// @nodoc
class _$PlayerEventCopyWithImpl<$Res>
    implements $PlayerEventCopyWith<$Res> {
  _$PlayerEventCopyWithImpl(this._self, this._then);

  final PlayerEvent _self;
  final $Res Function(PlayerEvent) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,}) {
  return _then(_self.copyWith(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PlayerEvent].
extension PlayerEventPatterns on PlayerEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PlayerEvent_TrackStarted value)?  trackStarted,TResult Function( PlayerEvent_Duration value)?  duration,TResult Function( PlayerEvent_Position value)?  position,TResult Function( PlayerEvent_Paused value)?  paused,TResult Function( PlayerEvent_Resumed value)?  resumed,TResult Function( PlayerEvent_Seeked value)?  seeked,TResult Function( PlayerEvent_Ended value)?  ended,TResult Function( PlayerEvent_Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted() when trackStarted != null:
return trackStarted(_that);case PlayerEvent_Duration() when duration != null:
return duration(_that);case PlayerEvent_Position() when position != null:
return position(_that);case PlayerEvent_Paused() when paused != null:
return paused(_that);case PlayerEvent_Resumed() when resumed != null:
return resumed(_that);case PlayerEvent_Seeked() when seeked != null:
return seeked(_that);case PlayerEvent_Ended() when ended != null:
return ended(_that);case PlayerEvent_Error() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PlayerEvent_TrackStarted value)  trackStarted,required TResult Function( PlayerEvent_Duration value)  duration,required TResult Function( PlayerEvent_Position value)  position,required TResult Function( PlayerEvent_Paused value)  paused,required TResult Function( PlayerEvent_Resumed value)  resumed,required TResult Function( PlayerEvent_Seeked value)  seeked,required TResult Function( PlayerEvent_Ended value)  ended,required TResult Function( PlayerEvent_Error value)  error,}){
final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted():
return trackStarted(_that);case PlayerEvent_Duration():
return duration(_that);case PlayerEvent_Position():
return position(_that);case PlayerEvent_Paused():
return paused(_that);case PlayerEvent_Resumed():
return resumed(_that);case PlayerEvent_Seeked():
return seeked(_that);case PlayerEvent_Ended():
return ended(_that);case PlayerEvent_Error():
return error(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PlayerEvent_TrackStarted value)?  trackStarted,TResult? Function( PlayerEvent_Duration value)?  duration,TResult? Function( PlayerEvent_Position value)?  position,TResult? Function( PlayerEvent_Paused value)?  paused,TResult? Function( PlayerEvent_Resumed value)?  resumed,TResult? Function( PlayerEvent_Seeked value)?  seeked,TResult? Function( PlayerEvent_Ended value)?  ended,TResult? Function( PlayerEvent_Error value)?  error,}){
final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted() when trackStarted != null:
return trackStarted(_that);case PlayerEvent_Duration() when duration != null:
return duration(_that);case PlayerEvent_Position() when position != null:
return position(_that);case PlayerEvent_Paused() when paused != null:
return paused(_that);case PlayerEvent_Resumed() when resumed != null:
return resumed(_that);case PlayerEvent_Seeked() when seeked != null:
return seeked(_that);case PlayerEvent_Ended() when ended != null:
return ended(_that);case PlayerEvent_Error() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String entry)?  trackStarted,TResult Function( String entry,  BigInt ms)?  duration,TResult Function( String entry,  BigInt ms)?  position,TResult Function( String entry,  BigInt ms)?  paused,TResult Function( String entry)?  resumed,TResult Function( String entry,  BigInt ms)?  seeked,TResult Function( String entry)?  ended,TResult Function( String entry,  PlayerErrorKind kind,  String message)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted() when trackStarted != null:
return trackStarted(_that.entry);case PlayerEvent_Duration() when duration != null:
return duration(_that.entry,_that.ms);case PlayerEvent_Position() when position != null:
return position(_that.entry,_that.ms);case PlayerEvent_Paused() when paused != null:
return paused(_that.entry,_that.ms);case PlayerEvent_Resumed() when resumed != null:
return resumed(_that.entry);case PlayerEvent_Seeked() when seeked != null:
return seeked(_that.entry,_that.ms);case PlayerEvent_Ended() when ended != null:
return ended(_that.entry);case PlayerEvent_Error() when error != null:
return error(_that.entry,_that.kind,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String entry)  trackStarted,required TResult Function( String entry,  BigInt ms)  duration,required TResult Function( String entry,  BigInt ms)  position,required TResult Function( String entry,  BigInt ms)  paused,required TResult Function( String entry)  resumed,required TResult Function( String entry,  BigInt ms)  seeked,required TResult Function( String entry)  ended,required TResult Function( String entry,  PlayerErrorKind kind,  String message)  error,}) {final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted():
return trackStarted(_that.entry);case PlayerEvent_Duration():
return duration(_that.entry,_that.ms);case PlayerEvent_Position():
return position(_that.entry,_that.ms);case PlayerEvent_Paused():
return paused(_that.entry,_that.ms);case PlayerEvent_Resumed():
return resumed(_that.entry);case PlayerEvent_Seeked():
return seeked(_that.entry,_that.ms);case PlayerEvent_Ended():
return ended(_that.entry);case PlayerEvent_Error():
return error(_that.entry,_that.kind,_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String entry)?  trackStarted,TResult? Function( String entry,  BigInt ms)?  duration,TResult? Function( String entry,  BigInt ms)?  position,TResult? Function( String entry,  BigInt ms)?  paused,TResult? Function( String entry)?  resumed,TResult? Function( String entry,  BigInt ms)?  seeked,TResult? Function( String entry)?  ended,TResult? Function( String entry,  PlayerErrorKind kind,  String message)?  error,}) {final _that = this;
switch (_that) {
case PlayerEvent_TrackStarted() when trackStarted != null:
return trackStarted(_that.entry);case PlayerEvent_Duration() when duration != null:
return duration(_that.entry,_that.ms);case PlayerEvent_Position() when position != null:
return position(_that.entry,_that.ms);case PlayerEvent_Paused() when paused != null:
return paused(_that.entry,_that.ms);case PlayerEvent_Resumed() when resumed != null:
return resumed(_that.entry);case PlayerEvent_Seeked() when seeked != null:
return seeked(_that.entry,_that.ms);case PlayerEvent_Ended() when ended != null:
return ended(_that.entry);case PlayerEvent_Error() when error != null:
return error(_that.entry,_that.kind,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class PlayerEvent_TrackStarted extends PlayerEvent {
  const PlayerEvent_TrackStarted({required this.entry}): super._();
  

@override final  String entry;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_TrackStartedCopyWith<PlayerEvent_TrackStarted> get copyWith => _$PlayerEvent_TrackStartedCopyWithImpl<PlayerEvent_TrackStarted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_TrackStarted&&(identical(other.entry, entry) || other.entry == entry));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry);
}

@override
String toString() {
    return 'PlayerEvent.trackStarted(entry: $entry)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_TrackStartedCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_TrackStartedCopyWith(PlayerEvent_TrackStarted value, $Res Function(PlayerEvent_TrackStarted) _then) = _$PlayerEvent_TrackStartedCopyWithImpl;
@override @useResult
$Res call({
 String entry
});




}
/// @nodoc
class _$PlayerEvent_TrackStartedCopyWithImpl<$Res>
    implements $PlayerEvent_TrackStartedCopyWith<$Res> {
  _$PlayerEvent_TrackStartedCopyWithImpl(this._self, this._then);

  final PlayerEvent_TrackStarted _self;
  final $Res Function(PlayerEvent_TrackStarted) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,}) {
  return _then(PlayerEvent_TrackStarted(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PlayerEvent_Duration extends PlayerEvent {
  const PlayerEvent_Duration({required this.entry, required this.ms}): super._();
  

@override final  String entry;
 final  BigInt ms;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_DurationCopyWith<PlayerEvent_Duration> get copyWith => _$PlayerEvent_DurationCopyWithImpl<PlayerEvent_Duration>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_Duration&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.ms, ms) || other.ms == ms));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,ms);
}

@override
String toString() {
    return 'PlayerEvent.duration(entry: $entry, ms: $ms)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_DurationCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_DurationCopyWith(PlayerEvent_Duration value, $Res Function(PlayerEvent_Duration) _then) = _$PlayerEvent_DurationCopyWithImpl;
@override @useResult
$Res call({
 String entry, BigInt ms
});




}
/// @nodoc
class _$PlayerEvent_DurationCopyWithImpl<$Res>
    implements $PlayerEvent_DurationCopyWith<$Res> {
  _$PlayerEvent_DurationCopyWithImpl(this._self, this._then);

  final PlayerEvent_Duration _self;
  final $Res Function(PlayerEvent_Duration) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? ms = null,}) {
  return _then(PlayerEvent_Duration(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,ms: null == ms ? _self.ms : ms // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class PlayerEvent_Position extends PlayerEvent {
  const PlayerEvent_Position({required this.entry, required this.ms}): super._();
  

@override final  String entry;
 final  BigInt ms;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_PositionCopyWith<PlayerEvent_Position> get copyWith => _$PlayerEvent_PositionCopyWithImpl<PlayerEvent_Position>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_Position&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.ms, ms) || other.ms == ms));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,ms);
}

@override
String toString() {
    return 'PlayerEvent.position(entry: $entry, ms: $ms)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_PositionCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_PositionCopyWith(PlayerEvent_Position value, $Res Function(PlayerEvent_Position) _then) = _$PlayerEvent_PositionCopyWithImpl;
@override @useResult
$Res call({
 String entry, BigInt ms
});




}
/// @nodoc
class _$PlayerEvent_PositionCopyWithImpl<$Res>
    implements $PlayerEvent_PositionCopyWith<$Res> {
  _$PlayerEvent_PositionCopyWithImpl(this._self, this._then);

  final PlayerEvent_Position _self;
  final $Res Function(PlayerEvent_Position) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? ms = null,}) {
  return _then(PlayerEvent_Position(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,ms: null == ms ? _self.ms : ms // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class PlayerEvent_Paused extends PlayerEvent {
  const PlayerEvent_Paused({required this.entry, required this.ms}): super._();
  

@override final  String entry;
 final  BigInt ms;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_PausedCopyWith<PlayerEvent_Paused> get copyWith => _$PlayerEvent_PausedCopyWithImpl<PlayerEvent_Paused>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_Paused&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.ms, ms) || other.ms == ms));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,ms);
}

@override
String toString() {
    return 'PlayerEvent.paused(entry: $entry, ms: $ms)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_PausedCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_PausedCopyWith(PlayerEvent_Paused value, $Res Function(PlayerEvent_Paused) _then) = _$PlayerEvent_PausedCopyWithImpl;
@override @useResult
$Res call({
 String entry, BigInt ms
});




}
/// @nodoc
class _$PlayerEvent_PausedCopyWithImpl<$Res>
    implements $PlayerEvent_PausedCopyWith<$Res> {
  _$PlayerEvent_PausedCopyWithImpl(this._self, this._then);

  final PlayerEvent_Paused _self;
  final $Res Function(PlayerEvent_Paused) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? ms = null,}) {
  return _then(PlayerEvent_Paused(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,ms: null == ms ? _self.ms : ms // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class PlayerEvent_Resumed extends PlayerEvent {
  const PlayerEvent_Resumed({required this.entry}): super._();
  

@override final  String entry;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_ResumedCopyWith<PlayerEvent_Resumed> get copyWith => _$PlayerEvent_ResumedCopyWithImpl<PlayerEvent_Resumed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_Resumed&&(identical(other.entry, entry) || other.entry == entry));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry);
}

@override
String toString() {
    return 'PlayerEvent.resumed(entry: $entry)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_ResumedCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_ResumedCopyWith(PlayerEvent_Resumed value, $Res Function(PlayerEvent_Resumed) _then) = _$PlayerEvent_ResumedCopyWithImpl;
@override @useResult
$Res call({
 String entry
});




}
/// @nodoc
class _$PlayerEvent_ResumedCopyWithImpl<$Res>
    implements $PlayerEvent_ResumedCopyWith<$Res> {
  _$PlayerEvent_ResumedCopyWithImpl(this._self, this._then);

  final PlayerEvent_Resumed _self;
  final $Res Function(PlayerEvent_Resumed) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,}) {
  return _then(PlayerEvent_Resumed(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PlayerEvent_Seeked extends PlayerEvent {
  const PlayerEvent_Seeked({required this.entry, required this.ms}): super._();
  

@override final  String entry;
 final  BigInt ms;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_SeekedCopyWith<PlayerEvent_Seeked> get copyWith => _$PlayerEvent_SeekedCopyWithImpl<PlayerEvent_Seeked>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_Seeked&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.ms, ms) || other.ms == ms));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,ms);
}

@override
String toString() {
    return 'PlayerEvent.seeked(entry: $entry, ms: $ms)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_SeekedCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_SeekedCopyWith(PlayerEvent_Seeked value, $Res Function(PlayerEvent_Seeked) _then) = _$PlayerEvent_SeekedCopyWithImpl;
@override @useResult
$Res call({
 String entry, BigInt ms
});




}
/// @nodoc
class _$PlayerEvent_SeekedCopyWithImpl<$Res>
    implements $PlayerEvent_SeekedCopyWith<$Res> {
  _$PlayerEvent_SeekedCopyWithImpl(this._self, this._then);

  final PlayerEvent_Seeked _self;
  final $Res Function(PlayerEvent_Seeked) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? ms = null,}) {
  return _then(PlayerEvent_Seeked(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,ms: null == ms ? _self.ms : ms // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class PlayerEvent_Ended extends PlayerEvent {
  const PlayerEvent_Ended({required this.entry}): super._();
  

@override final  String entry;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_EndedCopyWith<PlayerEvent_Ended> get copyWith => _$PlayerEvent_EndedCopyWithImpl<PlayerEvent_Ended>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_Ended&&(identical(other.entry, entry) || other.entry == entry));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry);
}

@override
String toString() {
    return 'PlayerEvent.ended(entry: $entry)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_EndedCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_EndedCopyWith(PlayerEvent_Ended value, $Res Function(PlayerEvent_Ended) _then) = _$PlayerEvent_EndedCopyWithImpl;
@override @useResult
$Res call({
 String entry
});




}
/// @nodoc
class _$PlayerEvent_EndedCopyWithImpl<$Res>
    implements $PlayerEvent_EndedCopyWith<$Res> {
  _$PlayerEvent_EndedCopyWithImpl(this._self, this._then);

  final PlayerEvent_Ended _self;
  final $Res Function(PlayerEvent_Ended) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,}) {
  return _then(PlayerEvent_Ended(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class PlayerEvent_Error extends PlayerEvent {
  const PlayerEvent_Error({required this.entry, required this.kind, required this.message}): super._();
  

@override final  String entry;
 final  PlayerErrorKind kind;
 final  String message;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlayerEvent_ErrorCopyWith<PlayerEvent_Error> get copyWith => _$PlayerEvent_ErrorCopyWithImpl<PlayerEvent_Error>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlayerEvent_Error&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,kind,message);
}

@override
String toString() {
    return 'PlayerEvent.error(entry: $entry, kind: $kind, message: $message)';
}


}

/// @nodoc
abstract mixin class $PlayerEvent_ErrorCopyWith<$Res> implements $PlayerEventCopyWith<$Res> {
  factory $PlayerEvent_ErrorCopyWith(PlayerEvent_Error value, $Res Function(PlayerEvent_Error) _then) = _$PlayerEvent_ErrorCopyWithImpl;
@override @useResult
$Res call({
 String entry, PlayerErrorKind kind, String message
});




}
/// @nodoc
class _$PlayerEvent_ErrorCopyWithImpl<$Res>
    implements $PlayerEvent_ErrorCopyWith<$Res> {
  _$PlayerEvent_ErrorCopyWithImpl(this._self, this._then);

  final PlayerEvent_Error _self;
  final $Res Function(PlayerEvent_Error) _then;

/// Create a copy of PlayerEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? kind = null,Object? message = null,}) {
  return _then(PlayerEvent_Error(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as PlayerErrorKind,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$QueueOp {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueueOp);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QueueOp()';
}


}

/// @nodoc
class $QueueOpCopyWith<$Res>  {
$QueueOpCopyWith(QueueOp _, $Res Function(QueueOp) __);
}


/// Adds pattern-matching-related methods to [QueueOp].
extension QueueOpPatterns on QueueOp {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( QueueOp_EnqueueNext value)?  enqueueNext,TResult Function( QueueOp_EnqueueLast value)?  enqueueLast,TResult Function( QueueOp_Remove value)?  remove,TResult Function( QueueOp_Move value)?  move,TResult Function( QueueOp_Shuffle value)?  shuffle,TResult Function( QueueOp_Repeat value)?  repeat,TResult Function( QueueOp_JumpTo value)?  jumpTo,required TResult orElse(),}){
final _that = this;
switch (_that) {
case QueueOp_EnqueueNext() when enqueueNext != null:
return enqueueNext(_that);case QueueOp_EnqueueLast() when enqueueLast != null:
return enqueueLast(_that);case QueueOp_Remove() when remove != null:
return remove(_that);case QueueOp_Move() when move != null:
return move(_that);case QueueOp_Shuffle() when shuffle != null:
return shuffle(_that);case QueueOp_Repeat() when repeat != null:
return repeat(_that);case QueueOp_JumpTo() when jumpTo != null:
return jumpTo(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( QueueOp_EnqueueNext value)  enqueueNext,required TResult Function( QueueOp_EnqueueLast value)  enqueueLast,required TResult Function( QueueOp_Remove value)  remove,required TResult Function( QueueOp_Move value)  move,required TResult Function( QueueOp_Shuffle value)  shuffle,required TResult Function( QueueOp_Repeat value)  repeat,required TResult Function( QueueOp_JumpTo value)  jumpTo,}){
final _that = this;
switch (_that) {
case QueueOp_EnqueueNext():
return enqueueNext(_that);case QueueOp_EnqueueLast():
return enqueueLast(_that);case QueueOp_Remove():
return remove(_that);case QueueOp_Move():
return move(_that);case QueueOp_Shuffle():
return shuffle(_that);case QueueOp_Repeat():
return repeat(_that);case QueueOp_JumpTo():
return jumpTo(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( QueueOp_EnqueueNext value)?  enqueueNext,TResult? Function( QueueOp_EnqueueLast value)?  enqueueLast,TResult? Function( QueueOp_Remove value)?  remove,TResult? Function( QueueOp_Move value)?  move,TResult? Function( QueueOp_Shuffle value)?  shuffle,TResult? Function( QueueOp_Repeat value)?  repeat,TResult? Function( QueueOp_JumpTo value)?  jumpTo,}){
final _that = this;
switch (_that) {
case QueueOp_EnqueueNext() when enqueueNext != null:
return enqueueNext(_that);case QueueOp_EnqueueLast() when enqueueLast != null:
return enqueueLast(_that);case QueueOp_Remove() when remove != null:
return remove(_that);case QueueOp_Move() when move != null:
return move(_that);case QueueOp_Shuffle() when shuffle != null:
return shuffle(_that);case QueueOp_Repeat() when repeat != null:
return repeat(_that);case QueueOp_JumpTo() when jumpTo != null:
return jumpTo(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<String> field0)?  enqueueNext,TResult Function( List<String> field0)?  enqueueLast,TResult Function( String field0)?  remove,TResult Function( String entry,  int to)?  move,TResult Function( bool field0)?  shuffle,TResult Function( Repeat field0)?  repeat,TResult Function( String field0)?  jumpTo,required TResult orElse(),}) {final _that = this;
switch (_that) {
case QueueOp_EnqueueNext() when enqueueNext != null:
return enqueueNext(_that.field0);case QueueOp_EnqueueLast() when enqueueLast != null:
return enqueueLast(_that.field0);case QueueOp_Remove() when remove != null:
return remove(_that.field0);case QueueOp_Move() when move != null:
return move(_that.entry,_that.to);case QueueOp_Shuffle() when shuffle != null:
return shuffle(_that.field0);case QueueOp_Repeat() when repeat != null:
return repeat(_that.field0);case QueueOp_JumpTo() when jumpTo != null:
return jumpTo(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<String> field0)  enqueueNext,required TResult Function( List<String> field0)  enqueueLast,required TResult Function( String field0)  remove,required TResult Function( String entry,  int to)  move,required TResult Function( bool field0)  shuffle,required TResult Function( Repeat field0)  repeat,required TResult Function( String field0)  jumpTo,}) {final _that = this;
switch (_that) {
case QueueOp_EnqueueNext():
return enqueueNext(_that.field0);case QueueOp_EnqueueLast():
return enqueueLast(_that.field0);case QueueOp_Remove():
return remove(_that.field0);case QueueOp_Move():
return move(_that.entry,_that.to);case QueueOp_Shuffle():
return shuffle(_that.field0);case QueueOp_Repeat():
return repeat(_that.field0);case QueueOp_JumpTo():
return jumpTo(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<String> field0)?  enqueueNext,TResult? Function( List<String> field0)?  enqueueLast,TResult? Function( String field0)?  remove,TResult? Function( String entry,  int to)?  move,TResult? Function( bool field0)?  shuffle,TResult? Function( Repeat field0)?  repeat,TResult? Function( String field0)?  jumpTo,}) {final _that = this;
switch (_that) {
case QueueOp_EnqueueNext() when enqueueNext != null:
return enqueueNext(_that.field0);case QueueOp_EnqueueLast() when enqueueLast != null:
return enqueueLast(_that.field0);case QueueOp_Remove() when remove != null:
return remove(_that.field0);case QueueOp_Move() when move != null:
return move(_that.entry,_that.to);case QueueOp_Shuffle() when shuffle != null:
return shuffle(_that.field0);case QueueOp_Repeat() when repeat != null:
return repeat(_that.field0);case QueueOp_JumpTo() when jumpTo != null:
return jumpTo(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class QueueOp_EnqueueNext extends QueueOp {
  const QueueOp_EnqueueNext( List<String> field0): _field0 = field0,super._();
  

 final  List<String> _field0;
 List<String> get field0 {
  if (_field0 is EqualUnmodifiableListView) return _field0;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_field0);
}


/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueueOp_EnqueueNextCopyWith<QueueOp_EnqueueNext> get copyWith => _$QueueOp_EnqueueNextCopyWithImpl<QueueOp_EnqueueNext>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueueOp_EnqueueNext&&const DeepCollectionEquality().equals(other.field0, _field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_field0));
}

@override
String toString() {
    return 'QueueOp.enqueueNext(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $QueueOp_EnqueueNextCopyWith<$Res> implements $QueueOpCopyWith<$Res> {
  factory $QueueOp_EnqueueNextCopyWith(QueueOp_EnqueueNext value, $Res Function(QueueOp_EnqueueNext) _then) = _$QueueOp_EnqueueNextCopyWithImpl;
@useResult
$Res call({
 List<String> field0
});




}
/// @nodoc
class _$QueueOp_EnqueueNextCopyWithImpl<$Res>
    implements $QueueOp_EnqueueNextCopyWith<$Res> {
  _$QueueOp_EnqueueNextCopyWithImpl(this._self, this._then);

  final QueueOp_EnqueueNext _self;
  final $Res Function(QueueOp_EnqueueNext) _then;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(QueueOp_EnqueueNext(
null == field0 ? _self._field0 : field0 // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class QueueOp_EnqueueLast extends QueueOp {
  const QueueOp_EnqueueLast( List<String> field0): _field0 = field0,super._();
  

 final  List<String> _field0;
 List<String> get field0 {
  if (_field0 is EqualUnmodifiableListView) return _field0;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_field0);
}


/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueueOp_EnqueueLastCopyWith<QueueOp_EnqueueLast> get copyWith => _$QueueOp_EnqueueLastCopyWithImpl<QueueOp_EnqueueLast>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueueOp_EnqueueLast&&const DeepCollectionEquality().equals(other.field0, _field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_field0));
}

@override
String toString() {
    return 'QueueOp.enqueueLast(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $QueueOp_EnqueueLastCopyWith<$Res> implements $QueueOpCopyWith<$Res> {
  factory $QueueOp_EnqueueLastCopyWith(QueueOp_EnqueueLast value, $Res Function(QueueOp_EnqueueLast) _then) = _$QueueOp_EnqueueLastCopyWithImpl;
@useResult
$Res call({
 List<String> field0
});




}
/// @nodoc
class _$QueueOp_EnqueueLastCopyWithImpl<$Res>
    implements $QueueOp_EnqueueLastCopyWith<$Res> {
  _$QueueOp_EnqueueLastCopyWithImpl(this._self, this._then);

  final QueueOp_EnqueueLast _self;
  final $Res Function(QueueOp_EnqueueLast) _then;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(QueueOp_EnqueueLast(
null == field0 ? _self._field0 : field0 // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc


class QueueOp_Remove extends QueueOp {
  const QueueOp_Remove(this.field0): super._();
  

 final  String field0;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueueOp_RemoveCopyWith<QueueOp_Remove> get copyWith => _$QueueOp_RemoveCopyWithImpl<QueueOp_Remove>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueueOp_Remove&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'QueueOp.remove(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $QueueOp_RemoveCopyWith<$Res> implements $QueueOpCopyWith<$Res> {
  factory $QueueOp_RemoveCopyWith(QueueOp_Remove value, $Res Function(QueueOp_Remove) _then) = _$QueueOp_RemoveCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$QueueOp_RemoveCopyWithImpl<$Res>
    implements $QueueOp_RemoveCopyWith<$Res> {
  _$QueueOp_RemoveCopyWithImpl(this._self, this._then);

  final QueueOp_Remove _self;
  final $Res Function(QueueOp_Remove) _then;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(QueueOp_Remove(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class QueueOp_Move extends QueueOp {
  const QueueOp_Move({required this.entry, required this.to}): super._();
  

 final  String entry;
 final  int to;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueueOp_MoveCopyWith<QueueOp_Move> get copyWith => _$QueueOp_MoveCopyWithImpl<QueueOp_Move>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueueOp_Move&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.to, to) || other.to == to));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,to);
}

@override
String toString() {
    return 'QueueOp.move(entry: $entry, to: $to)';
}


}

/// @nodoc
abstract mixin class $QueueOp_MoveCopyWith<$Res> implements $QueueOpCopyWith<$Res> {
  factory $QueueOp_MoveCopyWith(QueueOp_Move value, $Res Function(QueueOp_Move) _then) = _$QueueOp_MoveCopyWithImpl;
@useResult
$Res call({
 String entry, int to
});




}
/// @nodoc
class _$QueueOp_MoveCopyWithImpl<$Res>
    implements $QueueOp_MoveCopyWith<$Res> {
  _$QueueOp_MoveCopyWithImpl(this._self, this._then);

  final QueueOp_Move _self;
  final $Res Function(QueueOp_Move) _then;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? to = null,}) {
  return _then(QueueOp_Move(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as String,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class QueueOp_Shuffle extends QueueOp {
  const QueueOp_Shuffle(this.field0): super._();
  

 final  bool field0;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueueOp_ShuffleCopyWith<QueueOp_Shuffle> get copyWith => _$QueueOp_ShuffleCopyWithImpl<QueueOp_Shuffle>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueueOp_Shuffle&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'QueueOp.shuffle(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $QueueOp_ShuffleCopyWith<$Res> implements $QueueOpCopyWith<$Res> {
  factory $QueueOp_ShuffleCopyWith(QueueOp_Shuffle value, $Res Function(QueueOp_Shuffle) _then) = _$QueueOp_ShuffleCopyWithImpl;
@useResult
$Res call({
 bool field0
});




}
/// @nodoc
class _$QueueOp_ShuffleCopyWithImpl<$Res>
    implements $QueueOp_ShuffleCopyWith<$Res> {
  _$QueueOp_ShuffleCopyWithImpl(this._self, this._then);

  final QueueOp_Shuffle _self;
  final $Res Function(QueueOp_Shuffle) _then;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(QueueOp_Shuffle(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class QueueOp_Repeat extends QueueOp {
  const QueueOp_Repeat(this.field0): super._();
  

 final  Repeat field0;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueueOp_RepeatCopyWith<QueueOp_Repeat> get copyWith => _$QueueOp_RepeatCopyWithImpl<QueueOp_Repeat>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueueOp_Repeat&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'QueueOp.repeat(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $QueueOp_RepeatCopyWith<$Res> implements $QueueOpCopyWith<$Res> {
  factory $QueueOp_RepeatCopyWith(QueueOp_Repeat value, $Res Function(QueueOp_Repeat) _then) = _$QueueOp_RepeatCopyWithImpl;
@useResult
$Res call({
 Repeat field0
});




}
/// @nodoc
class _$QueueOp_RepeatCopyWithImpl<$Res>
    implements $QueueOp_RepeatCopyWith<$Res> {
  _$QueueOp_RepeatCopyWithImpl(this._self, this._then);

  final QueueOp_Repeat _self;
  final $Res Function(QueueOp_Repeat) _then;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(QueueOp_Repeat(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as Repeat,
  ));
}


}

/// @nodoc


class QueueOp_JumpTo extends QueueOp {
  const QueueOp_JumpTo(this.field0): super._();
  

 final  String field0;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueueOp_JumpToCopyWith<QueueOp_JumpTo> get copyWith => _$QueueOp_JumpToCopyWithImpl<QueueOp_JumpTo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueueOp_JumpTo&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'QueueOp.jumpTo(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $QueueOp_JumpToCopyWith<$Res> implements $QueueOpCopyWith<$Res> {
  factory $QueueOp_JumpToCopyWith(QueueOp_JumpTo value, $Res Function(QueueOp_JumpTo) _then) = _$QueueOp_JumpToCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$QueueOp_JumpToCopyWithImpl<$Res>
    implements $QueueOp_JumpToCopyWith<$Res> {
  _$QueueOp_JumpToCopyWithImpl(this._self, this._then);

  final QueueOp_JumpTo _self;
  final $Res Function(QueueOp_JumpTo) _then;

/// Create a copy of QueueOp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(QueueOp_JumpTo(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
