import assert from "node:assert/strict";
import test from "node:test";

import {
  COPYABLE_FIELDS,
  REDACTED_VALUE,
  redactDiagnostics,
  redactText,
} from "./redact.ts";
import type { DiagnosticsData } from "./types.ts";

const SECRETS = {
  deviceId: "7451564133168743978",
  iid: "9876543210",
  secUid: "MS4wLjABAAAAyR87q4L9RTyaDxZZltLJ6s2pONfOQvOT99k1xQGeLNyTtq3VUqLP6g66jgQFZNE",
  token: "abcSECRET123",
  session: "0a1b2c3d4e5f",
};

test("redacts the shapes the backend actually emits", () => {
  const cases: Array<[string, string]> = [
    [
      "url query",
      `GET /aweme/v2/feed/?device_id=${SECRETS.deviceId}&iid=${SECRETS.iid}&count=10`,
    ],
    [
      "bare key=value params dump",
      `CommonParams{device_id=${SECRETS.deviceId}, iid=${SECRETS.iid}, carrier_region=HK}`,
    ],
    ["spaces around equals", `device_id = ${SECRETS.deviceId}`],
    ["dash header", `x-tt-token: ${SECRETS.token} end`],
    ["colon form", `sessionid: ${SECRETS.session}`],
    ["json value", `{"sec_uid":"${SECRETS.secUid}","status":1}`],
    [
      "TNC separator",
      `device_id&#*${SECRETS.deviceId}@$*received_region_config&#*1`,
    ],
    [
      "TNC separator with a prefixed key",
      `store_sec_uid&#*${SECRETS.secUid}@$*tnc_abtest&#*1`,
    ],
    ["authorization header", "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.sig"],
    ["cookie header", "Cookie: sessionid=abc; sid_tt=def"],
  ];

  for (const [name, input] of cases) {
    const output = redactText(input);
    assert.ok(
      output.includes(REDACTED_VALUE),
      `${name}: expected a redaction marker in ${JSON.stringify(output)}`,
    );
    for (const secret of Object.values(SECRETS)) {
      assert.ok(
        !output.includes(secret),
        `${name}: leaked ${secret} in ${JSON.stringify(output)}`,
      );
    }
    assert.ok(
      !output.includes("eyJhbGciOiJIUzI1NiJ9"),
      `${name}: leaked an authorization token`,
    );
  }
});

test("leaves diagnostic evidence intact", () => {
  const keep = [
    "carrier_region=HK&mcc_mnc=45400&sys_region=US",
    "E TTNet: ERR_TTNET_TRAFFIC_CONTROL_DROP InternalErrorCode=-555 rule_id=3011076",
    "http_request_status_code=403 cronet_internal_error_code=-202",
    "NetworkRequest [ LISTEN id=64, [ Capabilities: INTERNET&VALIDATED Uid: 1000 ] ]",
  ];

  for (const input of keep) {
    assert.equal(redactText(input), input, `over-redacted: ${input}`);
  }
});

test("drops unknown fields instead of copying them", () => {
  const data = {
    status: "blocked",
    diagnosis_id: "local_ttnet_drop",
    device_id: SECRETS.deviceId,
    some_future_identity_field: SECRETS.secUid,
  } as DiagnosticsData;

  const output = redactDiagnostics(data);

  assert.equal(output.status, "blocked");
  assert.equal(output.diagnosis_id, "local_ttnet_drop");
  assert.ok(!("device_id" in output), "device_id should not be copied");
  assert.ok(
    !("some_future_identity_field" in output),
    "unknown fields must not be copied",
  );
  assert.ok(
    !JSON.stringify(output).includes(SECRETS.secUid),
    "unknown field value leaked",
  );
});

test("redacts values inside retained log fields", () => {
  const data = {
    status: "clean",
    latest_region_line: `carrier_region=HK CommonParams{device_id=${SECRETS.deviceId}, iid=${SECRETS.iid}}`,
    module_log: `[2026-01-01 00:00:00] x-tt-token: ${SECRETS.token}`,
  } as DiagnosticsData;

  const output = redactDiagnostics(data);
  const serialized = JSON.stringify(output);

  assert.ok(output.latest_region_line?.includes("carrier_region=HK"));
  assert.ok(
    !serialized.includes(SECRETS.deviceId),
    "device_id leaked from a log field",
  );
  assert.ok(!serialized.includes(SECRETS.iid), "iid leaked from a log field");
  assert.ok(
    !serialized.includes(SECRETS.token),
    "token leaked from the module log",
  );
});

test("COPYABLE_FIELDS stays declared and stable", () => {
  assert.ok(COPYABLE_FIELDS.includes("status"));
  assert.ok(COPYABLE_FIELDS.includes("module_log"));
  assert.equal(new Set(COPYABLE_FIELDS).size, COPYABLE_FIELDS.length);
});
