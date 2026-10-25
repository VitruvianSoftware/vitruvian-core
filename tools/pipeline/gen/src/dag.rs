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

//! Dependency validation and the topological order units render in.

use std::collections::HashMap;

use crate::gostr::quote;
use crate::unit::Unit;

pub struct Dag {
    units: HashMap<String, Unit>,
    /// unit -> dependents, in the order the edges were declared.
    adj: HashMap<String, Vec<String>>,
    in_degree: HashMap<String, usize>,
}

/// Go's `BuildDAG`: every dependency must exist and the graph be acyclic.
pub fn build_dag(units: &[Unit]) -> Result<Dag, String> {
    let mut dag = Dag {
        units: HashMap::new(),
        adj: HashMap::new(),
        in_degree: HashMap::new(),
    };
    for u in units {
        dag.units.insert(u.name.clone(), u.clone());
        dag.in_degree.insert(u.name.clone(), 0);
    }
    for u in units {
        for dep in &u.depends_on {
            if !dag.units.contains_key(dep) {
                return Err(format!(
                    "unit {} depends on non-existent unit {}",
                    quote(&u.name),
                    quote(dep)
                ));
            }
            dag.adj.entry(dep.clone()).or_default().push(u.name.clone());
            *dag.in_degree.get_mut(&u.name).expect("seeded above") += 1;
        }
    }
    dag.topological_order()?;
    Ok(dag)
}

impl Dag {
    /// Kahn's algorithm, re-sorting the whole queue after every step as the
    /// Go original does, so ties break alphabetically.
    pub fn topological_order(&self) -> Result<Vec<Unit>, String> {
        let mut in_degree = self.in_degree.clone();
        let mut queue: Vec<String> = in_degree
            .iter()
            .filter(|(_, d)| **d == 0)
            .map(|(n, _)| n.clone())
            .collect();
        queue.sort();
        let mut ordered = Vec::with_capacity(self.units.len());
        let mut head = 0;
        while head < queue.len() {
            let curr = queue[head].clone();
            head += 1;
            ordered.push(self.units[&curr].clone());
            if let Some(next) = self.adj.get(&curr) {
                for n in next {
                    let d = in_degree.get_mut(n).expect("every node has a degree");
                    *d -= 1;
                    if *d == 0 {
                        queue.push(n.clone());
                    }
                }
            }
            queue[head..].sort();
        }
        if ordered.len() != self.units.len() {
            return Err("cyclic dependency detected among pipeline units".to_string());
        }
        Ok(ordered)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn u(name: &str, deps: &[&str]) -> Unit {
        Unit {
            schema: 1,
            name: name.into(),
            test_targets: Some(vec![":t".into()]),
            depends_on: deps.iter().map(|s| s.to_string()).collect(),
            ..Default::default()
        }
    }

    #[test]
    fn order_respects_dependencies() {
        let units = vec![
            u("tabula-web", &["tabula-shared", "design-system"]),
            u("tabula-shared", &[]),
            u("design-system", &[]),
            u("tabula-api", &["tabula-shared"]),
        ];
        let names: Vec<String> = build_dag(&units)
            .unwrap()
            .topological_order()
            .unwrap()
            .into_iter()
            .map(|u| u.name)
            .collect();
        assert_eq!(
            names,
            ["design-system", "tabula-shared", "tabula-api", "tabula-web"]
        );
    }

    #[test]
    fn cycles_and_missing_deps_are_refused() {
        let cyc = vec![
            u("unit-a", &["unit-b"]),
            u("unit-b", &["unit-c"]),
            u("unit-c", &["unit-a"]),
        ];
        assert_eq!(
            build_dag(&cyc).err().unwrap(),
            "cyclic dependency detected among pipeline units"
        );
        let missing = vec![u("unit-a", &["non-existent-unit"])];
        assert_eq!(
            build_dag(&missing).err().unwrap(),
            "unit \"unit-a\" depends on non-existent unit \"non-existent-unit\""
        );
    }
}
