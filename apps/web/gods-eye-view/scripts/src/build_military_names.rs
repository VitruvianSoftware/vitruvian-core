// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeSet;
use std::path::PathBuf;

pub const RELEASE: &str = "2026-09-23.1";
pub const CLASSES: &[&str] = &[
    "military_land",
    "airfield",
    "naval_base",
    "range",
    "barracks",
    "base",
    "training_area",
];

const H_INIT: [u32; 8] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

pub fn sha256_hex(data: &[u8]) -> String {
    let mut h = H_INIT;
    let bit_len = (data.len() as u64) * 8;
    let mut padded = data.to_vec();
    padded.push(0x80);
    while padded.len() % 64 != 56 {
        padded.push(0);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in padded.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[4 * i],
                chunk[4 * i + 1],
                chunk[4 * i + 2],
                chunk[4 * i + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7)
                ^ w[i - 15].rotate_right(18)
                ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17)
                ^ w[i - 2].rotate_right(19)
                ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hv] = h;
        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hv
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);
            hv = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hv);
    }

    let mut hex = String::with_capacity(64);
    for word in &h {
        hex.push_str(&format!("{:08x}", word));
    }
    hex
}

pub fn parse_osm_record_id(s: &str) -> Option<(char, &str)> {
    let b = s.as_bytes();
    if b.is_empty() {
        return None;
    }
    let kind = b[0];
    if kind != b'n' && kind != b'w' && kind != b'r' {
        return None;
    }
    let mut i = 1usize;
    let d_start = i;
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
    }
    if i == d_start {
        return None;
    }
    let d_end = i;
    if i >= b.len() || b[i] != b'@' {
        return None;
    }
    i += 1;
    let a_start = i;
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
    }
    if i == a_start || i != b.len() {
        return None;
    }
    Some((kind as char, &s[d_start..d_end]))
}

fn round_half_to_even(v: f64) -> f64 {
    let floor = v.floor();
    let diff = v - floor;
    if (diff - 0.5).abs() < 1e-12 {
        if (floor as i64) % 2 == 0 {
            floor
        } else {
            floor + 1.0
        }
    } else {
        v.round()
    }
}

fn round_to(v: f64, places: u32) -> f64 {
    let factor = 10f64.powi(places as i32);
    round_half_to_even(v * factor) / factor
}

fn get_str<'a>(obj: &'a Value, key: &str) -> Result<&'a str, String> {
    obj.get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("Missing or non-string field '{}'", key))
}

fn get_f64(obj: &Value, key: &str) -> Result<f64, String> {
    obj.get(key)
        .and_then(Value::as_f64)
        .ok_or_else(|| format!("Missing or non-numeric field '{}'", key))
}

#[derive(Serialize)]
pub struct MilitaryNamesPack {
    pub release: String,
    pub snapshots: Vec<String>,
    pub classes: Vec<String>,
    pub records: Vec<Value>,
}

pub fn assemble_pack(rows: &[Value]) -> Result<MilitaryNamesPack, String> {
    let mut records: Vec<(char, u64, Value)> = Vec::with_capacity(rows.len());
    let mut snapshots = BTreeSet::new();

    for row in rows {
        let sources = row
            .get("sources")
            .and_then(Value::as_array)
            .ok_or("Missing 'sources' array")?;
        let source = sources
            .iter()
            .find(|s| s.get("dataset").and_then(Value::as_str) == Some("OpenStreetMap"))
            .ok_or("No OpenStreetMap source")?;
        let record_id = get_str(source, "record_id")?;
        let (kind_char, digits) =
            parse_osm_record_id(record_id).ok_or("Invalid typed OSM identity")?;
        let ident = format!("{}{}", kind_char, digits);
        let id_num: u64 = digits.parse().map_err(|_| "Invalid OSM id number")?;

        let bbox_obj = row.get("bbox").ok_or("Missing 'bbox'")?;
        let xmin = get_f64(bbox_obj, "xmin")?;
        let ymin = get_f64(bbox_obj, "ymin")?;
        let xmax = get_f64(bbox_obj, "xmax")?;
        let ymax = get_f64(bbox_obj, "ymax")?;
        let lon = get_f64(row, "lon")?;
        let lat = get_f64(row, "lat")?;
        let area = get_f64(row, "area")?;

        if !lon.is_finite()
            || !lat.is_finite()
            || !area.is_finite()
            || !xmin.is_finite()
            || !ymin.is_finite()
            || !xmax.is_finite()
            || !ymax.is_finite()
        {
            return Err("Invalid geometry measurement".into());
        }
        if !(xmin - 1e-7 <= lon && lon <= xmax + 1e-7)
            || !(ymin - 1e-7 <= lat && lat <= ymax + 1e-7)
        {
            return Err("Label outside source bounds".into());
        }

        let military = row
            .get("military")
            .and_then(Value::as_str)
            .unwrap_or("military_land");
        let class_idx = CLASSES.iter().position(|&c| c == military).unwrap_or(0);

        let name = get_str(row, "name")?;
        let lon_r = round_to(lon, 5);
        let lat_r = round_to(lat, 5);
        let xmin_r = round_to(xmin, 4);
        let ymin_r = round_to(ymin, 4);
        let xmax_r = round_to(xmax, 4);
        let ymax_r = round_to(ymax, 4);
        let area_int = (round_half_to_even(area.abs()) as i64).max(1);

        let version = get_str(source, "version")?;
        let snap_end = version.len().min(10);
        snapshots.insert(version[..snap_end].to_string());

        let record = Value::Array(vec![
            Value::String(ident),
            Value::String(name.to_string()),
            serde_json::Number::from_f64(lon_r)
                .map(Value::Number)
                .unwrap_or(Value::Null),
            serde_json::Number::from_f64(lat_r)
                .map(Value::Number)
                .unwrap_or(Value::Null),
            serde_json::Number::from_f64(xmin_r)
                .map(Value::Number)
                .unwrap_or(Value::Null),
            serde_json::Number::from_f64(ymin_r)
                .map(Value::Number)
                .unwrap_or(Value::Null),
            serde_json::Number::from_f64(xmax_r)
                .map(Value::Number)
                .unwrap_or(Value::Null),
            serde_json::Number::from_f64(ymax_r)
                .map(Value::Number)
                .unwrap_or(Value::Null),
            Value::Number(serde_json::Number::from(class_idx as u64)),
            Value::Number(serde_json::Number::from(area_int)),
        ]);
        records.push((kind_char, id_num, record));
    }

    records.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));

    for i in 1..records.len() {
        let prev = records[i - 1].2.as_array().unwrap()[0].as_str().unwrap();
        let curr = records[i].2.as_array().unwrap()[0].as_str().unwrap();
        if prev == curr {
            return Err("Duplicate OSM identity".into());
        }
    }

    Ok(MilitaryNamesPack {
        release: RELEASE.to_string(),
        snapshots: snapshots.into_iter().collect(),
        classes: CLASSES.iter().map(|s| s.to_string()).collect(),
        records: records.into_iter().map(|(_, _, r)| r).collect(),
    })
}

pub fn assemble(rows: &[Value]) -> Result<Value, String> {
    let pack = assemble_pack(rows)?;
    serde_json::to_value(&pack).map_err(|e| format!("Serialization failed: {}", e))
}

fn resolve_project_root() -> PathBuf {
    if let Ok(root) = std::env::var("GEV_PROJECT_ROOT") {
        return PathBuf::from(root);
    }
    let cwd = std::env::current_dir().unwrap_or_default();
    if cwd.join("scripts").is_dir() && cwd.join("src").is_dir() {
        return cwd;
    }
    cwd
}

pub fn run(args: &[String]) -> Result<(), String> {
    let mut cache: Option<PathBuf> = None;
    let mut extensions: Option<PathBuf> = None;
    let mut pack_override: Option<PathBuf> = None;
    let mut verify = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-h" | "--help" => {
                eprintln!(
                    "Usage: build-military-names --cache <path> [--extensions <path>] \
                     [--pack <path>] [--verify]"
                );
                return Ok(());
            }
            "--cache" => {
                i += 1;
                cache = Some(PathBuf::from(
                    args.get(i).ok_or("--cache requires a value")?,
                ));
            }
            "--extensions" => {
                i += 1;
                extensions = Some(PathBuf::from(
                    args.get(i).ok_or("--extensions requires a value")?,
                ));
            }
            "--pack" => {
                i += 1;
                pack_override = Some(PathBuf::from(
                    args.get(i).ok_or("--pack requires a value")?,
                ));
            }
            "--verify" => {
                verify = true;
            }
            other => return Err(format!("Unknown argument: {}", other)),
        }
        i += 1;
    }

    let _ = extensions;
    let cache = cache.ok_or("--cache is required")?;
    let root = resolve_project_root();
    let pack_dir =
        pack_override.unwrap_or_else(|| root.join("src/data/local_data/osm_military_names"));

    std::fs::create_dir_all(&cache).map_err(|e| format!("Cannot create cache dir: {}", e))?;
    let cached = cache.join(format!("military-names-{}.json", RELEASE));

    if !cached.exists() {
        return Err(format!(
            "Cached query result not found: {}. Run the Python script with DuckDB first.",
            cached.display()
        ));
    }

    let raw_rows =
        std::fs::read_to_string(&cached).map_err(|e| format!("Cannot read cache: {}", e))?;
    let rows: Vec<Value> =
        serde_json::from_str(&raw_rows).map_err(|e| format!("Invalid cache JSON: {}", e))?;
    let pack = assemble_pack(&rows)?;
    let raw = serde_json::to_string(&pack)
        .map_err(|e| format!("JSON serialization failed: {}", e))?;
    let raw_bytes = raw.as_bytes();
    let digest = sha256_hex(raw_bytes);

    if verify {
        let sha_path = pack_dir.join("names.sha256");
        let content = std::fs::read_to_string(&sha_path)
            .map_err(|e| format!("Cannot read {}: {}", sha_path.display(), e))?;
        let expected = content.split_whitespace().next().ok_or("Empty SHA-256 file")?;
        if digest != expected {
            return Err(format!("Output SHA-256 mismatch: {}", digest));
        }
    } else {
        std::fs::create_dir_all(&pack_dir)
            .map_err(|e| format!("Cannot create pack dir: {}", e))?;
        std::fs::write(pack_dir.join("names.json"), raw_bytes)
            .map_err(|e| format!("Cannot write names.json: {}", e))?;
        std::fs::write(
            pack_dir.join("names.sha256"),
            format!("{}  names.json\n", digest),
        )
        .map_err(|e| format!("Cannot write names.sha256: {}", e))?;
    }

    let record_count = pack.records.len();
    let summary = serde_json::json!({
        "records": record_count,
        "rawBytes": raw_bytes.len(),
        "sha256": digest,
    });
    println!("{}", serde_json::to_string(&summary).unwrap());
    Ok(())
}
