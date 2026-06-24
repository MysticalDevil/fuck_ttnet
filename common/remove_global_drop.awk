function should_remove(obj) {
  return obj ~ /"rule_id"[[:space:]]*:[[:space:]]*3011076/ &&
         obj ~ /"drop"[[:space:]]*:[[:space:]]*1/ &&
         obj ~ /"host_group"[[:space:]]*:[[:space:]]*\[[^]]*"[*]"[^]]*\]/ &&
         obj ~ /"service_name"[[:space:]]*:[[:space:]]*"drop flow"/
}

function find_matching_bracket(text, start,    i, c, depth, in_string, escaped) {
  depth = 0
  in_string = 0
  escaped = 0

  for (i = start; i <= length(text); i++) {
    c = substr(text, i, 1)

    if (in_string) {
      if (escaped) {
        escaped = 0
      } else if (c == "\\") {
        escaped = 1
      } else if (c == "\"") {
        in_string = 0
      }
      continue
    }

    if (c == "\"") {
      in_string = 1
    } else if (c == "[") {
      depth++
    } else if (c == "]") {
      depth--
      if (depth == 0) {
        return i
      }
    }
  }

  return 0
}

function find_object_end(text, start,    i, c, depth, in_string, escaped) {
  depth = 0
  in_string = 0
  escaped = 0

  for (i = start; i <= length(text); i++) {
    c = substr(text, i, 1)

    if (in_string) {
      if (escaped) {
        escaped = 0
      } else if (c == "\\") {
        escaped = 1
      } else if (c == "\"") {
        in_string = 0
      }
      continue
    }

    if (c == "\"") {
      in_string = 1
    } else if (c == "{") {
      depth++
    } else if (c == "}") {
      depth--
      if (depth == 0) {
        return i
      }
    }
  }

  return 0
}

function append_element(element) {
  if (element == "") {
    return
  }

  if (new_array != "") {
    new_array = new_array "," element
  } else {
    new_array = element
  }
}

function rebuild_actions_array(array_text,    i, c, end, obj) {
  i = 1
  new_array = ""
  removed = 0

  while (i <= length(array_text)) {
    c = substr(array_text, i, 1)

    if (c ~ /[[:space:],]/) {
      i++
      continue
    }

    if (c == "{") {
      end = find_object_end(array_text, i)
      if (end == 0) {
        return array_text
      }

      obj = substr(array_text, i, end - i + 1)
      if (should_remove(obj)) {
        removed++
      } else {
        append_element(obj)
      }

      i = end + 1
      continue
    }

    append_element(c)
    i++
  }

  return new_array
}

{
  if (NR > 1) {
    json = json "\n"
  }
  json = json $0
}

END {
  key = "\"ttnet_dispatch_actions\""
  key_pos = index(json, key)
  if (key_pos == 0) {
    print json
    exit
  }

  array_start = index(substr(json, key_pos), "[")
  if (array_start == 0) {
    print json
    exit
  }
  array_start = key_pos + array_start - 1

  array_end = find_matching_bracket(json, array_start)
  if (array_end == 0) {
    print json
    exit
  }

  array_text = substr(json, array_start + 1, array_end - array_start - 1)
  rebuilt = rebuild_actions_array(array_text)

  print substr(json, 1, array_start) rebuilt substr(json, array_end)
}
