extends Node

var _office: Node = null

func setup(office: Node) -> void:
	_office = office

func request(method: int, endpoint: String, payload: Dictionary = {}) -> Dictionary:
	if _office == null:
		return {"ok": false, "error": "api client not initialized"}

	var bases: PackedStringArray = PackedStringArray()
	var primary: String = _normalize_base_url(String(_office.api_base_url))
	if primary != "":
		bases.append(primary)
	if OS.get_name() != "Web":
		for base in _office.api_fallback_base_urls:
			var normalized: String = _normalize_base_url(String(base))
			if normalized == "" or bases.has(normalized):
				continue
			bases.append(normalized)

	var last_result: Dictionary = {"ok": false, "error": "no api base url configured"}
	for i in range(0, bases.size()):
		var base_url: String = String(bases[i])
		var result: Dictionary = await _request_with_base(base_url, method, endpoint, payload)
		if bool(result.get("ok", false)):
			if _office.api_base_url != base_url:
				_office.api_base_url = base_url
			return result
		last_result = result
		if i < bases.size() - 1 and _should_try_next_base(result):
			continue
		break
	return last_result

func request_with_base(base_url: String, method: int, endpoint: String, payload: Dictionary = {}) -> Dictionary:
	if _office == null:
		return {"ok": false, "error": "api client not initialized"}
	return await _request_with_base(base_url, method, endpoint, payload)

func _request_with_base(base_url: String, method: int, endpoint: String, payload: Dictionary) -> Dictionary:
	var req: HTTPRequest = HTTPRequest.new()
	_office.add_child(req)

	var resolved_base_url: String = _resolve_request_base_url(base_url)
	var url: String = "%s%s" % [resolved_base_url, endpoint]
	print("[API] request ", method, " ", url)
	var headers: PackedStringArray = PackedStringArray()
	var auth_header: String = _build_authorization_header()
	var has_auth: bool = auth_header != ""
	_office._api_debug_note_request(method, url, has_auth)
	if auth_header != "":
		headers.append(auth_header)
	var body: String = ""
	if method == HTTPClient.METHOD_POST:
		headers.append("Content-Type: application/json")
		body = JSON.stringify(payload)

	var err: Error = req.request(url, headers, method, body)
	if err != OK:
		push_warning("[API] request start failed: %s url=%s" % [str(err), url])
		req.queue_free()
		var start_fail: Dictionary = {"ok": false, "error": "request start failed: %s" % str(err), "network_error": true}
		_office._api_debug_note_result(start_fail)
		return start_fail

	var response: Array = await req.request_completed
	req.queue_free()
	if response.size() < 4:
		var invalid_resp: Dictionary = {"ok": false, "error": "invalid response", "network_error": true}
		_office._api_debug_note_result(invalid_resp)
		return invalid_resp

	var request_result: int = int(response[0])
	var response_code: int = int(response[1])
	var response_body: PackedByteArray = response[3]
	var response_text: String = response_body.get_string_from_utf8()

	if request_result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[API] request failed result=%d code=%d url=%s" % [request_result, response_code, url])
		var req_fail: Dictionary = {
			"ok": false,
			"error": "request failed(%d): %s" % [request_result, _http_request_result_text(request_result)],
			"code": response_code,
			"raw": response_text,
			"network_error": true
		}
		_office._api_debug_note_result(req_fail, response_code, request_result, response_text)
		return req_fail

	if response_code == 0:
		push_warning("[API] HTTP 0 url=%s" % url)
		var http_zero: Dictionary = {"ok": false, "error": "HTTP 0 (network unreachable or API unavailable)", "code": response_code, "raw": response_text, "network_error": true}
		_office._api_debug_note_result(http_zero, response_code, request_result, response_text)
		return http_zero

	if response_text.strip_edges() == "":
		var empty_resp: Dictionary = {"ok": false, "error": "empty response body (HTTP %d)" % response_code, "code": response_code, "raw": response_text, "network_error": false}
		_office._api_debug_note_result(empty_resp, response_code, request_result, response_text)
		return empty_resp

	var parsed: Variant = JSON.parse_string(response_text)
	var parsed_dict: Dictionary = {}
	if parsed is Dictionary:
		parsed_dict = _normalize_api_dictionary(parsed as Dictionary)
	else:
		var invalid_json: Dictionary = {"ok": false, "error": "invalid JSON body (HTTP %d)" % response_code, "code": response_code, "raw": response_text, "network_error": false}
		_office._api_debug_note_result(invalid_json, response_code, request_result, response_text)
		return invalid_json

	var success: bool = response_code >= 200 and response_code < 300 and bool(parsed_dict.get("success", false))
	if not success:
		var err_msg: String = String(parsed_dict.get("error", "HTTP %d" % response_code))
		var biz_fail: Dictionary = {"ok": false, "error": err_msg, "code": response_code, "raw": response_text, "network_error": false}
		_office._api_debug_note_result(biz_fail, response_code, request_result, response_text)
		return biz_fail

	var ok_result: Dictionary = {"ok": true, "data": parsed_dict.get("data", {}), "json": parsed_dict, "code": response_code, "base_url": resolved_base_url}
	_office._api_debug_note_result(ok_result, response_code, request_result, response_text)
	return ok_result

func _normalize_api_dictionary(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in src.keys():
		out[key] = _normalize_api_value(src[key])
	return out

func _normalize_api_array(src: Array) -> Array:
	var out: Array = []
	out.resize(src.size())
	for i in range(0, src.size()):
		out[i] = _normalize_api_value(src[i])
	return out

func _normalize_api_value(value: Variant) -> Variant:
	if value is Dictionary:
		return _normalize_api_dictionary(value as Dictionary)
	if value is Array:
		return _normalize_api_array(value as Array)
	if value is String:
		return _normalize_text(String(value))
	return value

func _normalize_text(text: String) -> String:
	return text.strip_edges()

func _build_authorization_header() -> String:
	var token: String = _read_web_auth_token()
	if token == "":
		return ""
	return "Authorization: Bearer %s" % token

func _read_web_auth_token() -> String:
	if OS.get_name() != "Web":
		return ""
	if not Engine.has_singleton("JavaScriptBridge"):
		return ""
	var js_bridge: Object = Engine.get_singleton("JavaScriptBridge")
	if js_bridge == null:
		return ""
	var raw: Variant = js_bridge.call("eval", "(function(){try{return window.localStorage.getItem('aicube_auth')||'';}catch(e){return '';}})();")
	var raw_text: String = String(raw).strip_edges()
	if raw_text == "" or raw_text == "null":
		return ""
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		return String((parsed as Dictionary).get("token", "")).strip_edges()
	return ""

func _normalize_base_url(raw_url: String) -> String:
	var out: String = raw_url.strip_edges()
	if out == "":
		return ""
	if out.ends_with("/"):
		out = out.substr(0, out.length() - 1)
	return out

func _resolve_request_base_url(base_url: String) -> String:
	var out: String = _normalize_base_url(base_url)
	if out.begins_with("http://") or out.begins_with("https://"):
		return out
	if OS.get_name() == "Web" and out.begins_with("/"):
		var origin: String = _get_web_origin()
		if origin != "":
			return "%s%s" % [origin, out]
	if OS.get_name() != "Web" and (out.begins_with("/") or not out.contains("://")):
		var fallback_abs: String = _first_absolute_base_url()
		if fallback_abs != "":
			if out == "" or out == "/api":
				return fallback_abs
			if not out.begins_with("/"):
				out = "/" + out
			return "%s%s" % [fallback_abs, out]
	return out

func _first_absolute_base_url() -> String:
	for base in _office.api_fallback_base_urls:
		var normalized: String = _normalize_base_url(String(base))
		if normalized.begins_with("http://") or normalized.begins_with("https://"):
			return normalized
	return ""

func _get_web_origin() -> String:
	if OS.get_name() != "Web":
		return ""
	if not Engine.has_singleton("JavaScriptBridge"):
		return ""
	var js_bridge: Object = Engine.get_singleton("JavaScriptBridge")
	if js_bridge == null:
		return ""
	var origin: Variant = js_bridge.call("eval", "(function(){try{return window.location.origin||'';}catch(e){return '';}})();")
	return String(origin).strip_edges()

func _should_try_next_base(result: Dictionary) -> bool:
	return bool(result.get("network_error", false))

func _http_request_result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "chunked body size mismatch"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "can't connect"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "can't resolve host"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS handshake error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "no response"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "body size limit exceeded"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "body decompress failed"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "request failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "download file can't open"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "download file write error"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "redirect limit reached"
		HTTPRequest.RESULT_TIMEOUT:
			return "timeout"
		_:
			return "unknown"
