//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

library openapi.api;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

part 'api_client.dart';
part 'api_helper.dart';
part 'api_exception.dart';
part 'auth/authentication.dart';
part 'auth/api_key_auth.dart';
part 'auth/oauth.dart';
part 'auth/http_basic_auth.dart';
part 'auth/http_bearer_auth.dart';

part 'api/auth_api.dart';
part 'api/library_api.dart';
part 'api/system_api.dart';
part 'api/transcode_api.dart';

part 'model/account.dart';
part 'model/add_vault_item_request.dart';
part 'model/continue_item.dart';
part 'model/create_library_request.dart';
part 'model/create_vault_request.dart';
part 'model/device.dart';
part 'model/device_preferences.dart';
part 'model/device_ref.dart';
part 'model/device_registration_request.dart';
part 'model/device_registration_response.dart';
part 'model/device_rename_request.dart';
part 'model/device_switch_request.dart';
part 'model/episode_summary.dart';
part 'model/error.dart';
part 'model/facet.dart';
part 'model/link_approve_request.dart';
part 'model/link_start_response.dart';
part 'model/link_status_response.dart';
part 'model/login_request.dart';
part 'model/login_response.dart';
part 'model/media_item_detail.dart';
part 'model/media_item_page.dart';
part 'model/media_item_summary.dart';
part 'model/model_library.dart';
part 'model/on_deck_item.dart';
part 'model/ping_response.dart';
part 'model/play_state.dart';
part 'model/playback_info.dart';
part 'model/playback_session.dart';
part 'model/profile_create_request.dart';
part 'model/profile_summary.dart';
part 'model/profile_update_request.dart';
part 'model/progress_update.dart';
part 'model/reorder_vault_request.dart';
part 'model/role.dart';
part 'model/scan_library_result.dart';
part 'model/scan_status.dart';
part 'model/search_results.dart';
part 'model/season_summary.dart';
part 'model/series_detail.dart';
part 'model/series_page.dart';
part 'model/series_summary.dart';
part 'model/session.dart';
part 'model/subtitle_track.dart';
part 'model/transcode_cache_stats.dart';
part 'model/transcode_capabilities.dart';
part 'model/transcode_progress.dart';
part 'model/transcode_session.dart';
part 'model/transcode_start_request.dart';
part 'model/update_vault_request.dart';
part 'model/user_preferences.dart';
part 'model/user_profile.dart';
part 'model/vault.dart';
part 'model/vault_detail.dart';
part 'model/vault_entry.dart';
part 'model/watched_bulk_result.dart';
part 'model/watched_update.dart';


/// An [ApiClient] instance that uses the default values obtained from
/// the OpenAPI specification file.
var defaultApiClient = ApiClient();

const _delimiters = {'csv': ',', 'ssv': ' ', 'tsv': '\t', 'pipes': '|'};
const _dateEpochMarker = 'epoch';
const _deepEquality = DeepCollectionEquality();
final _dateFormatter = DateFormat('yyyy-MM-dd');
final _regList = RegExp(r'^List<(.*)>$');
final _regSet = RegExp(r'^Set<(.*)>$');
final _regMap = RegExp(r'^Map<String,(.*)>$');

bool _isEpochMarker(String? pattern) => pattern == _dateEpochMarker || pattern == '/$_dateEpochMarker/';
