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

SELECT names.primary AS name, bbox, sources,
       source_tags['military'] AS military,
       ST_X(ST_PointOnSurface(geometry)) AS lon,
       ST_Y(ST_PointOnSurface(geometry)) AS lat,
       ST_Area_Spheroid(geometry) AS area
FROM read_parquet(?)
WHERE subtype = 'military'
  AND nullif(trim(names.primary), '') IS NOT NULL
  AND (source_tags['landuse'] = 'military'
       OR source_tags['military'] IN
          ('airfield', 'naval_base', 'range', 'barracks', 'base', 'training_area'))
