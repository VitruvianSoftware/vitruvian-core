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

import React from "react";
import { makeStyles, Theme, Grid, Paper } from "@material-ui/core";
import { CatalogSearchResultListItem } from "@backstage/plugin-catalog";
import {
  SearchBar,
  SearchFilter,
  SearchResult,
  DefaultResultListItem,
} from "@backstage/plugin-search-react";
import { CatalogIcon, Content, Header, Page } from "@backstage/core-components";

const useStyles = makeStyles((theme: Theme) => ({
  bar: {
    padding: theme.spacing(1, 0),
  },
  filter: {
    "& + &": {
      marginTop: theme.spacing(2.5),
    },
  },
  filters: {
    padding: theme.spacing(2),
    marginTop: theme.spacing(2),
  },
}));

export const searchPage = (
  <Page themeId="home">
    <Header title="Search" />
    <Content>
      <Grid container direction="row">
        <Grid item xs={12}>
          <SearchBar />
        </Grid>
        <Grid item xs={3}>
          <SearchFilter.Select
            name="kind"
            values={["Component", "Template", "User", "Group", "System"]}
          />
          <SearchFilter.Checkbox
            name="lifecycle"
            values={["experimental", "production"]}
          />
        </Grid>
        <Grid item xs={9}>
          <SearchResult>
            {({ results }) => (
              <div>
                {results.map(({ type, document }) => {
                  switch (type) {
                    case "software-catalog":
                      return (
                        <CatalogSearchResultListItem
                          key={document.location}
                          result={document}
                          icon={<CatalogIcon />}
                        />
                      );
                    default:
                      return (
                        <DefaultResultListItem
                          key={document.location}
                          result={document}
                        />
                      );
                  }
                })}
              </div>
            )}
          </SearchResult>
        </Grid>
      </Grid>
    </Content>
  </Page>
);
