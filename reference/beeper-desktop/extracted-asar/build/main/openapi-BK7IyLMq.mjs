import {
  O as E,
  E as q,
  C as D,
  A as M,
  b as R,
  c as O,
  r as C,
  z as e,
  U as N,
  d as P,
  I as U,
  e as B,
  a as V,
} from "./index-Cq1ckG2i.mjs";
import {
  l as A,
  g as x,
  k as f,
  f as K,
  a as W,
  e as I,
  d as z,
  A as S,
  b as L,
  h as j,
  o as G,
  R as k,
  B as F,
  C as H,
  j as $,
  n as J,
  m as Q,
  V as Y,
  S as X,
  t as Z,
  u as ee,
  q as te,
  p as re,
  W as oe,
  r as ie,
  s as ne,
  c as se,
  i as ae,
} from "./http-server-yJjafArR.mjs";
import "./Keychain-CHHka2u7.mjs";
import "./constants-BL_pdRyX.mjs";
import "path";
import "os";
import "url";
import "./index-DKkZ9dV1.mjs";
import "worker_threads";
import "fs";
import "./util-CrY9x2BW.mjs";
import "./_commonjsHelpers-CBUqixCJ.mjs";
import "./sentry-common-CDPx3Glo.mjs";
import "./package-CIHfweXK.mjs";
import "./sentry-enabled-COAVq6nC.mjs";
import "tty";
import "node:crypto";
import "better-sqlite3";
import "node:url";
import "node:path";
import "./logger-DoW0T1f3.mjs";
import "./startup-checkpoints-BQimOHWq.mjs";
import "./AsyncSqlite-CpInlfQ-.mjs";
import "./machine-id-DFkLVgcU.mjs";
import "perf_hooks";
import "child_process";
import "./index-CNG_AM8w.mjs";
import "timers/promises";
import "async_hooks";
import "fs/promises";
import "./index-B_PiTES1.mjs";
import "node:util";
import "node:stream";
import "node:child_process";
import "node:events";
import "node:os";
import "./index-CMOlVndj.mjs";
import "assert";
import "events";
import "buffer";
import "stream";
import "util";
import "node:fs";
import "node:module";
import "./index-DaNOOrJg.mjs";
import "./index-BJhQkpW6.mjs";
import "crypto";
import "http";
import "zlib";
import "https";
import "net";
import "tls";
import "stream/promises";
import "node:fs/promises";
import "./index-C7dxdDjs.mjs";
import "node:string_decoder";
import "./utils-D8MokWSu.mjs";
import "./index-BiKiNEmj.mjs";
import "./register-proxy-7lV9pun2.mjs";
import "domain";
import "./index-BiHJsdYm.mjs";
import "./rolling-logger-C9NTeNo3.mjs";
import "./got-_wC7Q_ix.mjs";
import "dns";
import "http2";
import "module";
import "./index-8JaOpgio.mjs";
import "node:worker_threads";
import "./macos-contacts-server-D9gt4gn9.mjs";
import "node:stream/promises";
import "./readable-VMWn1OrG.mjs";
import "./index-Bo2CLT1C.mjs";
import "./index-Cr2MKBou.mjs";
import "string_decoder";
import "node:zlib";
import "node:http";
import "querystring";
import "node:net";
import "./index-CvW2ssNt.mjs";
import "./immutable-XCMBOkhu.mjs";
(function () {
  try {
    var o =
      typeof window < "u"
        ? window
        : typeof global < "u"
          ? global
          : typeof globalThis < "u"
            ? globalThis
            : typeof self < "u"
              ? self
              : {};
    o.SENTRY_RELEASE = { id: "4.3.209" };
    var n = new o.Error().stack;
    n &&
      ((o._sentryDebugIds = o._sentryDebugIds || {}),
      (o._sentryDebugIds[n] = "36a199f8-1900-48ec-b54e-42413483710d"),
      (o._sentryDebugIdIdentifier =
        "sentry-dbid-36a199f8-1900-48ec-b54e-42413483710d"));
  } catch {}
})();
const pe = {
    paths: {
      "/_matrix/client/v3/user/{userId}/account_data/{type}": {
        get: {
          description: `Get some account data for the client. This config is only visible to the user
that set the account data.`,
          operationId: "getAccountData",
          parameters: [
            {
              description: `The ID of the user to get account data for. The access token must be
authorized to make requests for this user ID.`,
              example: "@alice:example.com",
              in: "path",
              name: "userId",
              required: !0,
              schema: { type: "string" },
            },
            {
              description: `The event type of the account data to get. Custom types should be
namespaced to avoid clashes.`,
              example: "org.example.custom.config",
              in: "path",
              name: "type",
              required: !0,
              schema: { type: "string" },
            },
          ],
          responses: {
            200: {
              content: {
                "application/json": {
                  schema: {
                    example: { custom_account_data_key: "custom_config_value" },
                    type: "object",
                  },
                },
              },
              description: "The account data content for the given type.",
            },
            403: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_FORBIDDEN",
                        error: "Cannot add account data for other users.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "The access token provided is not authorized to retrieve this user's account \ndata. Errcode: `M_FORBIDDEN`.",
            },
            404: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_NOT_FOUND",
                        error: "Account data not found.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "No account data has been provided for this user with the given `type`.\nErrcode: `M_NOT_FOUND`.",
            },
          },
          security: [{ accessTokenQuery: [] }, { accessTokenBearer: [] }],
          summary: "Get some account data for the user.",
          tags: ["User data"],
        },
        put: {
          description: `Set some account data for the client. This config is only visible to the user
that set the account data. The config will be available to clients through the
top-level \`account_data\` field in the homeserver response to
[/sync](https://spec.matrix.org/v1.18/client-server-api/#get_matrixclientv3sync).`,
          operationId: "setAccountData",
          parameters: [
            {
              description: `The ID of the user to set account data for. The access token must be
authorized to make requests for this user ID.`,
              example: "@alice:example.com",
              in: "path",
              name: "userId",
              required: !0,
              schema: { type: "string" },
            },
            {
              description: `The event type of the account data to set. Custom types should be
namespaced to avoid clashes.`,
              example: "org.example.custom.config",
              in: "path",
              name: "type",
              required: !0,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            content: {
              "application/json": {
                schema: {
                  example: { custom_account_data_key: "custom_config_value" },
                  type: "object",
                },
              },
            },
            description: "The content of the account data.",
            required: !0,
          },
          responses: {
            200: {
              content: {
                "application/json": {
                  examples: { response: { value: {} } },
                  schema: { type: "object" },
                },
              },
              description: "The account data was successfully added.",
            },
            400: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_NOT_JSON",
                        error: "Content must be a JSON object.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "The request body is not a JSON object. Errcode: `M_BAD_JSON`\nor `M_NOT_JSON`.",
            },
            403: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_FORBIDDEN",
                        error: "Cannot add account data for other users.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "The access token provided is not authorized to modify this user's account \ndata. Errcode: `M_FORBIDDEN`.",
            },
            405: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_BAD_JSON",
                        error: "Cannot set m.fully_read through this API.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "This `type` of account data is controlled by the server; it cannot be\nmodified by clients. Errcode: `M_BAD_JSON`.",
            },
          },
          security: [{ accessTokenQuery: [] }, { accessTokenBearer: [] }],
          summary: "Set some account data for the user.",
          tags: ["User data"],
        },
      },
      "/_matrix/client/v3/user/{userId}/rooms/{roomId}/account_data/{type}": {
        get: {
          description: `Get some account data for the client on a given room. This config is only
visible to the user that set the account data.`,
          operationId: "getAccountDataPerRoom",
          parameters: [
            {
              description: `The ID of the user to get account data for. The access token must be
authorized to make requests for this user ID.`,
              example: "@alice:example.com",
              in: "path",
              name: "userId",
              required: !0,
              schema: { type: "string" },
            },
            {
              description: "The ID of the room to get account data for.",
              example: "!726s6s6q:example.com",
              in: "path",
              name: "roomId",
              required: !0,
              schema: { type: "string" },
            },
            {
              description: `The event type of the account data to get. Custom types should be
namespaced to avoid clashes.`,
              example: "org.example.custom.room.config",
              in: "path",
              name: "type",
              required: !0,
              schema: { type: "string" },
            },
          ],
          responses: {
            200: {
              content: {
                "application/json": {
                  schema: {
                    example: { custom_account_data_key: "custom_config_value" },
                    type: "object",
                  },
                },
              },
              description: "The account data content for the given type.",
            },
            400: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_INVALID_PARAM",
                        error:
                          "@notaroomid:example.org is not a valid room ID.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "The given `roomID` is not a valid room ID. Errcode: `M_INVALID_PARAM`.",
            },
            403: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_FORBIDDEN",
                        error: "Cannot add account data for other users.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "The access token provided is not authorized to retrieve this user's account \ndata. Errcode: `M_FORBIDDEN`.",
            },
            404: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_NOT_FOUND",
                        error: "Room account data not found.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "No account data has been provided for this user and this room with the \ngiven `type`. Errcode: `M_NOT_FOUND`.",
            },
          },
          security: [{ accessTokenQuery: [] }, { accessTokenBearer: [] }],
          summary:
            "Get some account data for the user that is specific to a room.",
          tags: ["User data"],
        },
        put: {
          description: `Set some account data for the client on a given room. This config is only
visible to the user that set the account data. The config will be delivered to
clients in the per-room entries via [/sync](https://spec.matrix.org/v1.18/client-server-api/#get_matrixclientv3sync).`,
          operationId: "setAccountDataPerRoom",
          parameters: [
            {
              description: `The ID of the user to set account data for. The access token must be
authorized to make requests for this user ID.`,
              example: "@alice:example.com",
              in: "path",
              name: "userId",
              required: !0,
              schema: { type: "string" },
            },
            {
              description: "The ID of the room to set account data on.",
              example: "!726s6s6q:example.com",
              in: "path",
              name: "roomId",
              required: !0,
              schema: { type: "string" },
            },
            {
              description: `The event type of the account data to set. Custom types should be
namespaced to avoid clashes.`,
              example: "org.example.custom.room.config",
              in: "path",
              name: "type",
              required: !0,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            content: {
              "application/json": {
                schema: {
                  example: {
                    custom_account_data_key: "custom_account_data_value",
                  },
                  type: "object",
                },
              },
            },
            description: "The content of the account data.",
            required: !0,
          },
          responses: {
            200: {
              content: {
                "application/json": {
                  examples: { response: { value: {} } },
                  schema: { type: "object" },
                },
              },
              description: "The account data was successfully added.",
            },
            400: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_NOT_JSON",
                        error: "Content must be a JSON object.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "The request body is not a JSON object (errcode `M_BAD_JSON` or\n`M_NOT_JSON`), or the given `roomID` is not a valid room ID\n(errcode `M_INVALID_PARAM`).",
            },
            403: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_FORBIDDEN",
                        error: "Cannot add account data for other users.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "The access token provided is not authorized to modify this user's account \ndata. Errcode: `M_FORBIDDEN`.",
            },
            405: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_BAD_JSON",
                        error: "Cannot set m.fully_read through this API.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "This `type` of account data is controlled by the server; it cannot be\nmodified by clients. Errcode: `M_BAD_JSON`.",
            },
          },
          security: [{ accessTokenQuery: [] }, { accessTokenBearer: [] }],
          summary:
            "Set some account data for the user that is specific to a room.",
          tags: ["User data"],
        },
      },
      "/_matrix/client/v3/rooms/{roomId}/state": {
        get: {
          description: "Get the state events for the current state of a room.",
          operationId: "getRoomState",
          parameters: [
            {
              description: "The room to look up the state for.",
              example: "!636q39766251:example.com",
              in: "path",
              name: "roomId",
              required: !0,
              schema: { type: "string" },
            },
          ],
          responses: {
            200: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: [
                        {
                          content: { join_rule: "public" },
                          event_id: "$143273582443PhrSn:example.org",
                          origin_server_ts: 1432735824653,
                          room_id: "!636q39766251:example.com",
                          sender: "@example:example.org",
                          state_key: "",
                          type: "m.room.join_rules",
                          unsigned: { age: 1234, membership: "join" },
                        },
                        {
                          content: {
                            avatar_url: "mxc://example.org/SEsfnsuifSDFSSEF",
                            displayname: "Alice Margatroid",
                            membership: "join",
                            reason: "Looking for support",
                          },
                          event_id: "$143273582443PhrSn:example.org",
                          origin_server_ts: 1432735824653,
                          room_id: "!636q39766251:example.com",
                          sender: "@alice:example.org",
                          state_key: "@alice:example.org",
                          type: "m.room.member",
                          unsigned: { age: 1234, membership: "join" },
                        },
                        {
                          content: {
                            "m.federate": !0,
                            predecessor: {
                              event_id: "$something:example.org",
                              room_id: "!oldroom:example.org",
                            },
                            room_version: "11",
                          },
                          event_id: "$143273582443PhrSn:example.org",
                          origin_server_ts: 1432735824653,
                          room_id: "!636q39766251:example.com",
                          sender: "@example:example.org",
                          state_key: "",
                          type: "m.room.create",
                          unsigned: { age: 1234, membership: "join" },
                        },
                        {
                          content: {
                            ban: 50,
                            events: {
                              "m.room.name": 100,
                              "m.room.power_levels": 100,
                            },
                            events_default: 0,
                            invite: 50,
                            kick: 50,
                            notifications: { room: 20 },
                            redact: 50,
                            state_default: 50,
                            users: { "@example:localhost": 100 },
                            users_default: 0,
                          },
                          event_id: "$143273582443PhrSn:example.org",
                          origin_server_ts: 1432735824653,
                          room_id: "!636q39766251:example.com",
                          sender: "@example:example.org",
                          state_key: "",
                          type: "m.room.power_levels",
                          unsigned: { age: 1234, membership: "join" },
                        },
                      ],
                    },
                  },
                  schema: {
                    description: `If the user is a member of the room this will be the
current state of the room as a list of events. If the user
has left the room then this will be the state of the room
when they left as a list of events.`,
                    items: {
                      allOf: [
                        {
                          description:
                            "The format used for events when they are returned from\nAPI endpoints such as `/sync`, where the `room_id` is implied elsewhere\nin the response.",
                          properties: {
                            content: {
                              description:
                                "The body of this event, as created by the client which sent it.",
                              example: { membership: "join" },
                              type: "object",
                            },
                            event_id: {
                              description:
                                "The globally unique identifier for this event.",
                              example:
                                "$26RqwJMLw-yds1GAH_QxjHRC1Da9oasK0e5VLnck_45",
                              type: "string",
                            },
                            origin_server_ts: {
                              description: `Timestamp (in milliseconds since the unix epoch) on originating homeserver
when this event was sent.`,
                              example: 1632489532305,
                              format: "int64",
                              type: "integer",
                            },
                            sender: {
                              description:
                                "Contains the fully-qualified ID of the user who sent this event.",
                              example: "@example:example.org",
                              type: "string",
                            },
                            state_key: {
                              description: `Present if, and only if, this event is a *state* event. The key making
this piece of state unique in the room. Note that it is often an empty
string.

State keys starting with an \`@\` are reserved for referencing user IDs, such
as room members. With the exception of a few events, state events set with a
given user's ID as the state key MUST only be set by that user.`,
                              example: "@user:example.org",
                              type: "string",
                            },
                            type: {
                              description: "The type of the event.",
                              example: "m.room.member",
                              type: "string",
                            },
                            unsigned: {
                              description:
                                "Contains optional extra information about the event.",
                              properties: {
                                age: {
                                  description:
                                    "The time in milliseconds that has elapsed since the event was sent. This field is generated by the local homeserver, and may be incorrect if the local time on at least one of the two servers is out of sync, which can cause the age to either be negative or greater than it actually is.",
                                  example: 1567437,
                                  format: "int64",
                                  type: "integer",
                                },
                                membership: {
                                  description: `The room membership of the user making the request, at the time of the event.

This property is the value of the \`membership\` property of the
requesting user's [\`m.room.member\`](https://spec.matrix.org/v1.18/client-server-api#mroommember)
state at the point of the event, including any changes caused by the
event. If the user had yet to join the room at the time of the event
(i.e, they have no \`m.room.member\` state), this property is set to
\`leave\`.

Homeservers SHOULD populate this property
wherever practical, but they MAY omit it if necessary (for example,
if calculating the value is expensive, servers might choose to only
implement it in encrypted rooms). The property is *not* normally populated
in events pushed to application services via the application service transaction API
(where there is no clear definition of "requesting user").
`,
                                  example: "join",
                                  type: "string",
                                  "x-addedInMatrixVersion": "1.11",
                                },
                                prev_content: {
                                  description: `The previous \`content\` for this event. This field is generated
by the local homeserver, and is only returned if the event is a state event,
and the client has permission to see the previous content.
`,
                                  title: "EventContent",
                                  type: "object",
                                  "x-changedInMatrixVersion": {
                                    1.2: `Previously, this field was specified at the top level of returned
events rather than in \`unsigned\` (with the exception of the [\`GET
.../notifications\`](https://spec.matrix.org/v1.18/client-server-api/#get_matrixclientv3notifications)
endpoint), though in practice no known server implementations honoured
this.
`,
                                  },
                                },
                                redacted_because: {
                                  description:
                                    "The event that redacted this event, if any.",
                                  example: {
                                    content: { reason: "spam" },
                                    event_id:
                                      "$Nhl3rsgHMjk-DjMJANawr9HHAhLg4GcoTYrSiYYGqEE",
                                    origin_server_ts: 1632491098485,
                                    redacts:
                                      "$26RqwJMLw-yds1GAH_QxjHRC1Da9oasK0e5VLnck_45",
                                    sender: "@moderator:example.org",
                                    type: "m.room.redaction",
                                    unsigned: {
                                      age: 1257,
                                      membership: "leave",
                                    },
                                  },
                                  title: "ClientEventWithoutRoomID",
                                  type: "object",
                                },
                                transaction_id: {
                                  description: `The client-supplied [transaction ID](https://spec.matrix.org/v1.18/client-server-api/#transaction-identifiers), for example, provided via
\`PUT /_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId}\`,
if the client being given the event is the same one which sent it.
`,
                                  type: "string",
                                },
                              },
                              title: "UnsignedData",
                              type: "object",
                            },
                          },
                          required: [
                            "event_id",
                            "type",
                            "sender",
                            "origin_server_ts",
                            "content",
                          ],
                          title: "ClientEventWithoutRoomID",
                          type: "object",
                        },
                        {
                          properties: {
                            room_id: {
                              description:
                                "The ID of the room associated with this event.",
                              example: "!jEsUZKDJdhlrceRyVU:example.org",
                              type: "string",
                            },
                            unsigned: {
                              properties: {
                                redacted_because: {
                                  example: {
                                    content: { reason: "spam" },
                                    event_id:
                                      "$Nhl3rsgHMjk-DjMJANawr9HHAhLg4GcoTYrSiYYGqEE",
                                    origin_server_ts: 1632491098485,
                                    redacts:
                                      "$26RqwJMLw-yds1GAH_QxjHRC1Da9oasK0e5VLnck_45",
                                    room_id: "!jEsUZKDJdhlrceRyVU:example.org",
                                    sender: "@moderator:example.org",
                                    type: "m.room.redaction",
                                    unsigned: { age: 1257 },
                                  },
                                  title: "ClientEvent",
                                },
                              },
                            },
                          },
                          required: ["room_id"],
                          type: "object",
                        },
                      ],
                      description: `The format used for events when they are returned from a homeserver to a client
via the Client-Server API, or sent to an Application Service via the Application Services API.`,
                      title: "ClientEvent",
                      type: "object",
                    },
                    title: "RoomState",
                    type: "array",
                  },
                },
              },
              description: "The current state of the room",
            },
            403: {
              description: `You aren't a member of the room and weren't previously a member of the room.
`,
            },
          },
          security: [{ accessTokenQuery: [] }, { accessTokenBearer: [] }],
          summary: "Get all state events in the current state of a room.",
          tags: ["Room participation"],
        },
      },
      "/_matrix/client/v3/rooms/{roomId}/state/{eventType}/{stateKey}": {
        get: {
          description: `Looks up the contents of a state event in a room. If the user is
joined to the room then the state is taken from the current
state of the room. If the user has left the room then the state is
taken from the state of the room when they left.`,
          operationId: "getRoomStateWithKey",
          parameters: [
            {
              description: "The room to look up the state in.",
              example: "!636q39766251:example.com",
              in: "path",
              name: "roomId",
              required: !0,
              schema: { type: "string" },
            },
            {
              description: "The type of state to look up.",
              example: "m.room.name",
              in: "path",
              name: "eventType",
              required: !0,
              schema: { type: "string" },
            },
            {
              description: `The key of the state to look up. Defaults to an empty string. When
an empty string, the trailing slash on this endpoint is optional.`,
              example: "",
              in: "path",
              name: "stateKey",
              required: !0,
              schema: { type: "string" },
            },
            {
              description:
                "The format to use for the returned data. `content` (the default) will\nreturn only the content of the state event. `event` will return the entire\nevent in the usual format suitable for clients, including fields like event\nID, sender and timestamp.",
              example: "event",
              in: "query",
              name: "format",
              schema: { enum: ["content", "event"], type: "string" },
              "x-addedInMatrixVersion": "1.16",
            },
          ],
          responses: {
            200: {
              content: {
                "application/json": {
                  examples: {
                    response: { value: { name: "Example room name" } },
                  },
                  schema: {
                    oneOf: [
                      { type: "object" },
                      {
                        $schema: "https://json-schema.org/draft/2020-12/schema",
                        allOf: [
                          {
                            $schema:
                              "https://json-schema.org/draft/2020-12/schema",
                            allOf: [
                              {
                                $schema:
                                  "https://json-schema.org/draft/2020-12/schema",
                                allOf: [
                                  {
                                    $schema:
                                      "https://json-schema.org/draft/2020-12/schema",
                                    description:
                                      "The basic set of fields all events must have.",
                                    properties: {
                                      content: {
                                        description:
                                          "The fields in this object will vary depending on the type of event. When interacting with the REST API, this is the HTTP body.",
                                        type: "object",
                                      },
                                      type: {
                                        description:
                                          "The type of event, as defined by [the event type specification](https://spec.matrix.org/v1.18/client-server-api/#types-of-room-events).",
                                        type: "string",
                                      },
                                    },
                                    required: ["type", "content"],
                                    title: "Event",
                                    type: "object",
                                  },
                                  {
                                    properties: {
                                      event_id: {
                                        description:
                                          "The globally unique event identifier.",
                                        type: "string",
                                      },
                                      origin_server_ts: {
                                        description:
                                          "Timestamp in milliseconds on originating homeserver when this event was sent.",
                                        format: "int64",
                                        type: "integer",
                                      },
                                      sender: {
                                        description:
                                          "Contains the fully-qualified ID of the user who sent this event.",
                                        type: "string",
                                      },
                                      unsigned: {
                                        $schema:
                                          "https://json-schema.org/draft/2020-12/schema",
                                        description:
                                          "Contains optional extra information about the event.",
                                        properties: {
                                          age: {
                                            description:
                                              "The time in milliseconds that has elapsed since the event was sent.",
                                            type: "integer",
                                          },
                                        },
                                        title: "UnsignedData",
                                        type: "object",
                                      },
                                    },
                                    required: [
                                      "event_id",
                                      "sender",
                                      "origin_server_ts",
                                    ],
                                    type: "object",
                                  },
                                ],
                                description:
                                  "In addition to the Event fields, Room Events have the following additional fields.",
                                title: "SyncRoomEvent",
                              },
                              {
                                properties: {
                                  room_id: {
                                    description:
                                      "The ID of the room associated with this event. Will not be present on events\nthat arrive through `/sync`, despite being required everywhere else.",
                                    type: "string",
                                  },
                                },
                                required: ["room_id"],
                                type: "object",
                              },
                            ],
                            description:
                              "Room Events have the following fields.",
                            title: "RoomEvent",
                          },
                          {
                            $schema:
                              "https://json-schema.org/draft/2020-12/schema",
                            allOf: [
                              {
                                $schema:
                                  "https://json-schema.org/draft/2020-12/schema",
                                allOf: [
                                  {
                                    $schema:
                                      "https://json-schema.org/draft/2020-12/schema",
                                    description:
                                      "The basic set of fields all events must have.",
                                    properties: {
                                      content: {
                                        description:
                                          "The fields in this object will vary depending on the type of event. When interacting with the REST API, this is the HTTP body.",
                                        type: "object",
                                      },
                                      type: {
                                        description:
                                          "The type of event, as defined by [the event type specification](https://spec.matrix.org/v1.18/client-server-api/#types-of-room-events).",
                                        type: "string",
                                      },
                                    },
                                    required: ["type", "content"],
                                    title: "Event",
                                    type: "object",
                                  },
                                  {
                                    properties: {
                                      event_id: {
                                        description:
                                          "The globally unique event identifier.",
                                        type: "string",
                                      },
                                      origin_server_ts: {
                                        description:
                                          "Timestamp in milliseconds on originating homeserver when this event was sent.",
                                        format: "int64",
                                        type: "integer",
                                      },
                                      sender: {
                                        description:
                                          "Contains the fully-qualified ID of the user who sent this event.",
                                        type: "string",
                                      },
                                      unsigned: {
                                        $schema:
                                          "https://json-schema.org/draft/2020-12/schema",
                                        description:
                                          "Contains optional extra information about the event.",
                                        properties: {
                                          age: {
                                            description:
                                              "The time in milliseconds that has elapsed since the event was sent.",
                                            type: "integer",
                                          },
                                        },
                                        title: "UnsignedData",
                                        type: "object",
                                      },
                                    },
                                    required: [
                                      "event_id",
                                      "sender",
                                      "origin_server_ts",
                                    ],
                                    type: "object",
                                  },
                                ],
                                description:
                                  "In addition to the Event fields, Room Events have the following additional fields.",
                                title: "SyncRoomEvent",
                              },
                              {
                                properties: {
                                  state_key: {
                                    description:
                                      "A unique key which defines the overwriting semantics for this piece of room state. This value is often a zero-length string. The presence of this key makes this event a State Event.\nState keys starting with an `@` are reserved for referencing user IDs, such as room members. With the exception of a few events, state events set with a given user's ID as the state key MUST only be set by that user.",
                                    type: "string",
                                  },
                                },
                                required: ["state_key"],
                                type: "object",
                              },
                            ],
                            description:
                              "In addition to the Room Event fields, State Events have the following additional fields.",
                            title: "SyncStateEvent",
                          },
                        ],
                        description: "State Events have the following fields.",
                        title: "StateEvent",
                        type: "object",
                      },
                    ],
                  },
                },
              },
              description:
                "The content of the state event, or the entire client-formatted event\nif `?format=event` was used.",
            },
            403: {
              description: `You aren't a member of the room and weren't previously a member of the room.
`,
            },
            404: {
              description: "The room has no state with the given type or key.",
            },
          },
          security: [{ accessTokenQuery: [] }, { accessTokenBearer: [] }],
          summary: "Get the state identified by the type and key.",
          tags: ["Room participation"],
        },
      },
      "/_matrix/client/v3/rooms/{roomId}/event/{eventId}": {
        get: {
          description:
            "Get a single event based on `roomId/eventId`. You must have permission to\nretrieve this event e.g. by being a member in the room for this event.",
          operationId: "getOneRoomEvent",
          parameters: [
            {
              description: "The ID of the room the event is in.",
              example: "!636q39766251:matrix.org",
              in: "path",
              name: "roomId",
              required: !0,
              schema: { type: "string" },
            },
            {
              description: "The event ID to get.",
              example: "$asfDuShaf7Gafaw:matrix.org",
              in: "path",
              name: "eventId",
              required: !0,
              schema: { type: "string" },
            },
          ],
          responses: {
            200: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        content: {
                          body: "This is an example text message",
                          format: "org.matrix.custom.html",
                          formatted_body:
                            "<b>This is an example text message</b>",
                          msgtype: "m.text",
                        },
                        event_id: "$143273582443PhrSn:example.org",
                        origin_server_ts: 1432735824653,
                        room_id: "!636q39766251:matrix.org",
                        sender: "@example:example.org",
                        type: "m.room.message",
                        unsigned: { age: 1234, membership: "join" },
                      },
                    },
                  },
                  schema: {
                    allOf: [
                      {
                        description:
                          "The format used for events when they are returned from\nAPI endpoints such as `/sync`, where the `room_id` is implied elsewhere\nin the response.",
                        properties: {
                          content: {
                            description:
                              "The body of this event, as created by the client which sent it.",
                            example: { membership: "join" },
                            type: "object",
                          },
                          event_id: {
                            description:
                              "The globally unique identifier for this event.",
                            example:
                              "$26RqwJMLw-yds1GAH_QxjHRC1Da9oasK0e5VLnck_45",
                            type: "string",
                          },
                          origin_server_ts: {
                            description: `Timestamp (in milliseconds since the unix epoch) on originating homeserver
when this event was sent.`,
                            example: 1632489532305,
                            format: "int64",
                            type: "integer",
                          },
                          sender: {
                            description:
                              "Contains the fully-qualified ID of the user who sent this event.",
                            example: "@example:example.org",
                            type: "string",
                          },
                          state_key: {
                            description: `Present if, and only if, this event is a *state* event. The key making
this piece of state unique in the room. Note that it is often an empty
string.

State keys starting with an \`@\` are reserved for referencing user IDs, such
as room members. With the exception of a few events, state events set with a
given user's ID as the state key MUST only be set by that user.`,
                            example: "@user:example.org",
                            type: "string",
                          },
                          type: {
                            description: "The type of the event.",
                            example: "m.room.member",
                            type: "string",
                          },
                          unsigned: {
                            description:
                              "Contains optional extra information about the event.",
                            properties: {
                              age: {
                                description:
                                  "The time in milliseconds that has elapsed since the event was sent. This field is generated by the local homeserver, and may be incorrect if the local time on at least one of the two servers is out of sync, which can cause the age to either be negative or greater than it actually is.",
                                example: 1567437,
                                format: "int64",
                                type: "integer",
                              },
                              membership: {
                                description: `The room membership of the user making the request, at the time of the event.

This property is the value of the \`membership\` property of the
requesting user's [\`m.room.member\`](https://spec.matrix.org/v1.18/client-server-api#mroommember)
state at the point of the event, including any changes caused by the
event. If the user had yet to join the room at the time of the event
(i.e, they have no \`m.room.member\` state), this property is set to
\`leave\`.

Homeservers SHOULD populate this property
wherever practical, but they MAY omit it if necessary (for example,
if calculating the value is expensive, servers might choose to only
implement it in encrypted rooms). The property is *not* normally populated
in events pushed to application services via the application service transaction API
(where there is no clear definition of "requesting user").
`,
                                example: "join",
                                type: "string",
                                "x-addedInMatrixVersion": "1.11",
                              },
                              prev_content: {
                                description: `The previous \`content\` for this event. This field is generated
by the local homeserver, and is only returned if the event is a state event,
and the client has permission to see the previous content.
`,
                                title: "EventContent",
                                type: "object",
                                "x-changedInMatrixVersion": {
                                  1.2: `Previously, this field was specified at the top level of returned
events rather than in \`unsigned\` (with the exception of the [\`GET
.../notifications\`](https://spec.matrix.org/v1.18/client-server-api/#get_matrixclientv3notifications)
endpoint), though in practice no known server implementations honoured
this.
`,
                                },
                              },
                              redacted_because: {
                                description:
                                  "The event that redacted this event, if any.",
                                example: {
                                  content: { reason: "spam" },
                                  event_id:
                                    "$Nhl3rsgHMjk-DjMJANawr9HHAhLg4GcoTYrSiYYGqEE",
                                  origin_server_ts: 1632491098485,
                                  redacts:
                                    "$26RqwJMLw-yds1GAH_QxjHRC1Da9oasK0e5VLnck_45",
                                  sender: "@moderator:example.org",
                                  type: "m.room.redaction",
                                  unsigned: { age: 1257, membership: "leave" },
                                },
                                title: "ClientEventWithoutRoomID",
                                type: "object",
                              },
                              transaction_id: {
                                description: `The client-supplied [transaction ID](https://spec.matrix.org/v1.18/client-server-api/#transaction-identifiers), for example, provided via
\`PUT /_matrix/client/v3/rooms/{roomId}/send/{eventType}/{txnId}\`,
if the client being given the event is the same one which sent it.
`,
                                type: "string",
                              },
                            },
                            title: "UnsignedData",
                            type: "object",
                          },
                        },
                        required: [
                          "event_id",
                          "type",
                          "sender",
                          "origin_server_ts",
                          "content",
                        ],
                        title: "ClientEventWithoutRoomID",
                        type: "object",
                      },
                      {
                        properties: {
                          room_id: {
                            description:
                              "The ID of the room associated with this event.",
                            example: "!jEsUZKDJdhlrceRyVU:example.org",
                            type: "string",
                          },
                          unsigned: {
                            properties: {
                              redacted_because: {
                                example: {
                                  content: { reason: "spam" },
                                  event_id:
                                    "$Nhl3rsgHMjk-DjMJANawr9HHAhLg4GcoTYrSiYYGqEE",
                                  origin_server_ts: 1632491098485,
                                  redacts:
                                    "$26RqwJMLw-yds1GAH_QxjHRC1Da9oasK0e5VLnck_45",
                                  room_id: "!jEsUZKDJdhlrceRyVU:example.org",
                                  sender: "@moderator:example.org",
                                  type: "m.room.redaction",
                                  unsigned: { age: 1257 },
                                },
                                title: "ClientEvent",
                              },
                            },
                          },
                        },
                        required: ["room_id"],
                        type: "object",
                      },
                    ],
                    description: `The format used for events when they are returned from a homeserver to a client
via the Client-Server API, or sent to an Application Service via the Application Services API.`,
                    title: "ClientEvent",
                    type: "object",
                  },
                },
              },
              description: "The full event.",
            },
            404: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_NOT_FOUND",
                        error: "Event not found.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "The event was not found or you do not have permission to read this event.",
            },
          },
          security: [{ accessTokenQuery: [] }, { accessTokenBearer: [] }],
          summary: "Get a single event by event ID.",
          tags: ["Room participation"],
        },
      },
      "/_matrix/client/v3/profile/{userId}": {
        get: {
          description: "Get the complete profile for a user.",
          operationId: "getUserProfile",
          parameters: [
            {
              description: "The user whose profile information to get.",
              example: "@alice:example.com",
              in: "path",
              name: "userId",
              required: !0,
              schema: { type: "string" },
            },
          ],
          responses: {
            200: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        avatar_url: "mxc://matrix.org/SDGdghriugerRg",
                        displayname: "Alice Margatroid",
                        "m.example_field": "custom_value",
                        "m.tz": "Europe/London",
                      },
                    },
                  },
                  schema: {
                    additionalProperties: {
                      description: "Additional profile fields.",
                      "x-addedInMatrixVersion": "1.16",
                    },
                    properties: {
                      avatar_url: {
                        description:
                          "The user's avatar URL if they have set one, otherwise not present.",
                        format: "mx-mxc-uri",
                        type: "string",
                      },
                      displayname: {
                        description:
                          "The user's display name if they have set one, otherwise not present.",
                        type: "string",
                      },
                      "m.tz": {
                        description: "The user's time zone.",
                        type: "string",
                        "x-addedInMatrixVersion": "1.16",
                      },
                    },
                    type: "object",
                  },
                },
              },
              description: "The profile information for this user.",
            },
            403: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_FORBIDDEN",
                        error: "Profile lookup is disabled on this homeserver",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "The server is unwilling to disclose whether the user exists and/or has profile information.",
              "x-addedInMatrixVersion": "1.2",
            },
            404: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_NOT_FOUND",
                        error: "Profile not found",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "There is no profile information for this user or this user does not exist.",
            },
          },
          summary: "Get all profile information for a user.",
          tags: ["User data"],
        },
      },
      "/_matrix/client/v3/join/{roomIdOrAlias}": {
        post: {
          description: `*Note that this API takes either a room ID or alias, unlike* \`/rooms/{roomId}/join\`.

This API starts a user's participation in a particular room, if that user
is allowed to participate in that room. After this call, the client is
allowed to see all current state events in the room, and all subsequent
events associated with the room until the user leaves the room.

After a user has joined a room, the room will appear as an entry in the
response of the [\`/initialSync\`](https://spec.matrix.org/v1.18/client-server-api/#get_matrixclientv3initialsync)
and [\`/sync\`](https://spec.matrix.org/v1.18/client-server-api/#get_matrixclientv3sync) APIs.`,
          operationId: "joinRoom",
          parameters: [
            {
              description: "The room identifier or alias to join.",
              example: "#monkeys:matrix.org",
              in: "path",
              name: "roomIdOrAlias",
              required: !0,
              schema: { type: "string" },
            },
            {
              description: `The servers to attempt to join the room through. One of the servers
must be participating in the room.`,
              example: ["matrix.org", "elsewhere.ca"],
              in: "query",
              name: "via",
              schema: { items: { type: "string" }, type: "array" },
              "x-addedInMatrixVersion": "1.12",
            },
          ],
          requestBody: {
            content: {
              "application/json": {
                schema: {
                  properties: {
                    reason: {
                      description:
                        "Optional reason to be included as the `reason` on the subsequent\nmembership event.",
                      example: "Looking for support",
                      type: "string",
                      "x-addedInMatrixVersion": "1.1",
                    },
                    third_party_signed: {
                      allOf: [
                        {
                          description:
                            "A signature of an `m.third_party_invite` token to prove that this user\nowns a third-party identity which has been invited to the room.",
                          properties: {
                            mxid: {
                              description: "The Matrix ID of the invitee.",
                              example: "@bob:example.org",
                              type: "string",
                            },
                            sender: {
                              description:
                                "The Matrix ID of the user who issued the invite.",
                              example: "@alice:example.org",
                              type: "string",
                            },
                            signatures: {
                              additionalProperties: {
                                additionalProperties: { type: "string" },
                                type: "object",
                              },
                              description:
                                "A signatures object containing a signature of the entire signed object.",
                              example: {
                                "example.org": {
                                  "ed25519:0": "some9signature",
                                },
                              },
                              title: "Signatures",
                              type: "object",
                            },
                            token: {
                              description:
                                "The state key of the m.third_party_invite event.",
                              example: "random8nonce",
                              type: "string",
                            },
                          },
                          required: ["sender", "mxid", "token", "signatures"],
                          title: "Third-party Signed",
                          type: "object",
                        },
                      ],
                      description:
                        "If a `third_party_signed` was supplied, the homeserver must verify\nthat it matches a pending `m.room.third_party_invite` event in the\nroom, and perform key validity checking if required by the event.",
                    },
                  },
                  type: "object",
                },
              },
            },
            required: !0,
          },
          responses: {
            200: {
              content: {
                "application/json": {
                  examples: {
                    response: { value: { room_id: "!d41d8cd:matrix.org" } },
                  },
                  schema: {
                    properties: {
                      room_id: {
                        description: "The joined room ID.",
                        type: "string",
                      },
                    },
                    required: ["room_id"],
                    type: "object",
                  },
                },
              },
              description:
                "The room has been joined.\n\nThe joined room ID must be returned in the `room_id` field.",
            },
            403: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: {
                        errcode: "M_FORBIDDEN",
                        error: "You are not invited to this room.",
                      },
                    },
                  },
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description: `You do not have permission to join the room. A meaningful \`errcode\`
and description error text will be returned. Example reasons for rejection are:

- The room is invite-only and the user was not invited.
- The user has been banned from the room.
- The room is restricted and the user failed to satisfy any of the conditions.`,
            },
            429: {
              content: {
                "application/json": {
                  schema: {
                    allOf: [
                      {
                        description: "A Matrix-level Error",
                        properties: {
                          errcode: {
                            description: "An error code.",
                            example: "M_UNKNOWN",
                            type: "string",
                          },
                          error: {
                            description: "A human-readable error message.",
                            example: "An unknown error occurred",
                            type: "string",
                          },
                        },
                        required: ["errcode"],
                        title: "Error",
                        type: "object",
                      },
                      {
                        description:
                          "The rate limit was reached for this request",
                        properties: {
                          errcode: {
                            description: "The M_LIMIT_EXCEEDED error code",
                            example: "M_LIMIT_EXCEEDED",
                            type: "string",
                          },
                          error: {
                            description: "A human-readable error message.",
                            example: "Too many requests",
                            type: "string",
                          },
                          retry_after_ms: {
                            description: `The amount of time in milliseconds the client should wait
before trying the request again.`,
                            example: 2e3,
                            type: "integer",
                          },
                        },
                        required: ["errcode"],
                        title: "RateLimitError",
                        type: "object",
                      },
                    ],
                  },
                },
              },
              description: "This request was rate-limited.",
            },
          },
          security: [{ accessTokenQuery: [] }, { accessTokenBearer: [] }],
          summary: "Join the requesting user to a particular room.",
          tags: ["Room membership"],
        },
      },
      "/_matrix/client/v3/rooms/{roomId}/leave": {
        post: {
          description: `This API stops a user participating in a particular room.

If the user was already in the room, they will no longer be able to see
new events in the room. If the room requires an invite to join, they
will need to be re-invited before they can re-join.

If the user was invited to the room, but had not joined, this call
serves to reject the invite.

Servers MAY additionally forget the room when this endpoint is called –
just as if the user had also invoked [\`/forget\`](https://spec.matrix.org/v1.18/client-server-api/#post_matrixclientv3roomsroomidforget).
Servers that do this, MUST inform clients about this behavior using the
[\`m.forget_forced_upon_leave\`](https://spec.matrix.org/v1.18/client-server-api/#mforget_forced_upon_leave-capability)
capability.

If the server doesn't automatically forget the room, the user will still be
allowed to retrieve history from the room which they were previously allowed
to see.`,
          operationId: "leaveRoom",
          parameters: [
            {
              description: "The room identifier to leave.",
              example: "!nkl290a:matrix.org",
              in: "path",
              name: "roomId",
              required: !0,
              schema: { type: "string" },
            },
          ],
          requestBody: {
            content: {
              "application/json": {
                schema: {
                  example: {
                    reason: "Saying farewell - thanks for the support!",
                  },
                  properties: {
                    reason: {
                      description:
                        "Optional reason to be included as the `reason` on the subsequent\nmembership event.",
                      type: "string",
                      "x-addedInMatrixVersion": "1.1",
                    },
                  },
                  type: "object",
                },
              },
            },
            required: !0,
          },
          responses: {
            200: {
              content: {
                "application/json": {
                  examples: { response: { value: {} } },
                  schema: { type: "object" },
                },
              },
              description: "The room has been left.",
            },
            429: {
              content: {
                "application/json": {
                  schema: {
                    allOf: [
                      {
                        description: "A Matrix-level Error",
                        properties: {
                          errcode: {
                            description: "An error code.",
                            example: "M_UNKNOWN",
                            type: "string",
                          },
                          error: {
                            description: "A human-readable error message.",
                            example: "An unknown error occurred",
                            type: "string",
                          },
                        },
                        required: ["errcode"],
                        title: "Error",
                        type: "object",
                      },
                      {
                        description:
                          "The rate limit was reached for this request",
                        properties: {
                          errcode: {
                            description: "The M_LIMIT_EXCEEDED error code",
                            example: "M_LIMIT_EXCEEDED",
                            type: "string",
                          },
                          error: {
                            description: "A human-readable error message.",
                            example: "Too many requests",
                            type: "string",
                          },
                          retry_after_ms: {
                            description: `The amount of time in milliseconds the client should wait
before trying the request again.`,
                            example: 2e3,
                            type: "integer",
                          },
                        },
                        required: ["errcode"],
                        title: "RateLimitError",
                        type: "object",
                      },
                    ],
                  },
                },
              },
              description: "This request was rate-limited.",
            },
          },
          security: [{ accessTokenQuery: [] }, { accessTokenBearer: [] }],
          summary:
            "Stop the requesting user participating in a particular room.",
          tags: ["Room membership"],
          "x-changedInMatrixVersion": {
            1.18: `Servers may additionally forget the room provided that they make this behavior
transparent.`,
          },
        },
      },
      "/_matrix/client/v3/createRoom": {
        post: {
          description:
            "Create a new room with various configuration options.\n\nThe server MUST apply the normal state resolution rules when creating\nthe new room, including checking power levels for each event. It MUST\napply the events implied by the request in the following order:\n\n1. The `m.room.create` event itself. Must be the first event in the\n   room.\n\n2. An `m.room.member` event for the creator to join the room. This is\n   needed so the remaining events can be sent.\n\n3. A default `m.room.power_levels` event. Overridden by the\n   `power_level_content_override` parameter.\n\n   In [room versions](https://spec.matrix.org/v1.18/rooms) 1 through 11, the room creator (and not\n   other members) will be given permission to send state events.\n\n   In room versions 12 and later, the room creator is given infinite\n   power level and cannot be specified in the `users` field of\n   `m.room.power_levels`, so is not listed explicitly.\n\n   **Note**: For `trusted_private_chat`, the users specified in the\n   `invite` parameter SHOULD also be appended to `additional_creators`\n   by the server, per the `creation_content` parameter.\n\n   If the room's version is 12 or higher, the power level for sending\n   `m.room.tombstone` events MUST explicitly be higher than `state_default`.\n   For example, set to 150 instead of 100.\n\n4. An `m.room.canonical_alias` event if `room_alias_name` is given.\n\n5. Events set by the `preset`. Currently these are the `m.room.join_rules`,\n   `m.room.history_visibility`, and `m.room.guest_access` state events.\n\n6. Events listed in `initial_state`, in the order that they are\n   listed.\n\n7. Events implied by `name` and `topic` (`m.room.name` and `m.room.topic`\n   state events).\n\n8. Invite events implied by `invite` and `invite_3pid` (`m.room.member` with\n   `membership: invite` and `m.room.third_party_invite`).\n\nThe available presets do the following with respect to room state:\n\n| Preset                 | `join_rules` | `history_visibility` | `guest_access` | Other |\n|------------------------|--------------|----------------------|----------------|-------|\n| `private_chat`         | `invite`     | `shared`             | `can_join`     |       |\n| `trusted_private_chat` | `invite`     | `shared`             | `can_join`     | All invitees are given the same power level as the room creator. |\n| `public_chat`          | `public`     | `shared`             | `forbidden`    |       |\n\nThe server will create a `m.room.create` event in the room with the\nrequesting user as the creator, alongside other keys provided in the\n`creation_content` or implied by behaviour of `creation_content`.",
          operationId: "createRoom",
          requestBody: {
            content: {
              "application/json": {
                schema: {
                  example: {
                    creation_content: { "m.federate": !1 },
                    name: "The Grand Duke Pub",
                    preset: "public_chat",
                    room_alias_name: "thepub",
                    topic: "All about happy hour",
                  },
                  properties: {
                    creation_content: {
                      description:
                        "Extra keys, such as `m.federate`, to be added to the content\nof the [`m.room.create`](https://spec.matrix.org/v1.18/client-server-api/#mroomcreate) event.\n\nThe server will overwrite the following\nkeys: `creator`, `room_version`. Future versions of the specification\nmay allow the server to overwrite other keys.\n\nWhen using the `trusted_private_chat` preset, the server SHOULD combine\n`additional_creators` specified here and the `invite` array into the\neventual `m.room.create` event's `additional_creators`, deduplicating\nbetween the two parameters.",
                      title: "CreationContent",
                      type: "object",
                      "x-changedInMatrixVersion": {
                        1.16: "Added server behaviour for how to handle `trusted_private_chat` and invited users.",
                      },
                    },
                    initial_state: {
                      description:
                        "A list of state events to set in the new room. This allows\nthe user to override the default state events set in the new\nroom. The expected format of the state events are an object\nwith type, state_key and content keys set.\n\nTakes precedence over events set by `preset`, but gets\noverridden by `name` and `topic` keys.",
                      items: {
                        properties: {
                          content: {
                            description: "The content of the event.",
                            type: "object",
                          },
                          state_key: {
                            description:
                              "The state_key of the state event. Defaults to an empty string.",
                            type: "string",
                          },
                          type: {
                            description: "The type of event to send.",
                            type: "string",
                          },
                        },
                        required: ["type", "content"],
                        title: "StateEvent",
                        type: "object",
                      },
                      type: "array",
                    },
                    invite: {
                      description: `A list of user IDs to invite to the room. This will tell the
server to invite everyone in the list to the newly created room.`,
                      items: { type: "string" },
                      type: "array",
                    },
                    invite_3pid: {
                      description: `A list of objects representing third-party IDs to invite into
the room.`,
                      items: {
                        example: {
                          address: "cheeky@monkey.com",
                          id_access_token: "abc123_OpaqueString",
                          id_server: "matrix.org",
                          medium: "email",
                        },
                        properties: {
                          address: {
                            description:
                              "The invitee's third-party identifier.",
                            type: "string",
                          },
                          id_access_token: {
                            description: `An access token previously registered with the identity server. Servers
can treat this as optional to distinguish between r0.5-compatible clients
and this specification version.`,
                            type: "string",
                          },
                          id_server: {
                            description:
                              "The hostname+port of the identity server which should be used for third-party identifier lookups.",
                            type: "string",
                          },
                          medium: {
                            description:
                              "The kind of address being passed in the address field, for example `email`\n(see [the list of recognised values](https://spec.matrix.org/v1.18/appendices/#3pid-types)).",
                            type: "string",
                          },
                        },
                        required: [
                          "id_server",
                          "id_access_token",
                          "medium",
                          "address",
                        ],
                        title: "Invite3pid",
                        type: "object",
                      },
                      type: "array",
                    },
                    is_direct: {
                      description:
                        "This flag makes the server set the `is_direct` flag on the\n`m.room.member` events sent to the users in `invite` and\n`invite_3pid`. See [Direct Messaging](https://spec.matrix.org/v1.18/client-server-api/#direct-messaging) for more information.",
                      type: "boolean",
                    },
                    name: {
                      description:
                        "If this is included, an [`m.room.name`](https://spec.matrix.org/v1.18/client-server-api/#mroomname) event\nwill be sent into the room to indicate the name for the room.\nThis overwrites any [`m.room.name`](https://spec.matrix.org/v1.18/client-server-api/#mroomname)\nevent in `initial_state`.",
                      type: "string",
                    },
                    power_level_content_override: {
                      description: `The power level content to override in the default power level
event. This object is applied on top of the generated
[\`m.room.power_levels\`](https://spec.matrix.org/v1.18/client-server-api/#mroompower_levels)
event content prior to it being sent to the room. Defaults to
overriding nothing.`,
                      title: "Power Level Event Content",
                      type: "object",
                    },
                    preset: {
                      description:
                        "Convenience parameter for setting various default state events\nbased on a preset.\n\nIf unspecified, the server should use the `visibility` to determine\nwhich preset to use. A visibility of `public` equates to a preset of\n`public_chat` and `private` visibility equates to a preset of\n`private_chat`.",
                      enum: [
                        "private_chat",
                        "public_chat",
                        "trusted_private_chat",
                      ],
                      type: "string",
                    },
                    room_alias_name: {
                      description: `The desired room alias **local part**. If this is included, a
room alias will be created and mapped to the newly created
room. The alias will belong on the *same* homeserver which
created the room. For example, if this was set to "foo" and
sent to the homeserver "example.com" the complete room alias
would be \`#foo:example.com\`.

The complete room alias will become the canonical alias for
the room and an \`m.room.canonical_alias\` event will be sent
into the room.`,
                      type: "string",
                    },
                    room_version: {
                      description: `The room version to set for the room. If not provided, the homeserver is
to use its configured default. If provided, the homeserver will return a
400 error with the errcode \`M_UNSUPPORTED_ROOM_VERSION\` if it does not
support the room version.`,
                      example: "1",
                      type: "string",
                    },
                    topic: {
                      description:
                        "If this is included, an [`m.room.topic`](https://spec.matrix.org/v1.18/client-server-api/#mroomtopic)\nevent with a `text/plain` mimetype will be sent into the room\nto indicate the topic for the room. This overwrites any\n[`m.room.topic`](https://spec.matrix.org/v1.18/client-server-api/#mroomtopic) event in `initial_state`.",
                      type: "string",
                    },
                    visibility: {
                      description:
                        "The room's visibility in the server's\n[published room directory](https://spec.matrix.org/v1.18/client-server-api#published-room-directory).\nDefaults to `private`.",
                      enum: ["public", "private"],
                      type: "string",
                    },
                  },
                  type: "object",
                },
              },
            },
            description: "The desired room configuration.",
            required: !0,
          },
          responses: {
            200: {
              content: {
                "application/json": {
                  examples: {
                    response: {
                      value: { room_id: "!sefiuhWgwghwWgh:example.com" },
                    },
                  },
                  schema: {
                    description: "Information about the newly created room.",
                    properties: {
                      room_id: {
                        description: "The created room's ID.",
                        type: "string",
                      },
                    },
                    required: ["room_id"],
                    type: "object",
                  },
                },
              },
              description: "Information about the newly created room.",
            },
            400: {
              content: {
                "application/json": {
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "The request is invalid. A meaningful `errcode` and description\nerror text will be returned. Example reasons for rejection include:\n\n- The request body is malformed (`errcode` set to `M_BAD_JSON`\n  or `M_NOT_JSON`).\n\n- The room alias specified is already taken (`errcode` set to\n  `M_ROOM_IN_USE`).\n\n- The initial state implied by the parameters to the request is\n  invalid: for example, the user's `power_level` is set below\n  that necessary to set the room name (`errcode` set to\n  `M_INVALID_ROOM_STATE`).\n\n- The homeserver doesn't support the requested room version, or\n  one or more users being invited to the new room are residents\n  of a homeserver which does not support the requested room version.\n  The `errcode` will be `M_UNSUPPORTED_ROOM_VERSION` in these\n  cases.",
            },
            403: {
              content: {
                "application/json": {
                  schema: {
                    description: "A Matrix-level Error",
                    properties: {
                      errcode: {
                        description: "An error code.",
                        example: "M_UNKNOWN",
                        type: "string",
                      },
                      error: {
                        description: "A human-readable error message.",
                        example: "An unknown error occurred",
                        type: "string",
                      },
                    },
                    required: ["errcode"],
                    title: "Error",
                    type: "object",
                  },
                },
              },
              description:
                "Creating the room is not allowed.\n\n**[Added in `v1.18`]**  The `M_INVITE_BLOCKED` error code is used to\nindicate that one of the homeservers of the invited users rejected\nthe invite due to [invite blocking](https://spec.matrix.org/v1.18/client-server-api/#invite-permission).",
            },
          },
          security: [{ accessTokenQuery: [] }, { accessTokenBearer: [] }],
          summary: "Create a new room",
          tags: ["Room creation"],
          "x-changedInMatrixVersion": {
            1.16: "Added server behaviour for how the initial power levels change depending on room version.",
          },
        },
      },
    },
  },
  g = "Setup",
  b = [{ bearerAuth: [] }],
  ce = [{ bearerAuth: [] }, {}],
  _ = [],
  m = (o) => ({ schema: o });
function de(o, n, r) {
  const i = (t, l, u, a, p, w = x, T = b, y = "Setup state updated") => {
    o.registerPath({
      method: "post",
      path: t,
      summary: l,
      description: u,
      tags: [g],
      operationId: a,
      security: T,
      request: { body: { content: { "application/json": m(p) } } },
      responses: r({
        200: { description: y, content: { "application/json": m(w) } },
        ...n,
      }),
    });
  };
  (o.registerPath({
    method: "post",
    path: "/v1/app/setup/start",
    summary: "Start Beeper app setup",
    description:
      "Start setting up Beeper Desktop or Beeper Server. The flow supports existing Beeper accounts and new account creation.",
    tags: [g],
    operationId: "appSetupStart",
    security: _,
    responses: r({
      200: {
        description: "Sign-in request created",
        content: { "application/json": m(K) },
      },
      ...n,
    }),
  }),
    o.registerPath({
      method: "post",
      path: "/v1/app/setup/email",
      summary: "Send setup sign-in code",
      description:
        "Send a sign-in code to the user email address for app setup.",
      tags: [g],
      operationId: "appSetupEmail",
      security: _,
      request: { body: { content: { "application/json": m(W) } } },
      responses: r({ 204: { description: "Sign-in code sent" }, ...n }),
    }),
    i(
      "/v1/app/setup/response",
      "Complete setup sign-in with code",
      "Finish setup sign-in with the code sent to the user email address. If the user needs a new account, the response includes account creation copy and username suggestions.",
      "appSetupResponse",
      z,
      I,
      _,
      "Sign-in completed",
    ),
    i(
      "/v1/app/setup/register",
      "Create account for setup",
      "Create a Beeper account after the user chooses a username and accepts the Terms of Use.",
      "appSetupRegister",
      L,
      S,
      _,
      "Account created",
    ),
    o.registerPath({
      method: "get",
      path: "/v1/app/setup",
      summary: "Get Beeper app setup state",
      description:
        "Return the current Beeper Desktop or Beeper Server sign-in and encrypted messaging setup state. This endpoint is public before sign-in so apps can discover that sign-in is needed; after sign-in, pass a read token.",
      tags: [g],
      operationId: "appSetupRetrieve",
      security: ce,
      responses: r({
        200: {
          description: "Current app setup state",
          content: { "application/json": m(j) },
        },
        ...n,
      }),
    }),
    i(
      "/v1/app/setup/verification/recovery-key",
      "Verify with recovery key",
      "Unlock encrypted messages with the user recovery key.",
      "appSetupVerificationRecoveryKey",
      G,
      x,
    ),
    i(
      "/v1/app/setup/verification/recovery-key/reset",
      "Create new recovery key",
      "Create a new recovery key when the user cannot use the existing one.",
      "appSetupVerificationRecoveryKeyReset",
      F,
      k,
    ),
    i(
      "/v1/app/setup/verification/recovery-key/reset/confirm",
      "Confirm new recovery key",
      "Confirm that the new recovery key should be used for this account.",
      "appSetupVerificationRecoveryKeyResetConfirm",
      H,
      x,
    ),
    o.registerPath({
      method: "get",
      path: "/v1/app/setup/verifications",
      summary: "List active verifications",
      description:
        "List pending and active device verifications. Use this to recover state without a WebSocket connection.",
      tags: [g],
      operationId: "appSetupVerificationsList",
      security: b,
      responses: r({
        200: {
          description: "Active verifications",
          content: { "application/json": m($) },
        },
        ...n,
      }),
    }),
    i(
      "/v1/app/setup/verifications",
      "Start device verification",
      "Start verifying this device from another signed-in device.",
      "appSetupVerificationsCreate",
      J,
      f,
    ),
    i(
      "/v1/app/setup/verifications/qr/scan",
      "Scan verification QR code",
      "Submit the QR code scanned from another signed-in device.",
      "appSetupVerificationsQRScan",
      Q,
      f,
    ),
    o.registerPath({
      method: "get",
      path: "/v1/app/setup/verifications/{verificationID}",
      summary: "Get verification",
      description:
        "Get the current state of a device verification transaction.",
      tags: [g],
      operationId: "appSetupVerificationsGet",
      security: b,
      request: { params: A },
      responses: r({
        200: {
          description: "Verification state",
          content: { "application/json": m(f) },
        },
        ...n,
      }),
    }));
  const d = (t, l, u, a, p) => {
    o.registerPath({
      method: "post",
      path: t,
      summary: l,
      description: u,
      tags: [g],
      operationId: a,
      security: b,
      request: {
        params: A,
        ...(p ? { body: { content: { "application/json": m(p) } } } : {}),
      },
      responses: r({
        200: {
          description: "Verification state",
          content: { "application/json": m(f) },
        },
        ...n,
      }),
    });
  };
  (d(
    "/v1/app/setup/verifications/{verificationID}/accept",
    "Accept device verification",
    "Accept an incoming device verification request.",
    "appSetupVerificationsAccept",
  ),
    d(
      "/v1/app/setup/verifications/{verificationID}/cancel",
      "Cancel device verification",
      "Cancel an active device verification request.",
      "appSetupVerificationsCancel",
      Y,
    ),
    d(
      "/v1/app/setup/verifications/{verificationID}/qr/confirm-scanned",
      "Confirm QR code scan",
      "Confirm that another device scanned this device QR code.",
      "appSetupVerificationsQRConfirmScanned",
    ),
    d(
      "/v1/app/setup/verifications/{verificationID}/sas/start",
      "Start emoji verification",
      "Start emoji comparison for device verification.",
      "appSetupVerificationsSASStart",
    ),
    d(
      "/v1/app/setup/verifications/{verificationID}/sas/confirm",
      "Confirm emoji verification",
      "Confirm that the emoji or number sequence matches on both devices.",
      "appSetupVerificationsSASConfirm",
    ));
}
const me = /:([A-Za-z0-9_]+)/g,
  he = (o) => o.replace(me, (n, r) => `{${r}}`),
  le = "/_matrix/client/v3/rooms/{roomId}/state/{eventType}/{stateKey}",
  ue = "/_matrix/client/v3/join/{roomIdOrAlias}",
  ve = (o, n) => {
    const r = { ...n, security: [{ bearerAuth: [] }] };
    return o === ue
      ? {
          ...r,
          parameters: r.parameters?.map((i) =>
            i.name === "roomIdOrAlias"
              ? { ...i, example: "!monkeys:matrix.org" }
              : i,
          ),
          requestBody: {
            ...r.requestBody,
            content: {
              "application/json": {
                schema: {
                  ...r.requestBody?.content?.["application/json"]?.schema,
                  properties: {
                    ...r.requestBody?.content?.["application/json"]?.schema
                      ?.properties,
                    third_party_signed: {
                      ...r.requestBody?.content?.["application/json"]?.schema
                        ?.properties?.third_party_signed,
                      allOf: r.requestBody?.content?.[
                        "application/json"
                      ]?.schema?.properties?.third_party_signed?.allOf?.map(
                        (i) => ({
                          ...i,
                          properties: {
                            ...i.properties,
                            mxid: { ...i.properties?.mxid, example: "bob" },
                            sender: {
                              ...i.properties?.sender,
                              example: "alice",
                            },
                          },
                        }),
                      ),
                    },
                  },
                },
              },
            },
          },
        }
      : o !== le
        ? r
        : {
            ...r,
            parameters: r.parameters?.map((i) =>
              i.name === "stateKey" ? { ...i, example: "state_key" } : i,
            ),
            responses: {
              ...r.responses,
              200: {
                ...r.responses?.[200],
                content: {
                  "application/json": {
                    schema: { type: "object", additionalProperties: !0 },
                  },
                },
              },
            },
          };
  },
  ge = (o) => {
    for (const [n, r] of Object.entries(pe.paths))
      o.paths[n] = Object.fromEntries(
        Object.entries(r).map(([i, d]) => [i, ve(n, d)]),
      );
  };
function zt(o, n = {}) {
  const r = n.includeMatrixCompat ?? !0,
    i = n.listAuthPaths ?? !1,
    d = new Set(n.excludeRouteNames ?? []),
    t = new E();
  (t.register("Error", q),
    t.register("SetSubscriptionsMessage", X),
    t.register("WSReadyMessage", Z),
    t.register("WSSubscriptionsUpdatedMessage", ee),
    t.register("WSErrorMessage", te),
    t.register("WSDomainEventMessage", re),
    t.register("WSAppStateUpdatedMessage", oe),
    t.register("WSIncomingMessage", ie),
    t.register("WSOutgoingMessage", ne),
    t.register("AppSetupRegistrationRequiredResponse", se),
    t.register("AppSetupCompleteResponse", S),
    t.register("AppSetupResponseOutput", I),
    t.register("AppSetupStateResponse", x),
    t.register("AppStateSnapshot", j),
    t.register("AppVerification", ae),
    t.register("RecoveryKeyResetResponse", k),
    t.register("SetupVerificationResponse", f),
    t.registerParameter("ChatID", D),
    t.registerParameter("AccountID", M),
    t.registerParameter("Cursor", R),
    t.registerParameter("Direction", O));
  const l = { $ref: "#/components/headers/X-Beeper-Desktop-Version" },
    u = (h) =>
      Object.fromEntries(
        Object.entries(h).map(([s, c]) => [
          s,
          "$ref" in c
            ? c
            : {
                ...c,
                headers: { ...c.headers, "X-Beeper-Desktop-Version": l },
              },
        ]),
      ),
    a = (h, s) =>
      t.registerComponent("responses", h, {
        description: s,
        headers: { "X-Beeper-Desktop-Version": l },
        content: {
          "application/json": {
            schema: { $ref: "#/components/schemas/Error" },
          },
        },
      }).ref,
    p = {
      400: a("BadRequest", "Invalid request parameters"),
      401: a("UnauthorizedError", "Access token is missing or invalid"),
      403: a("ForbiddenError", "Access token does not have the required scope"),
      404: a("NotFound", "Resource not found"),
      409: a("Conflict", "Request conflicts with the current resource state"),
      422: a("UnprocessableEntity", "Unprocessable entity - validation error"),
      429: a("TooManyRequests", "Too many requests - rate limit exceeded"),
      500: a("InternalServerError", "Internal server error"),
      502: a("BadGateway", "Upstream dependency returned an invalid response"),
    };
  (t.registerComponent("headers", "X-Beeper-Desktop-Version", {
    description: "Beeper Desktop application version providing this response.",
    schema: { type: "string", example: "4.0.0" },
  }),
    t.registerComponent("securitySchemes", "bearerAuth", {
      type: "http",
      scheme: "bearer",
      description:
        "Bearer token authentication. Access token obtained via OAuth2 PKCE flow or created in-app. Required for all API operations.",
    }),
    t.registerComponent("securitySchemes", "oauth2", {
      type: "oauth2",
      description:
        "OAuth2 Authorization Code flow with PKCE for obtaining bearer access tokens. Used by MCP servers to authenticate clients.",
      flows: {
        authorizationCode: {
          authorizationUrl: `${o}/oauth/authorize`,
          tokenUrl: `${o}/oauth/token`,
          scopes: {
            read: "Read access to messages, chats, and accounts",
            write:
              "Write access to send messages, edit messages, react to messages, archive chats, and set reminders",
          },
        },
      },
    }));
  for (const [h, s] of Object.entries(C)) {
    if (d.has(h)) continue;
    const c = he(s.path);
    let v;
    (s.openApiSuccessResponses
      ? (v = { ...s.openApiSuccessResponses, ...p })
      : s.outputSchema instanceof e.ZodVoid
        ? (v = { 204: { description: "Request completed successfully" }, ...p })
        : (v = {
            200: {
              description: "Request completed successfully",
              content: { "application/json": { schema: s.outputSchema } },
            },
            ...p,
          }),
      t.registerPath({
        method: s.method,
        path: c,
        summary: s.summary,
        description: s.description,
        tags: s.tags,
        operationId: h,
        security: [{ bearerAuth: [] }],
        request: s.request,
        responses: u(v),
      }));
  }
  const w = `OAuth2 Authorization Code with PKCE. SDK code is not generated for these endpoints; call them directly.

Flow: register a public client with POST /oauth/register, send the user to GET /oauth/authorize, then exchange the returned code with POST /oauth/token. Use the returned access token as Authorization: Bearer on every other endpoint.

Notes: Use PKCE S256. Time-limited access tokens include expires_in; tokens without it do not expire. /oauth/token, /oauth/introspect, and /oauth/revoke use application/x-www-form-urlencoded bodies. Scopes are read and write.`;
  (de(t, p, u),
    t.registerPath({
      method: "get",
      path: "/v1/info",
      summary: "Retrieve server info",
      description:
        "Returns app, platform, server, endpoint discovery, OAuth, and WebSocket metadata for this Beeper Client API server.",
      tags: ["Server"],
      operationId: "getInfo",
      security: [],
      responses: u({
        200: {
          description: "Beeper Client API server info",
          content: { "application/json": { schema: V } },
        },
        500: p[500],
      }),
    }),
    i &&
      (t.registerPath({
        method: "get",
        path: "/oauth/userinfo",
        summary: "Get token info",
        description: "Returns information about the authenticated token",
        tags: ["OAuth"],
        operationId: "oauth_get_user_info",
        security: [{ bearerAuth: [] }],
        responses: {
          200: {
            description: "Token information",
            content: { "application/json": { schema: N } },
          },
          401: p[401],
        },
      }),
      t.registerPath({
        method: "get",
        path: "/oauth/authorize",
        summary: "Authorize client (PKCE)",
        description:
          "Starts the OAuth2 Authorization Code flow with PKCE. Renders an HTML consent page where the user can approve the requested scopes.",
        tags: ["OAuth"],
        operationId: "oauth_authorize",
        security: [],
        request: {
          query: e.object({
            client_id: e.string().describe("Client identifier"),
            redirect_uri: e
              .string()
              .url()
              .describe("Redirect URI to receive the authorization code"),
            state: e
              .string()
              .optional()
              .describe(
                "Opaque value to maintain state between the request and callback",
              ),
            scope: e
              .string()
              .default("read write")
              .describe("Space-delimited scopes to request"),
            response_type: e.literal("code").describe('Must be "code"'),
            code_challenge: e.string().describe("PKCE code challenge (S256)"),
            code_challenge_method: e
              .literal("S256")
              .optional()
              .describe("PKCE method; only S256 is supported"),
            resource: e
              .string()
              .optional()
              .describe("Requested resource (RFC 8707)"),
          }),
        },
        responses: {
          200: {
            description: "HTML consent page",
            content: { "text/html": { schema: { type: "string" } } },
          },
          400: {
            description: "Invalid request parameters",
            content: { "text/html": { schema: { type: "string" } } },
          },
        },
      }),
      t.registerPath({
        method: "post",
        path: "/oauth/authorize/callback",
        summary: "Authorization approval callback",
        description:
          "Completes the OAuth2 approval initiated by the consent screen and returns an authorization code if approved.",
        tags: ["OAuth"],
        operationId: "oauth_authorize_callback",
        security: [],
        request: {
          body: {
            content: {
              "application/json": {
                schema: e.object({
                  clientInfo: e
                    .object({
                      name: e.string().optional(),
                      version: e.string().optional(),
                      userAgent: e.string().optional(),
                      remoteAddress: e.string().optional(),
                      clientID: e.string().optional(),
                      clientURI: e.string().optional(),
                    })
                    .optional(),
                  scopes: e
                    .array(e.enum(["read", "write"]))
                    .default(["read"])
                    .describe("Requested scopes"),
                  state: e.string().optional(),
                  codeChallenge: e
                    .string()
                    .optional()
                    .describe("PKCE code challenge from the authorize request"),
                  codeChallengeMethod: e
                    .enum(["S256"])
                    .optional()
                    .describe("PKCE method; only S256 is supported"),
                  resource: e
                    .string()
                    .optional()
                    .describe("Requested resource (RFC 8707)"),
                }),
              },
            },
          },
        },
        responses: {
          200: {
            description: "Authorization result",
            content: {
              "application/json": {
                schema: e.object({
                  code: e
                    .string()
                    .optional()
                    .describe("Authorization code to exchange for a token"),
                  error: e
                    .string()
                    .optional()
                    .describe(
                      "Error code if authorization was denied or failed",
                    ),
                  state: e.string().optional(),
                }),
              },
            },
          },
        },
      }),
      t.registerPath({
        method: "post",
        path: "/oauth/introspect",
        summary: "Introspect token",
        description:
          "Returns metadata for a token according to OAuth2 Token Introspection (RFC 7662).",
        tags: ["OAuth"],
        operationId: "oauth_introspect_token",
        security: [],
        request: {
          body: {
            content: { "application/x-www-form-urlencoded": { schema: U } },
          },
        },
        responses: {
          200: {
            description: "Token introspection result",
            content: { "application/json": { schema: P } },
          },
          400: {
            description: "Invalid introspection request",
            content: {
              "application/json": {
                schema: e.object({
                  error: e.literal("invalid_request"),
                  error_description: e.string(),
                }),
              },
            },
          },
          500: {
            description: "Server error",
            content: {
              "application/json": {
                schema: e.object({
                  error: e.literal("server_error"),
                  error_description: e.string(),
                }),
              },
            },
          },
        },
      }),
      t.registerPath({
        method: "post",
        path: "/oauth/revoke",
        summary: "Revoke token",
        description: "Revoke an access token or refresh token (RFC 7009)",
        tags: ["OAuth"],
        operationId: "oauth_revoke_token",
        security: [],
        request: {
          body: {
            content: {
              "application/x-www-form-urlencoded": {
                schema: e.object({
                  token: e.string().describe("The token to revoke"),
                  token_type_hint: e
                    .enum(["access_token", "refresh_token"])
                    .optional()
                    .describe(
                      "Token type hint (RFC 7009). Refresh tokens are not issued today, but the hint is accepted for RFC compatibility.",
                    ),
                }),
              },
            },
          },
        },
        responses: {
          200: {
            description:
              "Token revoked successfully (empty response per RFC 7009)",
          },
        },
      }),
      t.registerPath({
        method: "post",
        path: "/oauth/token",
        summary: "Exchange authorization code for token",
        description:
          "Exchanges an authorization code (PKCE) for an access token. Supports the Authorization Code grant with PKCE.",
        tags: ["OAuth"],
        operationId: "oauth_token",
        security: [],
        request: {
          body: {
            content: {
              "application/x-www-form-urlencoded": {
                schema: e.object({
                  grant_type: e
                    .literal("authorization_code")
                    .describe(
                      "OAuth2 grant type; only authorization_code is supported",
                    ),
                  code: e
                    .string()
                    .describe(
                      "Authorization code returned by the authorize step",
                    ),
                  code_verifier: e.string().describe("PKCE code verifier"),
                  client_id: e
                    .string()
                    .optional()
                    .describe("Client ID (optional for public PKCE clients)"),
                  resource: e
                    .string()
                    .optional()
                    .describe("Resource parameter (RFC 8707)"),
                }),
              },
            },
          },
        },
        responses: {
          200: {
            description: "Access token response",
            content: {
              "application/json": {
                schema: e.object({
                  access_token: e.string(),
                  token_type: e.literal("Bearer"),
                  expires_in: e.number().int().optional(),
                  scope: e.string(),
                }),
              },
            },
          },
          400: {
            description: "Token request error",
            content: {
              "application/json": {
                schema: e.object({
                  error: e.string(),
                  error_description: e.string(),
                }),
              },
            },
          },
          500: {
            description: "Server error",
            content: {
              "application/json": { schema: e.object({ error: e.string() }) },
            },
          },
        },
      }),
      t.registerPath({
        method: "post",
        path: "/oauth/register",
        summary: "Register OAuth2 client",
        description:
          "Registers a new OAuth2 public client using Dynamic Client Registration (RFC 7591). Returns client metadata.",
        tags: ["OAuth"],
        operationId: "oauth_register_client",
        security: [],
        request: {
          body: {
            content: {
              "application/json": {
                schema: e.object({
                  client_name: e
                    .string()
                    .describe("Human-readable client name"),
                  client_uri: e
                    .string()
                    .url()
                    .optional()
                    .describe("Client homepage"),
                  grant_types: e
                    .array(e.enum(["authorization_code"]))
                    .default(["authorization_code"])
                    .describe("Supported grant types"),
                  response_types: e
                    .array(e.enum(["code"]))
                    .default(["code"])
                    .describe("Supported response types"),
                  redirect_uris: e
                    .array(e.string().url())
                    .describe("Allowed redirect URIs"),
                  scope: e
                    .string()
                    .default("read write")
                    .describe("Default scopes"),
                  token_endpoint_auth_method: e
                    .enum(["none"])
                    .default("none")
                    .describe(
                      "Auth method for token endpoint; public clients use none",
                    ),
                }),
              },
            },
          },
        },
        responses: {
          201: {
            description: "Client registered",
            content: {
              "application/json": {
                schema: e.object({
                  client_id: e.string(),
                  client_name: e.string(),
                  client_uri: e.string().url().optional(),
                  grant_types: e.array(e.enum(["authorization_code"])),
                  response_types: e.array(e.enum(["code"])),
                  redirect_uris: e.array(e.string().url()),
                  scope: e.string(),
                  token_endpoint_auth_method: e.enum(["none"]),
                  client_id_issued_at: e.number().int(),
                  authorization_endpoint: e.string().url(),
                  token_endpoint: e.string().url(),
                }),
              },
            },
          },
          400: {
            description: "Invalid client metadata",
            content: {
              "application/json": {
                schema: e.object({
                  error: e.literal("invalid_client_metadata"),
                  error_description: e.string(),
                }),
              },
            },
          },
        },
      })));
  const y = new B(t.definitions).generateDocument({
    openapi: "3.1.0",
    info: {
      title: "Beeper Client API",
      version: "5.0.0",
      description:
        'Beeper Client API is Beeper\'s local HTTP and WebSocket API, served by Beeper Desktop and Beeper Server. One authentication flow and one chat shape work across WhatsApp, iMessage, Telegram, Slack, Matrix, Discord, Twitter/X, Signal, and more.\n\nBeeper is built on the Matrix standard, so some identifiers and rich text use Matrix conventions. `mxc://` and `localmxc://` URLs identify message media. Message text is returned as rich text. `@room` means everyone in a group chat.\n\n## Quickstart\n1. Discover the server with `GET /v1/info`. The Beeper Client API is local-only unless the user has enabled remote access.\n2. Authenticate with an access token from Beeper Desktop or Beeper Server, or run OAuth2 Authorization Code with PKCE under the OAuth tag.\n3. Call `GET /v1/accounts` to see connected chat accounts, then `GET /v1/chats` for the unified inbox.\n\n## WebSocket\nConnect to `/v1/ws` with the same Bearer token in the upgrade request. Use a WebSocket client that can send the Authorization header. After the server sends `ready`, send `{"type":"subscriptions.set","chatIDs":["*"],"app":{"state":true}}` to receive chat updates and setup state updates. The server replies with `subscriptions.updated`, then streams `chat.upserted`, `chat.deleted`, `message.upserted`, `message.deleted`, and `app.state.updated`.\n\nDelivery is at-most-once. There is no replay on reconnect, and `seq` is per connection. Refetch via HTTP after a disconnect to reconcile drift. Initial subscription state is empty; `subscriptions.set` replaces previous state; `["*"]` cannot be combined with specific chat IDs.\n\n## Conventions\n- IDs and cursors are opaque strings.\n- Timestamps are ISO 8601 with timezone, except OAuth fields that use Unix seconds per RFC.\n- Pagination is `cursor` plus `direction=before|after`.\n- Sends return a `pendingMessageID`; resolve it with `GET /v1/chats/{chatID}/messages/{messageID}` or wait for `message.upserted` over the WebSocket.\n- Optional fields may be omitted when unknown. Nullable write fields use `null` as an explicit clear operation.\n- Every response carries `X-Beeper-Desktop-Version` so clients can tell which app version produced it.',
      termsOfService: "https://www.beeper.com/terms",
      contact: {
        name: "Beeper",
        email: "help@beeper.com",
        url: "https://www.beeper.com",
      },
      license: { name: "Proprietary", url: "https://www.beeper.com/terms" },
    },
    servers: [{ url: o, description: "Beeper Client API server" }],
    security: [{ bearerAuth: [] }],
    tags: [
      {
        name: "App",
        description: d.has("focusApp")
          ? "Top-level actions: run unified search across chats and messages."
          : "Top-level actions: focus Beeper Desktop, jump to a chat, or run unified search across chats and messages.",
      },
      {
        name: "Server",
        description:
          "Server discovery and capability metadata. Use /v1/info before authentication setup.",
      },
      {
        name: "Accounts",
        description:
          "Chat accounts connected to this Beeper Client API server. Each account represents one signed-in identity on a messaging network.",
      },
      {
        name: "Bridges",
        description:
          "Available bridges, bridge logins, login sessions for connect and reconnect flows, and advanced network capabilities.",
      },
      {
        name: "Contacts",
        description:
          "Per-account contacts and network lookup. The same person can appear under multiple accounts.",
      },
      {
        name: "Chats",
        description:
          "Chats, reminders, read state, archive state, Low Priority, mute, and other conversation metadata.",
      },
      {
        name: "Labels",
        description:
          "User-created labels that organize chats across accounts. Chats carry their labels, and chat search can filter by one.",
      },
      {
        name: "Messages",
        description:
          "Messages inside a chat: list, search, send, retrieve, edit, delete, and react.",
      },
      {
        name: "Files",
        description:
          "File upload, download, and streaming helpers for message attachments and drafts.",
      },
      {
        name: "Setup",
        description:
          "First-party sign-in and encrypted messaging setup for Beeper Desktop and Beeper Server.",
      },
      ...(r
        ? [
            {
              name: "Matrix",
              description: "Matrix-compatible APIs for accounts and rooms.",
            },
          ]
        : []),
      { name: "OAuth", description: w },
    ],
    externalDocs: {
      description: "Beeper Client API Documentation",
      url: "https://developers.beeper.com/desktop-api",
    },
  });
  r && ge(y);
  for (const h of Object.values(y.paths))
    for (const s of Object.values(h))
      if (!(!s || typeof s != "object" || !("responses" in s)))
        for (const c of Object.values(s.responses)) {
          if (!c || typeof c != "object" || "$ref" in c) continue;
          const v = c;
          v.headers = { ...v.headers, "X-Beeper-Desktop-Version": l };
        }
  return y;
}
export { zt as createOpenAPISpec };
//# sourceMappingURL=openapi-BK7IyLMq.mjs.map
