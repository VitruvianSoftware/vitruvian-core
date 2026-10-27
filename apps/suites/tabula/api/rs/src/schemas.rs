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

use crate::crypto::{is_valid_email, is_valid_hex_color, is_valid_uuid, parse_datetime_ms};
use crate::errors::AppError;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

fn validation_err(field: &str, msg: &str) -> AppError {
    AppError::validation(json!({
        "formErrors": [],
        "fieldErrors": {
            field: [msg]
        }
    }))
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParsedTab {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<Value>,
    pub url: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub favicon_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub position: Option<i64>,
    pub is_pinned: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub group_id: Option<String>,
    pub metadata: Map<String, Value>,
}

/// Parse and normalize a tab payload (`TabSchema` in `src/schemas/workspace.ts`).
/// Maps `favIconUrl -> faviconUrl`, `pinned -> isPinned`, `index -> position`
/// while preferring canonical fields when both are present (`??` semantics).
pub fn parse_tab_schema(raw: &Value) -> Result<ParsedTab, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("tab", "Expected object"));
    };

    // id: union(string, number).nullable().optional()
    let id = match obj.get("id") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(Value::String(s.clone())),
        Some(Value::Number(n)) => Some(Value::Number(n.clone())),
        Some(_) => return Err(validation_err("id", "Expected string, number, or null")),
    };

    // url: string().min(1)
    let Some(url_str) = obj.get("url").and_then(Value::as_str) else {
        return Err(validation_err("url", "URL is required"));
    };
    if url_str.is_empty() {
        return Err(validation_err("url", "URL is required"));
    }

    // title: string().max(500).nullable().optional()
    let title = match obj.get("title") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if s.chars().count() > 500 {
                return Err(validation_err("title", "Title exceeds 500 characters"));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("title", "Expected string or null")),
    };

    // faviconUrl ?? favIconUrl: string().nullable().optional()
    let favicon_val = match obj.get("faviconUrl") {
        Some(v) if !v.is_null() => Some(v),
        Some(_) => match obj.get("favIconUrl") {
            Some(v2) => Some(v2),
            None => Some(&Value::Null),
        },
        None => obj.get("favIconUrl"),
    };
    let favicon_url = match favicon_val {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return Err(validation_err("faviconUrl", "Expected string or null")),
    };

    // position ?? index: number().int().min(0).optional()
    let pos_val = match obj.get("position") {
        Some(v) if !v.is_null() => Some(v),
        _ => match obj.get("index") {
            Some(v) if !v.is_null() => Some(v),
            _ => None,
        },
    };
    let position = match pos_val {
        None => None,
        Some(Value::Number(n)) => {
            let Some(i) = n.as_i64() else {
                return Err(validation_err("position", "Expected non-negative integer"));
            };
            if i < 0 {
                return Err(validation_err("position", "Position must be >= 0"));
            }
            Some(i)
        }
        Some(_) => return Err(validation_err("position", "Expected integer")),
    };

    // isPinned ?? pinned: boolean().default(false)
    let pinned_val = match obj.get("isPinned") {
        Some(v) if !v.is_null() => Some(v),
        _ => match obj.get("pinned") {
            Some(v) if !v.is_null() => Some(v),
            _ => None,
        },
    };
    let is_pinned = match pinned_val {
        None => false,
        Some(Value::Bool(b)) => *b,
        Some(_) => return Err(validation_err("isPinned", "Expected boolean")),
    };

    // groupId: string().nullable().optional()
    let group_id = match obj.get("groupId") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return Err(validation_err("groupId", "Expected string or null")),
    };

    // metadata: record(unknown).default({})
    let metadata = match obj.get("metadata") {
        None | Some(Value::Null) => Map::new(),
        Some(Value::Object(m)) => m.clone(),
        Some(_) => return Err(validation_err("metadata", "Expected object")),
    };

    Ok(ParsedTab {
        id,
        url: url_str.to_string(),
        title,
        favicon_url,
        position,
        is_pinned,
        group_id,
        metadata,
    })
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParsedResource {
    pub id: Option<String>,
    pub title: String,
    pub url: String,
    pub favicon_url: Option<String>,
    pub position: Option<i64>,
    pub section_id: Option<String>,
}

/// Parse `ResourceSchema` (`src/schemas/workspace.ts`).
/// Accepts scheme-less URLs (`z.string().min(1)`), odd/relative `faviconUrl`, and null/missing `id`.
pub fn parse_resource_schema(raw: &Value) -> Result<ParsedResource, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("resource", "Expected object"));
    };
    let id = match obj.get("id") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return Err(validation_err("id", "Expected string or null")),
    };
    let Some(title) = obj.get("title").and_then(Value::as_str) else {
        return Err(validation_err("title", "Resource title is required"));
    };
    if title.is_empty() || title.chars().count() > 500 {
        return Err(validation_err("title", "Invalid resource title"));
    }
    let Some(url) = obj.get("url").and_then(Value::as_str) else {
        return Err(validation_err("url", "Resource URL is required"));
    };
    if url.is_empty() {
        return Err(validation_err("url", "Resource URL cannot be empty"));
    }
    let favicon_url = match obj.get("faviconUrl") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return Err(validation_err("faviconUrl", "Expected string or null")),
    };
    let position = match obj.get("position") {
        None | Some(Value::Null) => None,
        Some(Value::Number(n)) => {
            let Some(i) = n.as_i64() else {
                return Err(validation_err("position", "Expected integer"));
            };
            if i < 0 {
                return Err(validation_err("position", "Position must be >= 0"));
            }
            Some(i)
        }
        Some(_) => return Err(validation_err("position", "Expected integer")),
    };
    let section_id = match obj.get("sectionId") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return Err(validation_err("sectionId", "Expected string or null")),
    };
    Ok(ParsedResource {
        id,
        title: title.to_string(),
        url: url.to_string(),
        favicon_url,
        position,
        section_id,
    })
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParsedSection {
    pub id: Option<String>,
    pub title: String,
    pub position: Option<i64>,
    pub resources: Option<Vec<ParsedResource>>,
}

pub fn parse_section_schema(raw: &Value) -> Result<ParsedSection, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("section", "Expected object"));
    };
    let id = match obj.get("id") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return Err(validation_err("id", "Expected string or null")),
    };
    let Some(title) = obj.get("title").and_then(Value::as_str) else {
        return Err(validation_err("title", "Section title is required"));
    };
    if title.is_empty() || title.chars().count() > 255 {
        return Err(validation_err("title", "Invalid section title"));
    }
    let position = match obj.get("position") {
        None | Some(Value::Null) => None,
        Some(Value::Number(n)) => {
            let Some(i) = n.as_i64() else {
                return Err(validation_err("position", "Expected integer"));
            };
            if i < 0 {
                return Err(validation_err("position", "Position must be >= 0"));
            }
            Some(i)
        }
        Some(_) => return Err(validation_err("position", "Expected integer")),
    };
    let resources = match obj.get("resources") {
        None | Some(Value::Null) => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(parse_resource_schema(item)?);
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("resources", "Expected array")),
    };
    Ok(ParsedSection {
        id,
        title: title.to_string(),
        position,
        resources,
    })
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParsedNote {
    pub id: Option<String>,
    pub title: String,
    pub content: String,
    pub position: Option<i64>,
}

pub fn parse_note_schema(raw: &Value) -> Result<ParsedNote, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("note", "Expected object"));
    };
    let id = match obj.get("id") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return Err(validation_err("id", "Expected string or null")),
    };
    let Some(title) = obj.get("title").and_then(Value::as_str) else {
        return Err(validation_err("title", "Note title is required"));
    };
    if title.is_empty() || title.chars().count() > 255 {
        return Err(validation_err("title", "Invalid note title"));
    }
    let content = match obj.get("content") {
        None | Some(Value::Null) => String::new(),
        Some(Value::String(s)) => s.clone(),
        Some(_) => return Err(validation_err("content", "Expected string")),
    };
    let position = match obj.get("position") {
        None | Some(Value::Null) => None,
        Some(Value::Number(n)) => {
            let Some(i) = n.as_i64() else {
                return Err(validation_err("position", "Expected integer"));
            };
            if i < 0 {
                return Err(validation_err("position", "Position must be >= 0"));
            }
            Some(i)
        }
        Some(_) => return Err(validation_err("position", "Expected integer")),
    };
    Ok(ParsedNote {
        id,
        title: title.to_string(),
        content,
        position,
    })
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParsedTask {
    pub id: Option<String>,
    pub title: String,
    pub completed: bool,
    pub due_date: Option<String>,
    pub position: Option<i64>,
}

pub fn parse_task_schema(raw: &Value) -> Result<ParsedTask, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("task", "Expected object"));
    };
    let id = match obj.get("id") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return Err(validation_err("id", "Expected string or null")),
    };
    let Some(title) = obj.get("title").and_then(Value::as_str) else {
        return Err(validation_err("title", "Task title is required"));
    };
    if title.is_empty() || title.chars().count() > 500 {
        return Err(validation_err("title", "Invalid task title"));
    }
    let completed = match obj.get("completed") {
        None => false,
        Some(Value::Bool(b)) => *b,
        Some(_) => return Err(validation_err("completed", "Expected boolean")),
    };
    let due_date = match obj.get("dueDate") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return Err(validation_err("dueDate", "Expected string or null")),
    };
    let position = match obj.get("position") {
        None | Some(Value::Null) => None,
        Some(Value::Number(n)) => {
            let Some(i) = n.as_i64() else {
                return Err(validation_err("position", "Expected integer"));
            };
            if i < 0 {
                return Err(validation_err("position", "Position must be >= 0"));
            }
            Some(i)
        }
        Some(_) => return Err(validation_err("position", "Expected integer")),
    };
    Ok(ParsedTask {
        id,
        title: title.to_string(),
        completed,
        due_date,
        position,
    })
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ParsedTabGroup {
    pub id: String,
    pub title: Option<String>,
    pub color: String,
    pub collapsed: bool,
}

pub fn parse_tab_group_schema(raw: &Value) -> Result<ParsedTabGroup, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("tabGroup", "Expected object"));
    };
    let Some(id) = obj.get("id").and_then(Value::as_str) else {
        return Err(validation_err("id", "Tab group id is required"));
    };
    if id.is_empty() {
        return Err(validation_err("id", "Tab group id cannot be empty"));
    }
    let title = match obj.get("title") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return Err(validation_err("title", "Expected string")),
    };
    let Some(color) = obj.get("color").and_then(Value::as_str) else {
        return Err(validation_err("color", "Tab group color is required"));
    };
    let collapsed = match obj.get("collapsed") {
        None => false,
        Some(Value::Bool(b)) => *b,
        Some(_) => return Err(validation_err("collapsed", "Expected boolean")),
    };
    Ok(ParsedTabGroup {
        id: id.to_string(),
        title,
        color: color.to_string(),
        collapsed,
    })
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct WorkspaceCreateInput {
    pub id: Option<String>,
    pub name: String,
    pub description: Option<String>,
    pub color: Option<String>,
    pub icon: Option<String>,
    pub position: i64,
    pub group_id: Option<String>,
    pub settings: Map<String, Value>,
    pub tab_groups: Option<Vec<Value>>,
    pub tabs: Option<Vec<ParsedTab>>,
    pub sections: Option<Vec<ParsedSection>>,
    pub notes: Option<Vec<ParsedNote>>,
    pub tasks: Option<Vec<ParsedTask>>,
    pub resources: Option<Vec<ParsedResource>>,
}

pub fn parse_workspace_create_schema(raw: &Value) -> Result<WorkspaceCreateInput, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };

    let id = match obj.get("id") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if s.is_empty() {
                return Err(validation_err("id", "Workspace ID cannot be empty"));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("id", "Expected string")),
    };

    let Some(name) = obj.get("name").and_then(Value::as_str) else {
        return Err(validation_err("name", "Workspace name is required"));
    };
    if name.is_empty() || name.chars().count() > 255 {
        return Err(validation_err(
            "name",
            "Workspace name must be between 1 and 255 characters",
        ));
    }

    let description = match obj.get("description") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if s.chars().count() > 1000 {
                return Err(validation_err(
                    "description",
                    "Description exceeds 1000 characters",
                ));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("description", "Expected string or null")),
    };

    let color = match obj.get("color") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if !is_valid_hex_color(s) {
                return Err(validation_err("color", "Invalid hex color"));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("color", "Expected hex color string")),
    };

    let icon = match obj.get("icon") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if s.chars().count() > 50 {
                return Err(validation_err("icon", "Icon exceeds 50 characters"));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("icon", "Expected string or null")),
    };

    let position = match obj.get("position") {
        None => 0,
        Some(Value::Number(n)) => {
            let Some(i) = n.as_i64() else {
                return Err(validation_err("position", "Expected integer"));
            };
            if i < 0 {
                return Err(validation_err("position", "Position must be >= 0"));
            }
            i
        }
        Some(_) => return Err(validation_err("position", "Expected integer")),
    };

    let group_id = match obj.get("groupId") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => Some(s.clone()),
        Some(_) => return Err(validation_err("groupId", "Expected string or null")),
    };

    let settings = match obj.get("settings") {
        None => Map::new(),
        Some(Value::Object(m)) => m.clone(),
        Some(_) => return Err(validation_err("settings", "Expected object")),
    };

    let tab_groups = match obj.get("tabGroups") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                let parsed = parse_tab_group_schema(item)?;
                out.push(serde_json::to_value(parsed).unwrap_or(Value::Null));
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("tabGroups", "Expected array")),
    };

    let tabs = match obj.get("tabs") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(parse_tab_schema(item)?);
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("tabs", "Expected array")),
    };

    let sections = match obj.get("sections") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(parse_section_schema(item)?);
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("sections", "Expected array")),
    };

    let notes = match obj.get("notes") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(parse_note_schema(item)?);
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("notes", "Expected array")),
    };

    let tasks = match obj.get("tasks") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(parse_task_schema(item)?);
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("tasks", "Expected array")),
    };

    let resources = match obj.get("resources") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(parse_resource_schema(item)?);
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("resources", "Expected array")),
    };

    Ok(WorkspaceCreateInput {
        id,
        name: name.to_string(),
        description,
        color,
        icon,
        position,
        group_id,
        settings,
        tab_groups,
        tabs,
        sections,
        notes,
        tasks,
        resources,
    })
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct WorkspaceUpdateInput {
    pub name: Option<String>,
    pub description: Option<Option<String>>,
    pub color: Option<Option<String>>,
    pub icon: Option<Option<String>>,
    pub position: Option<i64>,
    pub group_id: Option<Option<String>>,
    pub settings: Option<Map<String, Value>>,
    pub tab_groups: Option<Vec<Value>>,
    pub tabs: Option<Vec<ParsedTab>>,
    pub sections: Option<Vec<ParsedSection>>,
    pub notes: Option<Vec<ParsedNote>>,
    pub tasks: Option<Vec<ParsedTask>>,
    pub resources: Option<Vec<ParsedResource>>,
    pub base_version: Option<u64>,
    pub tab_sync: Option<bool>,
    pub claim_active_device: Option<bool>,
}

pub fn parse_workspace_update_schema(raw: &Value) -> Result<WorkspaceUpdateInput, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };

    let name = match obj.get("name") {
        None => None,
        Some(Value::String(s)) => {
            if s.is_empty() || s.chars().count() > 255 {
                return Err(validation_err("name", "Invalid workspace name"));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("name", "Expected string")),
    };

    let description = match obj.get("description") {
        None => None,
        Some(Value::Null) => Some(None),
        Some(Value::String(s)) => {
            if s.chars().count() > 1000 {
                return Err(validation_err(
                    "description",
                    "Description exceeds 1000 characters",
                ));
            }
            Some(Some(s.clone()))
        }
        Some(_) => return Err(validation_err("description", "Expected string or null")),
    };

    let color = match obj.get("color") {
        None => None,
        Some(Value::Null) => Some(None),
        Some(Value::String(s)) => {
            if !is_valid_hex_color(s) {
                return Err(validation_err("color", "Invalid hex color"));
            }
            Some(Some(s.clone()))
        }
        Some(_) => return Err(validation_err("color", "Expected hex color string")),
    };

    let icon = match obj.get("icon") {
        None => None,
        Some(Value::Null) => Some(None),
        Some(Value::String(s)) => {
            if s.chars().count() > 50 {
                return Err(validation_err("icon", "Icon exceeds 50 characters"));
            }
            Some(Some(s.clone()))
        }
        Some(_) => return Err(validation_err("icon", "Expected string or null")),
    };

    let position = match obj.get("position") {
        None => None,
        Some(Value::Number(n)) => {
            let Some(i) = n.as_i64() else {
                return Err(validation_err("position", "Expected integer"));
            };
            if i < 0 {
                return Err(validation_err("position", "Position must be >= 0"));
            }
            Some(i)
        }
        Some(_) => return Err(validation_err("position", "Expected integer")),
    };

    let group_id = match obj.get("groupId") {
        None => None,
        Some(Value::Null) => Some(None),
        Some(Value::String(s)) => Some(Some(s.clone())),
        Some(_) => return Err(validation_err("groupId", "Expected string or null")),
    };

    let settings = match obj.get("settings") {
        None => None,
        Some(Value::Object(m)) => Some(m.clone()),
        Some(_) => return Err(validation_err("settings", "Expected object")),
    };

    let tab_groups = match obj.get("tabGroups") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                let parsed = parse_tab_group_schema(item)?;
                out.push(serde_json::to_value(parsed).unwrap_or(Value::Null));
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("tabGroups", "Expected array")),
    };

    let tabs = match obj.get("tabs") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(parse_tab_schema(item)?);
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("tabs", "Expected array")),
    };

    let sections = match obj.get("sections") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(parse_section_schema(item)?);
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("sections", "Expected array")),
    };

    let notes = match obj.get("notes") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(parse_note_schema(item)?);
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("notes", "Expected array")),
    };

    let tasks = match obj.get("tasks") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(parse_task_schema(item)?);
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("tasks", "Expected array")),
    };

    let resources = match obj.get("resources") {
        None => None,
        Some(Value::Array(arr)) => {
            let mut out = Vec::with_capacity(arr.len());
            for item in arr {
                out.push(parse_resource_schema(item)?);
            }
            Some(out)
        }
        Some(_) => return Err(validation_err("resources", "Expected array")),
    };

    let base_version = match obj.get("baseVersion") {
        None => None,
        Some(Value::Number(n)) => {
            let Some(v) = n.as_u64() else {
                return Err(validation_err(
                    "baseVersion",
                    "Expected non-negative integer",
                ));
            };
            Some(v)
        }
        Some(_) => return Err(validation_err("baseVersion", "Expected integer")),
    };

    let tab_sync = match obj.get("tabSync") {
        None => None,
        Some(Value::Bool(b)) => Some(*b),
        Some(_) => return Err(validation_err("tabSync", "Expected boolean")),
    };

    let claim_active_device = match obj.get("claimActiveDevice") {
        None => None,
        Some(Value::Bool(b)) => Some(*b),
        Some(_) => return Err(validation_err("claimActiveDevice", "Expected boolean")),
    };

    Ok(WorkspaceUpdateInput {
        name,
        description,
        color,
        icon,
        position,
        group_id,
        settings,
        tab_groups,
        tabs,
        sections,
        notes,
        tasks,
        resources,
        base_version,
        tab_sync,
        claim_active_device,
    })
}

pub fn parse_save_tabs_schema(raw: &Value) -> Result<Vec<ParsedTab>, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(Value::Array(arr)) = obj.get("tabs") else {
        return Err(validation_err("tabs", "Expected array"));
    };
    let mut out = Vec::with_capacity(arr.len());
    for item in arr {
        out.push(parse_tab_schema(item)?);
    }
    Ok(out)
}

#[derive(Debug, Clone, PartialEq)]
pub struct TabMoveInput {
    pub tab_id: String,
    pub target_workspace_id: String,
    pub position: Option<i64>,
}

pub fn parse_tab_move_schema(raw: &Value) -> Result<TabMoveInput, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(tab_id) = obj.get("tabId").and_then(Value::as_str) else {
        return Err(validation_err("tabId", "Tab ID is required"));
    };
    if !is_valid_uuid(tab_id) {
        return Err(validation_err("tabId", "Invalid tab UUID"));
    }
    let Some(target) = obj.get("targetWorkspaceId").and_then(Value::as_str) else {
        return Err(validation_err(
            "targetWorkspaceId",
            "Target workspace ID is required",
        ));
    };
    if !is_valid_uuid(target) {
        return Err(validation_err(
            "targetWorkspaceId",
            "Invalid target workspace UUID",
        ));
    }
    let position = match obj.get("position") {
        None | Some(Value::Null) => None,
        Some(Value::Number(n)) => {
            let Some(i) = n.as_i64() else {
                return Err(validation_err("position", "Expected integer"));
            };
            if i < 0 {
                return Err(validation_err("position", "Position must be >= 0"));
            }
            Some(i)
        }
        Some(_) => return Err(validation_err("position", "Expected integer")),
    };
    Ok(TabMoveInput {
        tab_id: tab_id.to_string(),
        target_workspace_id: target.to_string(),
        position,
    })
}

pub fn parse_move_tab_schema(raw: &Value) -> Result<String, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(target) = obj.get("targetWorkspaceId").and_then(Value::as_str) else {
        return Err(validation_err(
            "targetWorkspaceId",
            "Target workspace ID is required",
        ));
    };
    if !is_valid_uuid(target) {
        return Err(validation_err(
            "targetWorkspaceId",
            "Invalid target workspace UUID",
        ));
    }
    Ok(target.to_string())
}

#[derive(Debug, Clone, PartialEq)]
pub struct TabReorderInput {
    pub tab_id: String,
    pub new_position: i64,
}

pub fn parse_tab_reorder_schema(raw: &Value) -> Result<TabReorderInput, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(tab_id) = obj.get("tabId").and_then(Value::as_str) else {
        return Err(validation_err("tabId", "Tab ID is required"));
    };
    if !is_valid_uuid(tab_id) {
        return Err(validation_err("tabId", "Invalid tab UUID"));
    }
    let Some(pos) = obj.get("newPosition").and_then(Value::as_i64) else {
        return Err(validation_err(
            "newPosition",
            "Expected non-negative integer",
        ));
    };
    if pos < 0 {
        return Err(validation_err("newPosition", "newPosition must be >= 0"));
    }
    Ok(TabReorderInput {
        tab_id: tab_id.to_string(),
        new_position: pos,
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct TabBulkOperationInput {
    pub tab_ids: Vec<String>,
    pub operation: String,
}

pub fn parse_tab_bulk_operation_schema(raw: &Value) -> Result<TabBulkOperationInput, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let ids = parse_bulk_delete_tabs_schema(raw)?;
    let Some(op) = obj.get("operation").and_then(Value::as_str) else {
        return Err(validation_err("operation", "Operation is required"));
    };
    if op != "close" && op != "suspend" && op != "pin" && op != "unpin" {
        return Err(validation_err("operation", "Invalid bulk operation"));
    }
    Ok(TabBulkOperationInput {
        tab_ids: ids,
        operation: op.to_string(),
    })
}

pub fn parse_bulk_delete_tabs_schema(raw: &Value) -> Result<Vec<String>, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(Value::Array(arr)) = obj.get("tabIds") else {
        return Err(validation_err("tabIds", "Expected array"));
    };
    if arr.is_empty() {
        return Err(validation_err("tabIds", "At least one tab ID is required"));
    }
    let mut ids = Vec::with_capacity(arr.len());
    for v in arr {
        let Some(s) = v.as_str() else {
            return Err(validation_err("tabIds", "Expected string UUID"));
        };
        if !is_valid_uuid(s) {
            return Err(validation_err("tabIds", "Invalid tab UUID"));
        }
        ids.push(s.to_string());
    }
    Ok(ids)
}

pub fn parse_bulk_update_tabs_schema(raw: &Value) -> Result<(Vec<String>, String), AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let ids = parse_bulk_delete_tabs_schema(raw)?;
    let Some(action) = obj.get("action").and_then(Value::as_str) else {
        return Err(validation_err("action", "Action is required"));
    };
    if action != "pin" && action != "unpin" {
        return Err(validation_err("action", "Invalid bulk action"));
    }
    Ok((ids, action.to_string()))
}

pub fn parse_reorder_tab_schema(raw: &Value) -> Result<i64, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(pos) = obj.get("newPosition").and_then(Value::as_i64) else {
        return Err(validation_err(
            "newPosition",
            "Expected non-negative integer",
        ));
    };
    if pos < 0 {
        return Err(validation_err("newPosition", "newPosition must be >= 0"));
    }
    Ok(pos)
}

pub fn parse_password_reset_schema(raw: &Value) -> Result<String, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(email) = obj.get("email").and_then(Value::as_str) else {
        return Err(validation_err("email", "Email is required"));
    };
    if !is_valid_email(email) {
        return Err(validation_err("email", "Invalid email address"));
    }
    Ok(email.to_string())
}

#[derive(Debug, Clone, PartialEq)]
pub struct SpaceGroupCreateInput {
    pub id: Option<String>,
    pub title: String,
    pub collapsed: bool,
    pub position: i64,
    pub color: Option<String>,
}

pub fn parse_space_group_create_schema(raw: &Value) -> Result<SpaceGroupCreateInput, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let id = match obj.get("id") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if s.is_empty() {
                return Err(validation_err("id", "ID cannot be empty"));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("id", "Expected string")),
    };
    let Some(title) = obj.get("title").and_then(Value::as_str) else {
        return Err(validation_err("title", "Title is required"));
    };
    if title.is_empty() || title.chars().count() > 255 {
        return Err(validation_err("title", "Title must be 1-255 characters"));
    }
    let collapsed = match obj.get("collapsed") {
        None => false,
        Some(Value::Bool(b)) => *b,
        Some(_) => return Err(validation_err("collapsed", "Expected boolean")),
    };
    let position = match obj.get("position") {
        None => 0,
        Some(Value::Number(n)) => {
            let Some(i) = n.as_i64() else {
                return Err(validation_err("position", "Expected integer"));
            };
            if i < 0 {
                return Err(validation_err("position", "Position must be >= 0"));
            }
            i
        }
        Some(_) => return Err(validation_err("position", "Expected integer")),
    };
    let color = match obj.get("color") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if !is_valid_hex_color(s) {
                return Err(validation_err("color", "Invalid hex color"));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("color", "Expected hex color string")),
    };
    Ok(SpaceGroupCreateInput {
        id,
        title: title.to_string(),
        collapsed,
        position,
        color,
    })
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct SpaceGroupUpdateInput {
    pub title: Option<String>,
    pub collapsed: Option<bool>,
    pub position: Option<i64>,
    pub color: Option<Option<String>>,
    pub base_version: Option<u64>,
}

pub fn parse_space_group_update_schema(raw: &Value) -> Result<SpaceGroupUpdateInput, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let title = match obj.get("title") {
        None => None,
        Some(Value::String(s)) => {
            if s.is_empty() || s.chars().count() > 255 {
                return Err(validation_err("title", "Title must be 1-255 characters"));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("title", "Expected string")),
    };
    let collapsed = match obj.get("collapsed") {
        None => None,
        Some(Value::Bool(b)) => Some(*b),
        Some(_) => return Err(validation_err("collapsed", "Expected boolean")),
    };
    let position = match obj.get("position") {
        None => None,
        Some(Value::Number(n)) => {
            let Some(i) = n.as_i64() else {
                return Err(validation_err("position", "Expected integer"));
            };
            if i < 0 {
                return Err(validation_err("position", "Position must be >= 0"));
            }
            Some(i)
        }
        Some(_) => return Err(validation_err("position", "Expected integer")),
    };
    let color = match obj.get("color") {
        None => None,
        Some(Value::Null) => Some(None),
        Some(Value::String(s)) => {
            if !is_valid_hex_color(s) {
                return Err(validation_err("color", "Invalid hex color"));
            }
            Some(Some(s.clone()))
        }
        Some(_) => return Err(validation_err("color", "Expected hex color string")),
    };
    let base_version = match obj.get("baseVersion") {
        None => None,
        Some(Value::Number(n)) => {
            let Some(v) = n.as_u64() else {
                return Err(validation_err(
                    "baseVersion",
                    "Expected non-negative integer",
                ));
            };
            Some(v)
        }
        Some(_) => return Err(validation_err("baseVersion", "Expected integer")),
    };
    Ok(SpaceGroupUpdateInput {
        title,
        collapsed,
        position,
        color,
        base_version,
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct BackupCreateInput {
    pub workspace_id: Option<String>,
    pub name: Option<String>,
    pub backup_type: String,
}

pub fn parse_backup_create_schema(raw: &Value) -> Result<BackupCreateInput, AppError> {
    if raw.is_null() {
        return Ok(BackupCreateInput {
            workspace_id: None,
            name: None,
            backup_type: "manual".to_string(),
        });
    }
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let workspace_id = match obj.get("workspaceId") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if s.is_empty() {
                return Err(validation_err(
                    "workspaceId",
                    "Workspace ID cannot be empty",
                ));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("workspaceId", "Expected string")),
    };
    let name = match obj.get("name") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if s.chars().count() > 255 {
                return Err(validation_err("name", "Backup name exceeds 255 characters"));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("name", "Expected string")),
    };
    let backup_type = match obj.get("type") {
        None | Some(Value::Null) => "manual".to_string(),
        Some(Value::String(s)) if s == "auto" || s == "manual" => s.clone(),
        Some(_) => return Err(validation_err("type", "Expected 'auto' or 'manual'")),
    };
    Ok(BackupCreateInput {
        workspace_id,
        name,
        backup_type,
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct BackupListQuery {
    pub workspace_id: Option<String>,
    pub backup_type: Option<String>,
    pub limit: usize,
    pub offset: usize,
    pub sort_by: String,
    pub sort_order: String,
}

pub fn parse_backup_list_query(
    query: &std::collections::HashMap<String, String>,
) -> Result<BackupListQuery, AppError> {
    let workspace_id = match query.get("workspaceId") {
        None => None,
        Some(s) if s.is_empty() => {
            return Err(validation_err("workspaceId", "Invalid workspaceId"))
        }
        Some(s) => Some(s.clone()),
    };
    let backup_type = match query.get("type") {
        None => None,
        Some(s) if s == "auto" || s == "manual" => Some(s.clone()),
        Some(_) => return Err(validation_err("type", "Expected 'auto' or 'manual'")),
    };
    let limit = match query.get("limit") {
        None => 20usize,
        Some(s) => {
            let Ok(n) = s.parse::<usize>() else {
                return Err(validation_err("limit", "Expected integer"));
            };
            if !(1..=100).contains(&n) {
                return Err(validation_err("limit", "Limit must be between 1 and 100"));
            }
            n
        }
    };
    let offset = match query.get("offset") {
        None => 0usize,
        Some(s) => {
            let Ok(n) = s.parse::<usize>() else {
                return Err(validation_err("offset", "Expected non-negative integer"));
            };
            n
        }
    };
    let sort_by = match query.get("sortBy").map(|s| s.as_str()) {
        None | Some("createdAt") => "createdAt".to_string(),
        Some("sizeBytes") => "sizeBytes".to_string(),
        Some(_) => {
            return Err(validation_err(
                "sortBy",
                "Expected 'createdAt' or 'sizeBytes'",
            ))
        }
    };
    let sort_order = match query.get("sortOrder").map(|s| s.as_str()) {
        None | Some("desc") => "desc".to_string(),
        Some("asc") => "asc".to_string(),
        Some(_) => return Err(validation_err("sortOrder", "Expected 'asc' or 'desc'")),
    };
    Ok(BackupListQuery {
        workspace_id,
        backup_type,
        limit,
        offset,
        sort_by,
        sort_order,
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct BackupRestoreInput {
    pub target_workspace_id: Option<String>,
    pub merge: bool,
    pub create_new: bool,
}

pub fn parse_backup_restore_schema(raw: &Value) -> Result<BackupRestoreInput, AppError> {
    if raw.is_null() {
        return Ok(BackupRestoreInput {
            target_workspace_id: None,
            merge: false,
            create_new: false,
        });
    }
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let target_workspace_id = match obj.get("targetWorkspaceId") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if s.is_empty() {
                return Err(validation_err(
                    "targetWorkspaceId",
                    "Target workspace ID cannot be empty",
                ));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("targetWorkspaceId", "Expected string")),
    };
    let merge = match obj.get("merge") {
        None => false,
        Some(Value::Bool(b)) => *b,
        Some(_) => return Err(validation_err("merge", "Expected boolean")),
    };
    let create_new = match obj.get("createNew") {
        None => false,
        Some(Value::Bool(b)) => *b,
        Some(_) => return Err(validation_err("createNew", "Expected boolean")),
    };
    Ok(BackupRestoreInput {
        target_workspace_id,
        merge,
        create_new,
    })
}

pub fn parse_share_by_email_schema(raw: &Value) -> Result<(String, String), AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(email) = obj.get("email").and_then(Value::as_str) else {
        return Err(validation_err("email", "Email is required"));
    };
    if email.chars().count() > 320 || !is_valid_email(email) {
        return Err(validation_err("email", "Invalid email address"));
    }
    let Some(role) = obj.get("role").and_then(Value::as_str) else {
        return Err(validation_err("role", "Role is required"));
    };
    if role != "view" && role != "edit" {
        return Err(validation_err("role", "Role must be 'view' or 'edit'"));
    }
    Ok((email.to_string(), role.to_string()))
}

pub fn parse_set_collaborator_role_schema(raw: &Value) -> Result<String, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(role) = obj.get("role").and_then(Value::as_str) else {
        return Err(validation_err("role", "Role is required"));
    };
    if role != "view" && role != "edit" {
        return Err(validation_err("role", "Role must be 'view' or 'edit'"));
    }
    Ok(role.to_string())
}

#[derive(Debug, Clone, PartialEq)]
pub struct CreateShareLinkInput {
    pub role: String,
    pub label: Option<String>,
    pub expires_at: Option<String>,
}

pub fn parse_create_share_link_schema(raw: &Value) -> Result<CreateShareLinkInput, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(role) = obj.get("role").and_then(Value::as_str) else {
        return Err(validation_err("role", "Role is required"));
    };
    if role != "view" && role != "edit" {
        return Err(validation_err("role", "Role must be 'view' or 'edit'"));
    }
    let label = match obj.get("label") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if s.chars().count() > 255 {
                return Err(validation_err("label", "Label exceeds 255 characters"));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("label", "Expected string")),
    };
    let expires_at = match obj.get("expiresAt") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            if parse_datetime_ms(s).is_none() {
                return Err(validation_err("expiresAt", "Invalid ISO datetime"));
            }
            Some(s.clone())
        }
        Some(_) => return Err(validation_err("expiresAt", "Expected datetime string")),
    };
    Ok(CreateShareLinkInput {
        role: role.to_string(),
        label,
        expires_at,
    })
}

pub fn parse_share_link_token_body(raw: &Value) -> Result<String, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(token) = obj.get("token").and_then(Value::as_str) else {
        return Err(validation_err("token", "Token is required"));
    };
    if token.is_empty() || token.len() > 128 {
        return Err(validation_err(
            "token",
            "Token must be between 1 and 128 characters",
        ));
    }
    Ok(token.to_string())
}

#[derive(Debug, Clone, PartialEq)]
pub struct SyncChangeInput {
    pub entity_type: String,
    pub action: String,
    pub entity_id: String,
    pub data: Option<Map<String, Value>>,
    pub version: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SyncPushInput {
    pub device_id: String,
    pub client_timestamp_ms: i64,
    pub changes: Vec<SyncChangeInput>,
}

pub fn parse_sync_push_schema(raw: &Value) -> Result<SyncPushInput, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(device_id) = obj.get("deviceId").and_then(Value::as_str) else {
        return Err(validation_err("deviceId", "deviceId is required"));
    };
    if device_id.is_empty() || device_id.chars().count() > 255 {
        return Err(validation_err("deviceId", "Invalid deviceId"));
    }
    let client_timestamp_ms = match obj.get("clientTimestamp") {
        Some(Value::String(s)) => parse_datetime_ms(s)
            .ok_or_else(|| validation_err("clientTimestamp", "Invalid timestamp"))?,
        Some(Value::Number(n)) => n
            .as_i64()
            .ok_or_else(|| validation_err("clientTimestamp", "Invalid timestamp"))?,
        _ => {
            return Err(validation_err(
                "clientTimestamp",
                "clientTimestamp is required",
            ))
        }
    };
    let Some(Value::Array(arr)) = obj.get("changes") else {
        return Err(validation_err("changes", "Expected array"));
    };
    let mut changes = Vec::with_capacity(arr.len());
    for item in arr {
        let Some(c_obj) = item.as_object() else {
            return Err(validation_err("changes", "Expected object"));
        };
        let Some(entity_type) = c_obj.get("type").and_then(Value::as_str) else {
            return Err(validation_err("type", "Entity type is required"));
        };
        if entity_type != "workspace" && entity_type != "spaceGroup" {
            return Err(validation_err("type", "Invalid entity type"));
        }
        let Some(action) = c_obj.get("action").and_then(Value::as_str) else {
            return Err(validation_err("action", "Action is required"));
        };
        if action != "create" && action != "update" && action != "delete" {
            return Err(validation_err("action", "Invalid action"));
        }
        let Some(entity_id) = c_obj.get("entityId").and_then(Value::as_str) else {
            return Err(validation_err("entityId", "entityId is required"));
        };
        if entity_id.is_empty() {
            return Err(validation_err("entityId", "entityId cannot be empty"));
        }
        let data = match c_obj.get("data") {
            None | Some(Value::Null) => None,
            Some(Value::Object(m)) => Some(m.clone()),
            Some(_) => return Err(validation_err("data", "Expected object")),
        };
        let version = match c_obj.get("version") {
            None => 0u64,
            Some(Value::Number(n)) => n
                .as_u64()
                .ok_or_else(|| validation_err("version", "Expected non-negative integer"))?,
            Some(_) => return Err(validation_err("version", "Expected integer")),
        };
        changes.push(SyncChangeInput {
            entity_type: entity_type.to_string(),
            action: action.to_string(),
            entity_id: entity_id.to_string(),
            data,
            version,
        });
    }
    Ok(SyncPushInput {
        device_id: device_id.to_string(),
        client_timestamp_ms,
        changes,
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct SyncPullInput {
    pub device_id: String,
    pub last_sync_at_ms: Option<i64>,
    pub entity_types: Vec<String>,
}

pub fn parse_sync_pull_schema(raw: &Value) -> Result<SyncPullInput, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let Some(device_id) = obj.get("deviceId").and_then(Value::as_str) else {
        return Err(validation_err("deviceId", "deviceId is required"));
    };
    if device_id.is_empty() || device_id.chars().count() > 255 {
        return Err(validation_err("deviceId", "Invalid deviceId"));
    }
    let last_sync_at_ms = match obj.get("lastSyncAt") {
        None | Some(Value::Null) => None,
        Some(Value::String(s)) => {
            Some(parse_datetime_ms(s).ok_or_else(|| validation_err("lastSyncAt", "Invalid date"))?)
        }
        Some(Value::Number(n)) => Some(
            n.as_i64()
                .ok_or_else(|| validation_err("lastSyncAt", "Invalid date"))?,
        ),
        Some(_) => return Err(validation_err("lastSyncAt", "Invalid date")),
    };
    let entity_types = match obj.get("entityTypes") {
        None => vec!["workspace".to_string(), "spaceGroup".to_string()],
        Some(Value::Array(arr)) => {
            let mut types = Vec::with_capacity(arr.len());
            for v in arr {
                let Some(s) = v.as_str() else {
                    return Err(validation_err("entityTypes", "Expected string"));
                };
                if s != "workspace" && s != "spaceGroup" {
                    return Err(validation_err("entityTypes", "Invalid entity type"));
                }
                types.push(s.to_string());
            }
            types
        }
        Some(_) => return Err(validation_err("entityTypes", "Expected array")),
    };
    Ok(SyncPullInput {
        device_id: device_id.to_string(),
        last_sync_at_ms,
        entity_types,
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct UserUpdateInput {
    pub name: Option<String>,
    pub preferences: Option<Map<String, Value>>,
}

pub fn parse_user_update_schema(raw: &Value) -> Result<UserUpdateInput, AppError> {
    let Some(obj) = raw.as_object() else {
        return Err(validation_err("body", "Expected object"));
    };
    let name = match obj.get("name") {
        None => None,
        Some(Value::String(s)) => {
            let trimmed = s.trim();
            if trimmed.is_empty() {
                return Err(validation_err("name", "Name cannot be empty"));
            }
            if trimmed.chars().count() > 255 {
                return Err(validation_err("name", "Name is too long"));
            }
            Some(trimmed.to_string())
        }
        Some(_) => return Err(validation_err("name", "Expected string")),
    };
    let preferences = match obj.get("preferences") {
        None => None,
        Some(Value::Object(m)) => Some(m.clone()),
        Some(_) => return Err(validation_err("preferences", "Expected object")),
    };
    Ok(UserUpdateInput { name, preferences })
}
