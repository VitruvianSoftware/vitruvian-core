-- Copyright (c) 2026 VitruvianSoftware
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

-- The relay's first schema: devices and a log of calls. The relay keeps no
-- content: `activity` holds the tool name, sizes, duration and outcome of a
-- call, never its arguments or its result.
--
-- Applied by src/store.rs at start, once, in one transaction. Every statement
-- is written so that running it again changes nothing.

CREATE TABLE IF NOT EXISTS schema_version (
    version integer NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
    id          text PRIMARY KEY,
    owner_sub   text NOT NULL,
    name        text NOT NULL,
    public_key  bytea NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    last_seen   timestamptz,
    revoked_at  timestamptz
);

CREATE INDEX IF NOT EXISTS devices_owner_sub_idx ON devices (owner_sub);

CREATE TABLE IF NOT EXISTS activity (
    id            bigserial PRIMARY KEY,
    at            timestamptz NOT NULL,
    owner_sub     text NOT NULL,
    device_id     text NOT NULL,
    client_id     text NOT NULL,
    tool          text NOT NULL,
    arg_bytes     integer,
    result_bytes  integer,
    duration_ms   integer,
    outcome       text NOT NULL
);

CREATE INDEX IF NOT EXISTS activity_owner_at_idx ON activity (owner_sub, at DESC);
