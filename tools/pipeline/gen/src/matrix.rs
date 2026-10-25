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

//! The GitHub Actions dynamic-matrix payload (`--format=matrix`).

use std::collections::BTreeMap;

use serde::Serialize;

use crate::unit::Unit;

#[derive(Debug, Serialize)]
pub struct MatrixEntry {
    pub name: String,
    pub package: String,
    pub targets: String,
    pub test_targets: String,
    pub runner: String,
    pub tier: String,
    pub persona: String,
    pub timeout_minutes: i64,
    pub concurrency_group: String,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub env: BTreeMap<String, String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub needs: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct MatrixPayload {
    /// `None` is Go's nil slice: no unit passed the filters, `"include": null`.
    pub include: Option<Vec<MatrixEntry>>,
}

/// Go's `CompileMatrix`, with its tier and persona filters.
pub fn compile_matrix(units: &[Unit], tier: &str, persona: &str) -> MatrixPayload {
    let mut entries: Option<Vec<MatrixEntry>> = None;
    for u in units {
        if !tier.is_empty() && tier != "all" && u.tier != tier {
            continue;
        }
        if !persona.is_empty() && persona != "all" && u.persona != "all" && u.persona != persona {
            continue;
        }
        let targets = u.targets().join(" ");
        entries.get_or_insert_with(Vec::new).push(MatrixEntry {
            name: u.name.clone(),
            package: u.package.clone(),
            targets: targets.clone(),
            test_targets: targets,
            runner: u.runner.clone(),
            tier: u.tier.clone(),
            persona: u.persona.clone(),
            timeout_minutes: u.timeout_minutes,
            concurrency_group: u.concurrency_group.clone(),
            env: u.env.clone(),
            needs: u.depends_on.clone(),
        });
    }
    MatrixPayload { include: entries }
}

/// Go's `RenderMatrixJSON`: indented JSON and a newline.
pub fn render_matrix_json(p: &MatrixPayload) -> String {
    crate::unit::marshal_indent(p) + "\n"
}

#[cfg(test)]
mod tests {
    use super::*;

    fn u(name: &str, tier: &str, persona: &str) -> Unit {
        Unit {
            schema: 1,
            name: name.into(),
            tier: tier.into(),
            persona: persona.into(),
            test_targets: Some(vec![":test".into()]),
            ..Default::default()
        }
    }

    #[test]
    fn filters() {
        let units = vec![
            u("fe-unit", "L1", "frontend"),
            u("be-unit", "L1", "backend"),
            u("soak-unit", "L3", "backend"),
        ];
        assert_eq!(
            compile_matrix(&units, "L1", "all").include.unwrap().len(),
            2
        );
        let fe = compile_matrix(&units, "all", "frontend").include.unwrap();
        assert_eq!(fe.len(), 1);
        assert_eq!(fe[0].name, "fe-unit");
        assert_eq!(
            render_matrix_json(&compile_matrix(&units, "L0", "all")),
            "{\n  \"include\": null\n}\n"
        );
    }
}
