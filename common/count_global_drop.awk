function should_count(obj) {
  return obj ~ /"rule_id"[[:space:]]*:[[:space:]]*3011076/ &&
         obj ~ /"action"[[:space:]]*:[[:space:]]*"tc"/ &&
         obj ~ /"drop"[[:space:]]*:[[:space:]]*1/ &&
         obj ~ /"possibility"[[:space:]]*:[[:space:]]*100/ &&
         obj ~ /"host_group"[[:space:]]*:[[:space:]]*\[[^]]*"[*]"[^]]*\]/ &&
         obj ~ /"contain_group"[[:space:]]*:[[:space:]]*\[[^]]*"(\\\/|\/)"[^]]*\]/ &&
         obj ~ /"service_name"[[:space:]]*:[[:space:]]*"drop flow"/
}

function object_start(text, pos,    i, c, depth) {
  depth = 0
  for (i = pos; i >= 1; i--) {
    c = substr(text, i, 1)
    if (c == "}") {
      depth++
    } else if (c == "{") {
      if (depth == 0) {
        return i
      }
      depth--
    }
  }
  return 0
}

function object_end(text, pos,    i, c, depth, in_string, escaped) {
  depth = 0
  in_string = 0
  escaped = 0
  for (i = pos; i <= length(text); i++) {
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

{
  if (NR > 1) {
    json = json "\n"
  }
  json = json $0
}

END {
  count = 0
  offset = 1
  while ((rel = index(substr(json, offset), "3011076")) > 0) {
    pos = offset + rel - 1
    start = object_start(json, pos)
    end = object_end(json, start)
    if (start > 0 && end > 0) {
      obj = substr(json, start, end - start + 1)
      if (should_count(obj)) {
        count++
      }
      offset = end + 1
    } else {
      offset = pos + 7
    }
  }
  print count
}
