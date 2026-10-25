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

//! CPython 3.12's list.sort (Objects/listobject.c, "timsort" with powersort
//! merging), ported comparison for comparison. Any stable sort gives the
//! same order; this one also asks the same `<` questions in the same order,
//! so when two keys cannot be compared (a component that is a number among
//! ones that are text) it fails on the pair Python fails on, with Python's
//! message.

use crate::pyval::Exc;

const MIN_GALLOP: usize = 7;

struct Run {
    base: usize,
    len: usize,
    power: u32,
}

struct State<'a, T, F: FnMut(&T, &T) -> Result<bool, Exc>> {
    a: &'a mut [T],
    lt: F,
    min_gallop: usize,
    pending: Vec<Run>,
    tmp: Vec<T>,
}

/// Sorts `items` in place, ascending by `lt`, or returns the first error
/// `lt` gave.
pub fn sort<T: Clone, F: FnMut(&T, &T) -> Result<bool, Exc>>(
    items: &mut [T],
    lt: F,
) -> Result<(), Exc> {
    let n = items.len();
    if n < 2 {
        return Ok(());
    }
    let mut ms = State {
        a: items,
        lt,
        min_gallop: MIN_GALLOP,
        pending: Vec::new(),
        tmp: Vec::new(),
    };
    let minrun = compute_minrun(n);
    let mut lo = 0;
    let mut remaining = n;
    while remaining > 0 {
        let (mut run, descending) = ms.count_run(lo, lo + remaining)?;
        if descending {
            ms.a[lo..lo + run].reverse();
        }
        if run < minrun {
            let force = remaining.min(minrun);
            ms.binarysort(lo, lo + force, lo + run)?;
            run = force;
        }
        ms.found_new_run(run, n)?;
        ms.pending.push(Run {
            base: lo,
            len: run,
            power: 0,
        });
        lo += run;
        remaining -= run;
    }
    while ms.pending.len() > 1 {
        let mut i = ms.pending.len() - 2;
        if i > 0 && ms.pending[i - 1].len < ms.pending[i + 1].len {
            i -= 1;
        }
        ms.merge_at(i)?;
    }
    Ok(())
}

fn compute_minrun(mut n: usize) -> usize {
    let mut r = 0;
    while n >= 64 {
        r |= n & 1;
        n >>= 1;
    }
    n + r
}

fn powerloop(s1: usize, n1: usize, n2: usize, n: usize) -> u32 {
    let mut result = 0;
    let mut a = 2 * s1 + n1;
    let mut b = a + n1 + n2;
    loop {
        result += 1;
        if a >= n {
            a -= n;
            b -= n;
        } else if b >= n {
            break;
        }
        a <<= 1;
        b <<= 1;
    }
    result
}

impl<'a, T: Clone, F: FnMut(&T, &T) -> Result<bool, Exc>> State<'a, T, F> {
    fn islt(&mut self, x: &T, y: &T) -> Result<bool, Exc> {
        (self.lt)(x, y)
    }

    fn count_run(&mut self, lo: usize, hi: usize) -> Result<(usize, bool), Exc> {
        let mut i = lo + 1;
        if i == hi {
            return Ok((1, false));
        }
        let mut n = 2;
        let (x, y) = (self.a[i].clone(), self.a[i - 1].clone());
        if self.islt(&x, &y)? {
            i += 1;
            while i < hi {
                let (x, y) = (self.a[i].clone(), self.a[i - 1].clone());
                if !self.islt(&x, &y)? {
                    break;
                }
                i += 1;
                n += 1;
            }
            Ok((n, true))
        } else {
            i += 1;
            while i < hi {
                let (x, y) = (self.a[i].clone(), self.a[i - 1].clone());
                if self.islt(&x, &y)? {
                    break;
                }
                i += 1;
                n += 1;
            }
            Ok((n, false))
        }
    }

    fn binarysort(&mut self, lo: usize, hi: usize, mut start: usize) -> Result<(), Exc> {
        if lo == start {
            start += 1;
        }
        while start < hi {
            let pivot = self.a[start].clone();
            let (mut l, mut r) = (lo, start);
            while l < r {
                let p = l + ((r - l) >> 1);
                let other = self.a[p].clone();
                if self.islt(&pivot, &other)? {
                    r = p;
                } else {
                    l = p + 1;
                }
            }
            self.a[l..=start].rotate_right(1);
            start += 1;
        }
        Ok(())
    }

    /// gallop_left over `slice` (the run in `a` at `base`, or `tmp`).
    fn gallop_left(
        &mut self,
        key: &T,
        in_tmp: bool,
        base: usize,
        n: usize,
        hint: usize,
    ) -> Result<usize, Exc> {
        let at = |s: &Self, i: usize| -> T {
            if in_tmp {
                s.tmp[base + i].clone()
            } else {
                s.a[base + i].clone()
            }
        };
        let mut lastofs: isize;
        let mut ofs: isize;
        let h = at(self, hint);
        if self.islt(&h, key)? {
            let maxofs = (n - hint) as isize;
            lastofs = 0;
            ofs = 1;
            while ofs < maxofs {
                let v = at(self, hint + ofs as usize);
                if self.islt(&v, key)? {
                    lastofs = ofs;
                    ofs = (ofs << 1) + 1;
                } else {
                    break;
                }
            }
            if ofs > maxofs {
                ofs = maxofs;
            }
            lastofs += hint as isize;
            ofs += hint as isize;
        } else {
            let maxofs = (hint + 1) as isize;
            lastofs = 0;
            ofs = 1;
            while ofs < maxofs {
                let v = at(self, hint - ofs as usize);
                if self.islt(&v, key)? {
                    break;
                }
                lastofs = ofs;
                ofs = (ofs << 1) + 1;
            }
            if ofs > maxofs {
                ofs = maxofs;
            }
            let k = lastofs;
            lastofs = hint as isize - ofs;
            ofs = hint as isize - k;
        }
        lastofs += 1;
        while lastofs < ofs {
            let m = lastofs + ((ofs - lastofs) >> 1);
            let v = at(self, m as usize);
            if self.islt(&v, key)? {
                lastofs = m + 1;
            } else {
                ofs = m;
            }
        }
        Ok(ofs as usize)
    }

    fn gallop_right(
        &mut self,
        key: &T,
        in_tmp: bool,
        base: usize,
        n: usize,
        hint: usize,
    ) -> Result<usize, Exc> {
        let at = |s: &Self, i: usize| -> T {
            if in_tmp {
                s.tmp[base + i].clone()
            } else {
                s.a[base + i].clone()
            }
        };
        let mut lastofs: isize;
        let mut ofs: isize;
        let h = at(self, hint);
        if self.islt(key, &h)? {
            let maxofs = (hint + 1) as isize;
            lastofs = 0;
            ofs = 1;
            while ofs < maxofs {
                let v = at(self, hint - ofs as usize);
                if self.islt(key, &v)? {
                    lastofs = ofs;
                    ofs = (ofs << 1) + 1;
                } else {
                    break;
                }
            }
            if ofs > maxofs {
                ofs = maxofs;
            }
            let k = lastofs;
            lastofs = hint as isize - ofs;
            ofs = hint as isize - k;
        } else {
            let maxofs = (n - hint) as isize;
            lastofs = 0;
            ofs = 1;
            while ofs < maxofs {
                let v = at(self, hint + ofs as usize);
                if self.islt(key, &v)? {
                    break;
                }
                lastofs = ofs;
                ofs = (ofs << 1) + 1;
            }
            if ofs > maxofs {
                ofs = maxofs;
            }
            lastofs += hint as isize;
            ofs += hint as isize;
        }
        lastofs += 1;
        while lastofs < ofs {
            let m = lastofs + ((ofs - lastofs) >> 1);
            let v = at(self, m as usize);
            if self.islt(key, &v)? {
                ofs = m;
            } else {
                lastofs = m + 1;
            }
        }
        Ok(ofs as usize)
    }

    fn merge_lo(
        &mut self,
        ssa: usize,
        mut na: usize,
        ssb: usize,
        mut nb: usize,
    ) -> Result<(), Exc> {
        self.tmp = self.a[ssa..ssa + na].to_vec();
        let mut dest = ssa;
        let mut pa = 0usize; // in tmp
        let mut pb = ssb; // in a
        self.a[dest] = self.a[pb].clone();
        dest += 1;
        pb += 1;
        nb -= 1;
        macro_rules! copy_b {
            () => {{
                for i in 0..nb {
                    self.a[dest + i] = self.a[pb + i].clone();
                }
                self.a[dest + nb] = self.tmp[pa].clone();
                return Ok(());
            }};
        }
        macro_rules! succeed {
            () => {{
                for i in 0..na {
                    self.a[dest + i] = self.tmp[pa + i].clone();
                }
                return Ok(());
            }};
        }
        if nb == 0 {
            succeed!();
        }
        if na == 1 {
            copy_b!();
        }
        let mut min_gallop = self.min_gallop;
        loop {
            let mut acount = 0usize;
            let mut bcount = 0usize;
            loop {
                let (x, y) = (self.a[pb].clone(), self.tmp[pa].clone());
                if self.islt(&x, &y)? {
                    self.a[dest] = self.a[pb].clone();
                    dest += 1;
                    pb += 1;
                    bcount += 1;
                    acount = 0;
                    nb -= 1;
                    if nb == 0 {
                        succeed!();
                    }
                    if bcount >= min_gallop {
                        break;
                    }
                } else {
                    self.a[dest] = self.tmp[pa].clone();
                    dest += 1;
                    pa += 1;
                    acount += 1;
                    bcount = 0;
                    na -= 1;
                    if na == 1 {
                        copy_b!();
                    }
                    if acount >= min_gallop {
                        break;
                    }
                }
            }
            min_gallop += 1;
            loop {
                min_gallop -= (min_gallop > 1) as usize;
                self.min_gallop = min_gallop;
                let key = self.a[pb].clone();
                let k = self.gallop_right(&key, true, pa, na, 0)?;
                acount = k;
                if k > 0 {
                    for i in 0..k {
                        self.a[dest + i] = self.tmp[pa + i].clone();
                    }
                    dest += k;
                    pa += k;
                    na -= k;
                    if na == 1 {
                        copy_b!();
                    }
                    if na == 0 {
                        succeed!();
                    }
                }
                self.a[dest] = self.a[pb].clone();
                dest += 1;
                pb += 1;
                nb -= 1;
                if nb == 0 {
                    succeed!();
                }
                let key = self.tmp[pa].clone();
                let k = self.gallop_left(&key, false, pb, nb, 0)?;
                bcount = k;
                if k > 0 {
                    for i in 0..k {
                        self.a[dest + i] = self.a[pb + i].clone();
                    }
                    dest += k;
                    pb += k;
                    nb -= k;
                    if nb == 0 {
                        succeed!();
                    }
                }
                self.a[dest] = self.tmp[pa].clone();
                dest += 1;
                pa += 1;
                na -= 1;
                if na == 1 {
                    copy_b!();
                }
                if !(acount >= MIN_GALLOP || bcount >= MIN_GALLOP) {
                    break;
                }
            }
            min_gallop += 1;
            self.min_gallop = min_gallop;
        }
    }

    fn merge_hi(
        &mut self,
        ssa: usize,
        mut na: usize,
        ssb: usize,
        mut nb: usize,
    ) -> Result<(), Exc> {
        self.tmp = self.a[ssb..ssb + nb].to_vec();
        let basea = ssa;
        let mut dest = (ssb + nb - 1) as isize;
        let mut pb = (nb - 1) as isize; // in tmp
        let mut pa = (ssa + na - 1) as isize; // in a
        self.a[dest as usize] = self.a[pa as usize].clone();
        dest -= 1;
        pa -= 1;
        na -= 1;
        macro_rules! copy_a {
            () => {{
                let d = dest + 1 - na as isize;
                let s = pa + 1 - na as isize;
                for i in (0..na).rev() {
                    self.a[(d + i as isize) as usize] = self.a[(s + i as isize) as usize].clone();
                }
                dest -= na as isize;
                self.a[dest as usize] = self.tmp[pb as usize].clone();
                return Ok(());
            }};
        }
        macro_rules! succeed {
            () => {{
                let d = dest - (nb as isize - 1);
                for i in 0..nb {
                    self.a[(d + i as isize) as usize] = self.tmp[i].clone();
                }
                return Ok(());
            }};
        }
        if na == 0 {
            succeed!();
        }
        if nb == 1 {
            copy_a!();
        }
        let mut min_gallop = self.min_gallop;
        loop {
            let mut acount = 0usize;
            let mut bcount = 0usize;
            loop {
                let (x, y) = (self.tmp[pb as usize].clone(), self.a[pa as usize].clone());
                if self.islt(&x, &y)? {
                    self.a[dest as usize] = self.a[pa as usize].clone();
                    dest -= 1;
                    pa -= 1;
                    acount += 1;
                    bcount = 0;
                    na -= 1;
                    if na == 0 {
                        succeed!();
                    }
                    if acount >= min_gallop {
                        break;
                    }
                } else {
                    self.a[dest as usize] = self.tmp[pb as usize].clone();
                    dest -= 1;
                    pb -= 1;
                    bcount += 1;
                    acount = 0;
                    nb -= 1;
                    if nb == 1 {
                        copy_a!();
                    }
                    if bcount >= min_gallop {
                        break;
                    }
                }
            }
            min_gallop += 1;
            loop {
                min_gallop -= (min_gallop > 1) as usize;
                self.min_gallop = min_gallop;
                let key = self.tmp[pb as usize].clone();
                let k = self.gallop_right(&key, false, basea, na, na - 1)?;
                let k = na - k;
                acount = k;
                if k > 0 {
                    dest -= k as isize;
                    pa -= k as isize;
                    for i in (0..k).rev() {
                        self.a[(dest + 1 + i as isize) as usize] =
                            self.a[(pa + 1 + i as isize) as usize].clone();
                    }
                    na -= k;
                    if na == 0 {
                        succeed!();
                    }
                }
                self.a[dest as usize] = self.tmp[pb as usize].clone();
                dest -= 1;
                pb -= 1;
                nb -= 1;
                if nb == 1 {
                    copy_a!();
                }
                let key = self.a[pa as usize].clone();
                let k = self.gallop_left(&key, true, 0, nb, nb - 1)?;
                let k = nb - k;
                bcount = k;
                if k > 0 {
                    dest -= k as isize;
                    pb -= k as isize;
                    for i in 0..k {
                        self.a[(dest + 1 + i as isize) as usize] =
                            self.tmp[(pb + 1 + i as isize) as usize].clone();
                    }
                    nb -= k;
                    if nb == 1 {
                        copy_a!();
                    }
                    if nb == 0 {
                        succeed!();
                    }
                }
                self.a[dest as usize] = self.a[pa as usize].clone();
                dest -= 1;
                pa -= 1;
                na -= 1;
                if na == 0 {
                    succeed!();
                }
                if !(acount >= MIN_GALLOP || bcount >= MIN_GALLOP) {
                    break;
                }
            }
            min_gallop += 1;
            self.min_gallop = min_gallop;
        }
    }

    fn merge_at(&mut self, i: usize) -> Result<(), Exc> {
        let (mut ssa, mut na) = (self.pending[i].base, self.pending[i].len);
        let (ssb, nb) = (self.pending[i + 1].base, self.pending[i + 1].len);
        self.pending[i].len = na + nb;
        self.pending.remove(i + 1);
        let key = self.a[ssb].clone();
        let k = self.gallop_right(&key, false, ssa, na, 0)?;
        ssa += k;
        na -= k;
        if na == 0 {
            return Ok(());
        }
        let key = self.a[ssa + na - 1].clone();
        let nb = self.gallop_left(&key, false, ssb, nb, nb - 1)?;
        if nb == 0 {
            return Ok(());
        }
        if na <= nb {
            self.merge_lo(ssa, na, ssb, nb)
        } else {
            self.merge_hi(ssa, na, ssb, nb)
        }
    }

    fn found_new_run(&mut self, n2: usize, listlen: usize) -> Result<(), Exc> {
        if let Some(top) = self.pending.last() {
            let power = powerloop(top.base, top.len, n2, listlen);
            while self.pending.len() > 1 && self.pending[self.pending.len() - 2].power > power {
                let i = self.pending.len() - 2;
                self.merge_at(i)?;
            }
            self.pending.last_mut().expect("a run").power = power;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lcg(seed: &mut u64) -> u64 {
        *seed = seed
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        *seed >> 33
    }

    #[test]
    fn sorts_stably_at_every_size() {
        let mut seed = 7;
        for n in [0usize, 1, 2, 3, 10, 63, 64, 65, 200, 1000, 5000] {
            for spread in [3u64, 50, 1 << 30] {
                let mut items: Vec<(u64, usize)> =
                    (0..n).map(|i| (lcg(&mut seed) % spread, i)).collect();
                // Runs, so merging and galloping are exercised.
                if n > 100 {
                    items[..n / 3].sort();
                }
                let mut want = items.clone();
                want.sort_by_key(|x| x.0);
                sort(&mut items, |x, y| Ok(x.0 < y.0)).unwrap();
                assert_eq!(items, want, "n={} spread={}", n, spread);
            }
        }
    }

    #[test]
    fn a_failing_comparison_stops_the_sort() {
        let mut items = vec![3, 1, 2];
        let err = sort(&mut items, |_, _| Err(Exc::type_error("no"))).unwrap_err();
        assert_eq!(err, Exc::type_error("no"));
    }
}
