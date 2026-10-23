// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'events.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LibraryChanged {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryChanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LibraryChanged()';
}


}

/// @nodoc
class $LibraryChangedCopyWith<$Res>  {
$LibraryChangedCopyWith(LibraryChanged _, $Res Function(LibraryChanged) __);
}


/// Adds pattern-matching-related methods to [LibraryChanged].
extension LibraryChangedPatterns on LibraryChanged {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LibraryChanged_Likes value)?  likes,TResult Function( LibraryChanged_Playlists value)?  playlists,TResult Function( LibraryChanged_Playlist value)?  playlist,TResult Function( LibraryChanged_Downloads value)?  downloads,TResult Function( LibraryChanged_History value)?  history,TResult Function( LibraryChanged_Plugins value)?  plugins,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LibraryChanged_Likes() when likes != null:
return likes(_that);case LibraryChanged_Playlists() when playlists != null:
return playlists(_that);case LibraryChanged_Playlist() when playlist != null:
return playlist(_that);case LibraryChanged_Downloads() when downloads != null:
return downloads(_that);case LibraryChanged_History() when history != null:
return history(_that);case LibraryChanged_Plugins() when plugins != null:
return plugins(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LibraryChanged_Likes value)  likes,required TResult Function( LibraryChanged_Playlists value)  playlists,required TResult Function( LibraryChanged_Playlist value)  playlist,required TResult Function( LibraryChanged_Downloads value)  downloads,required TResult Function( LibraryChanged_History value)  history,required TResult Function( LibraryChanged_Plugins value)  plugins,}){
final _that = this;
switch (_that) {
case LibraryChanged_Likes():
return likes(_that);case LibraryChanged_Playlists():
return playlists(_that);case LibraryChanged_Playlist():
return playlist(_that);case LibraryChanged_Downloads():
return downloads(_that);case LibraryChanged_History():
return history(_that);case LibraryChanged_Plugins():
return plugins(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LibraryChanged_Likes value)?  likes,TResult? Function( LibraryChanged_Playlists value)?  playlists,TResult? Function( LibraryChanged_Playlist value)?  playlist,TResult? Function( LibraryChanged_Downloads value)?  downloads,TResult? Function( LibraryChanged_History value)?  history,TResult? Function( LibraryChanged_Plugins value)?  plugins,}){
final _that = this;
switch (_that) {
case LibraryChanged_Likes() when likes != null:
return likes(_that);case LibraryChanged_Playlists() when playlists != null:
return playlists(_that);case LibraryChanged_Playlist() when playlist != null:
return playlist(_that);case LibraryChanged_Downloads() when downloads != null:
return downloads(_that);case LibraryChanged_History() when history != null:
return history(_that);case LibraryChanged_Plugins() when plugins != null:
return plugins(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  likes,TResult Function()?  playlists,TResult Function( String id)?  playlist,TResult Function()?  downloads,TResult Function()?  history,TResult Function()?  plugins,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LibraryChanged_Likes() when likes != null:
return likes();case LibraryChanged_Playlists() when playlists != null:
return playlists();case LibraryChanged_Playlist() when playlist != null:
return playlist(_that.id);case LibraryChanged_Downloads() when downloads != null:
return downloads();case LibraryChanged_History() when history != null:
return history();case LibraryChanged_Plugins() when plugins != null:
return plugins();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  likes,required TResult Function()  playlists,required TResult Function( String id)  playlist,required TResult Function()  downloads,required TResult Function()  history,required TResult Function()  plugins,}) {final _that = this;
switch (_that) {
case LibraryChanged_Likes():
return likes();case LibraryChanged_Playlists():
return playlists();case LibraryChanged_Playlist():
return playlist(_that.id);case LibraryChanged_Downloads():
return downloads();case LibraryChanged_History():
return history();case LibraryChanged_Plugins():
return plugins();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  likes,TResult? Function()?  playlists,TResult? Function( String id)?  playlist,TResult? Function()?  downloads,TResult? Function()?  history,TResult? Function()?  plugins,}) {final _that = this;
switch (_that) {
case LibraryChanged_Likes() when likes != null:
return likes();case LibraryChanged_Playlists() when playlists != null:
return playlists();case LibraryChanged_Playlist() when playlist != null:
return playlist(_that.id);case LibraryChanged_Downloads() when downloads != null:
return downloads();case LibraryChanged_History() when history != null:
return history();case LibraryChanged_Plugins() when plugins != null:
return plugins();case _:
  return null;

}
}

}

/// @nodoc


class LibraryChanged_Likes extends LibraryChanged {
  const LibraryChanged_Likes(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryChanged_Likes);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LibraryChanged.likes()';
}


}




/// @nodoc


class LibraryChanged_Playlists extends LibraryChanged {
  const LibraryChanged_Playlists(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryChanged_Playlists);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LibraryChanged.playlists()';
}


}




/// @nodoc


class LibraryChanged_Playlist extends LibraryChanged {
  const LibraryChanged_Playlist({required this.id}): super._();
  

 final  String id;

/// Create a copy of LibraryChanged
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LibraryChanged_PlaylistCopyWith<LibraryChanged_Playlist> get copyWith => _$LibraryChanged_PlaylistCopyWithImpl<LibraryChanged_Playlist>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryChanged_Playlist&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id);
}

@override
String toString() {
    return 'LibraryChanged.playlist(id: $id)';
}


}

/// @nodoc
abstract mixin class $LibraryChanged_PlaylistCopyWith<$Res> implements $LibraryChangedCopyWith<$Res> {
  factory $LibraryChanged_PlaylistCopyWith(LibraryChanged_Playlist value, $Res Function(LibraryChanged_Playlist) _then) = _$LibraryChanged_PlaylistCopyWithImpl;
@useResult
$Res call({
 String id
});




}
/// @nodoc
class _$LibraryChanged_PlaylistCopyWithImpl<$Res>
    implements $LibraryChanged_PlaylistCopyWith<$Res> {
  _$LibraryChanged_PlaylistCopyWithImpl(this._self, this._then);

  final LibraryChanged_Playlist _self;
  final $Res Function(LibraryChanged_Playlist) _then;

/// Create a copy of LibraryChanged
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,}) {
  return _then(LibraryChanged_Playlist(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class LibraryChanged_Downloads extends LibraryChanged {
  const LibraryChanged_Downloads(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryChanged_Downloads);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LibraryChanged.downloads()';
}


}




/// @nodoc


class LibraryChanged_History extends LibraryChanged {
  const LibraryChanged_History(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryChanged_History);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LibraryChanged.history()';
}


}




/// @nodoc


class LibraryChanged_Plugins extends LibraryChanged {
  const LibraryChanged_Plugins(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LibraryChanged_Plugins);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'LibraryChanged.plugins()';
}


}




/// @nodoc
mixin _$Notice {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Notice);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Notice()';
}


}

/// @nodoc
class $NoticeCopyWith<$Res>  {
$NoticeCopyWith(Notice _, $Res Function(Notice) __);
}


/// Adds pattern-matching-related methods to [Notice].
extension NoticePatterns on Notice {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( Notice_Skipped value)?  skipped,TResult Function( Notice_UpdateAvailable value)?  updateAvailable,TResult Function( Notice_Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case Notice_Skipped() when skipped != null:
return skipped(_that);case Notice_UpdateAvailable() when updateAvailable != null:
return updateAvailable(_that);case Notice_Error() when error != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( Notice_Skipped value)  skipped,required TResult Function( Notice_UpdateAvailable value)  updateAvailable,required TResult Function( Notice_Error value)  error,}){
final _that = this;
switch (_that) {
case Notice_Skipped():
return skipped(_that);case Notice_UpdateAvailable():
return updateAvailable(_that);case Notice_Error():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( Notice_Skipped value)?  skipped,TResult? Function( Notice_UpdateAvailable value)?  updateAvailable,TResult? Function( Notice_Error value)?  error,}){
final _that = this;
switch (_that) {
case Notice_Skipped() when skipped != null:
return skipped(_that);case Notice_UpdateAvailable() when updateAvailable != null:
return updateAvailable(_that);case Notice_Error() when error != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String title,  CoreError reason)?  skipped,TResult Function( String version)?  updateAvailable,TResult Function( CoreError field0)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case Notice_Skipped() when skipped != null:
return skipped(_that.title,_that.reason);case Notice_UpdateAvailable() when updateAvailable != null:
return updateAvailable(_that.version);case Notice_Error() when error != null:
return error(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String title,  CoreError reason)  skipped,required TResult Function( String version)  updateAvailable,required TResult Function( CoreError field0)  error,}) {final _that = this;
switch (_that) {
case Notice_Skipped():
return skipped(_that.title,_that.reason);case Notice_UpdateAvailable():
return updateAvailable(_that.version);case Notice_Error():
return error(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String title,  CoreError reason)?  skipped,TResult? Function( String version)?  updateAvailable,TResult? Function( CoreError field0)?  error,}) {final _that = this;
switch (_that) {
case Notice_Skipped() when skipped != null:
return skipped(_that.title,_that.reason);case Notice_UpdateAvailable() when updateAvailable != null:
return updateAvailable(_that.version);case Notice_Error() when error != null:
return error(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class Notice_Skipped extends Notice {
  const Notice_Skipped({required this.title, required this.reason}): super._();
  

 final  String title;
 final  CoreError reason;

/// Create a copy of Notice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Notice_SkippedCopyWith<Notice_Skipped> get copyWith => _$Notice_SkippedCopyWithImpl<Notice_Skipped>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Notice_Skipped&&(identical(other.title, title) || other.title == title)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,reason);
}

@override
String toString() {
    return 'Notice.skipped(title: $title, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $Notice_SkippedCopyWith<$Res> implements $NoticeCopyWith<$Res> {
  factory $Notice_SkippedCopyWith(Notice_Skipped value, $Res Function(Notice_Skipped) _then) = _$Notice_SkippedCopyWithImpl;
@useResult
$Res call({
 String title, CoreError reason
});


$CoreErrorCopyWith<$Res> get reason;

}
/// @nodoc
class _$Notice_SkippedCopyWithImpl<$Res>
    implements $Notice_SkippedCopyWith<$Res> {
  _$Notice_SkippedCopyWithImpl(this._self, this._then);

  final Notice_Skipped _self;
  final $Res Function(Notice_Skipped) _then;

/// Create a copy of Notice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = null,Object? reason = null,}) {
  return _then(Notice_Skipped(
title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as CoreError,
  ));
}

/// Create a copy of Notice
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CoreErrorCopyWith<$Res> get reason {
  
  return $CoreErrorCopyWith<$Res>(_self.reason, (value) {
    return _then(_self.copyWith(reason: value));
  });
}
}

/// @nodoc


class Notice_UpdateAvailable extends Notice {
  const Notice_UpdateAvailable({required this.version}): super._();
  

 final  String version;

/// Create a copy of Notice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Notice_UpdateAvailableCopyWith<Notice_UpdateAvailable> get copyWith => _$Notice_UpdateAvailableCopyWithImpl<Notice_UpdateAvailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Notice_UpdateAvailable&&(identical(other.version, version) || other.version == version));
}


@override
int get hashCode {
    return Object.hash(runtimeType,version);
}

@override
String toString() {
    return 'Notice.updateAvailable(version: $version)';
}


}

/// @nodoc
abstract mixin class $Notice_UpdateAvailableCopyWith<$Res> implements $NoticeCopyWith<$Res> {
  factory $Notice_UpdateAvailableCopyWith(Notice_UpdateAvailable value, $Res Function(Notice_UpdateAvailable) _then) = _$Notice_UpdateAvailableCopyWithImpl;
@useResult
$Res call({
 String version
});




}
/// @nodoc
class _$Notice_UpdateAvailableCopyWithImpl<$Res>
    implements $Notice_UpdateAvailableCopyWith<$Res> {
  _$Notice_UpdateAvailableCopyWithImpl(this._self, this._then);

  final Notice_UpdateAvailable _self;
  final $Res Function(Notice_UpdateAvailable) _then;

/// Create a copy of Notice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? version = null,}) {
  return _then(Notice_UpdateAvailable(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class Notice_Error extends Notice {
  const Notice_Error(this.field0): super._();
  

 final  CoreError field0;

/// Create a copy of Notice
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$Notice_ErrorCopyWith<Notice_Error> get copyWith => _$Notice_ErrorCopyWithImpl<Notice_Error>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Notice_Error&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'Notice.error(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $Notice_ErrorCopyWith<$Res> implements $NoticeCopyWith<$Res> {
  factory $Notice_ErrorCopyWith(Notice_Error value, $Res Function(Notice_Error) _then) = _$Notice_ErrorCopyWithImpl;
@useResult
$Res call({
 CoreError field0
});


$CoreErrorCopyWith<$Res> get field0;

}
/// @nodoc
class _$Notice_ErrorCopyWithImpl<$Res>
    implements $Notice_ErrorCopyWith<$Res> {
  _$Notice_ErrorCopyWithImpl(this._self, this._then);

  final Notice_Error _self;
  final $Res Function(Notice_Error) _then;

/// Create a copy of Notice
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(Notice_Error(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as CoreError,
  ));
}

/// Create a copy of Notice
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CoreErrorCopyWith<$Res> get field0 {
  
  return $CoreErrorCopyWith<$Res>(_self.field0, (value) {
    return _then(_self.copyWith(field0: value));
  });
}
}

// dart format on
