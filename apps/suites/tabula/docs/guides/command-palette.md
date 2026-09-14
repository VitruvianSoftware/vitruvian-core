# Command Palette (Global Search)

## Overview

The Command Palette is a powerful global search feature that allows you to quickly find and navigate
to workspaces, resources, tabs, notes, and tasks across your entire Tabula workspace. It provides
instant access to any item with keyboard-driven navigation.

## Features

- **Global Search**: Search across all workspaces, resources, tabs, notes, and tasks
- **Search History**: Automatically saves your recent searches for quick access
- **Type Filters**: Filter results by type (all, workspace, resource, tab, note, task)
- **Keyboard-First Design**: Fast navigation using keyboard shortcuts
- **Fuzzy Matching**: Intelligent search that finds relevant results even with partial matches
- **Type Indicators**: Visual badges showing the type of each result (workspace, resource, tab,
  note, task)
- **Context Information**: Shows which workspace each item belongs to

## Opening the Command Palette

### Keyboard Shortcut

Press **`Cmd+K`** (Mac) or **`Ctrl+K`** (Windows/Linux) from anywhere in the dashboard to open the
Command Palette.

Press **`Escape`** to close it at any time.

## Using the Command Palette

### 1. Basic Search

1. Press `Cmd+K` (or `Ctrl+K`) to open the Command Palette
2. Start typing to search across all your content
3. Results appear instantly as you type

### 2. Navigating Results

- **Arrow Down** (`↓`): Move selection down
- **Arrow Up** (`↑`): Move selection up
- **Enter** (`↵`): Select the highlighted result
- **Escape** (`Esc`): Close the Command Palette

### 3. Search Result Types

The Command Palette searches across five content types and can filter by type:

#### Filtering Results

Use the filter buttons at the top of the search results to narrow down by type:

- **All**: Shows all result types (default)
- **Workspace**: Only shows workspaces
- **Resource**: Only shows resources
- **Tab**: Only shows tabs
- **Note**: Only shows notes
- **Task**: Only shows tasks

Click any filter button to activate it, or click "All" to see all results again.

#### Workspaces

- **Icon**: Dashboard icon
- **Action**: Switches to the selected workspace

#### Resources

- **Icon**: Link icon
- **Action**: Opens the resource URL in a new tab
- **Context**: Shows which workspace and section (if any) contains the resource

#### Tabs

- **Icon**: Tab icon
- **Action**: Opens the tab URL in a new browser tab
- **Context**: Shows which workspace the tab belongs to

#### Notes

- **Icon**: Description icon
- **Action**: Switches to the workspace containing the note
- **Context**: Shows a preview of the note content

#### Tasks

- **Icon**: Checkbox icon
- **Action**: Switches to the workspace containing the task
- **Context**: Shows whether the task is completed or pending

## Search Tips

### 1. Using Search History

When you open the Command Palette without typing, you'll see your recent searches:

- **Recent Searches**: Last 10 searches are automatically saved
- **Click to Reuse**: Click any recent search to fill the search box
- **Quick Access**: Quickly repeat previous searches without retyping

### 2. Using Filters

Click the filter buttons to narrow your search:

```
Example: Click "Resource" filter → Only resources will appear in results
```

Filters work with or without a search query.

### 3. Search by Name

Simply type part of the name of any workspace, resource, tab, note, or task:

```
Example: "docs" → finds "Documentation" workspace, "API Docs" resource, etc.
```

### 4. Search by URL

For resources and tabs, you can search by their URL:

```
Example: "github" → finds all resources and tabs with "github" in their URL
```

### 5. Search by Content

For notes, you can search by their content:

```
Example: "meeting" → finds notes containing "meeting" in their title or content
```

### 6. Empty Results

If no results match your search, you'll see a "No results found" message.

## Examples

### Example 1: Finding a Workspace

1. Press `Cmd+K`
2. Type "project alpha"
3. Select the "Project Alpha" workspace from results
4. The workspace becomes active

### Example 2: Opening a Resource

1. Press `Cmd+K`
2. Type "api documentation"
3. Select the resource from results
4. The resource URL opens in a new tab

### Example 3: Finding a Task

1. Press `Cmd+K`
2. Type "review pr"
3. Select the task from results
4. Switches to the workspace containing that task

## Keyboard Shortcuts Reference

| Shortcut           | Action                    |
| ------------------ | ------------------------- |
| `Cmd+K` / `Ctrl+K` | Open Command Palette      |
| `↓`                | Move selection down       |
| `↑`                | Move selection up         |
| `↵` (Enter)        | Select highlighted result |
| `Esc`              | Close Command Palette     |

## UI Components

### Filter Buttons

- Row of filter buttons below the search input
- Active filter highlighted in blue
- Click to toggle between filters
- Filters: All, Workspace, Resource, Tab, Note, Task

### Search History

- Appears when opening Command Palette with no search query
- Shows "Recent Searches" header
- Lists up to 10 recent searches
- Click any item to fill the search box
- Automatically saved to local storage

### Search Input

- Large, prominent search field
- Placeholder text: "Search workspaces, resources, tabs, notes, and tasks..."
- Auto-focuses when the Command Palette opens

### Results List

- Displays up to 50 results at a time
- Scrollable if more results exist
- Each result shows:
  - Icon (type indicator)
  - Title
  - Subtitle (URL, content preview, or status)
  - Workspace context (for non-workspace items)
  - Type badge

### Footer Hints

- Visual keyboard shortcut hints
- Shows available navigation actions

## Best Practices

1. **Use Specific Keywords**: The more specific your search term, the better the results
2. **Try Partial Matches**: You don't need to type the full name - "doc" can find "Documentation"
3. **Check Context**: Pay attention to the workspace context shown for each result
4. **Use Keyboard Navigation**: It's faster than using the mouse for selection

## Accessibility

- **Keyboard Accessible**: All functionality available via keyboard
- **Screen Reader Support**: Semantic HTML elements and ARIA labels
- **Focus Management**: Proper focus trapping within the modal
- **Visual Indicators**: Clear visual feedback for selected items

## Technical Details

### Search Algorithm

- Case-insensitive matching
- Searches across multiple fields (title, subtitle, URL, content)
- Results ranked by relevance:
  1. Exact matches (highest priority)
  2. Matches at start of text
  3. Matches within text
  4. Context matches (workspace name, etc.)

### Performance

- Instant search with no debouncing needed
- Efficient indexing of all workspace data
- Results update in real-time as you type
- Handles large workspaces with hundreds of items

## Troubleshooting

### Command Palette Won't Open

- Ensure you're pressing the correct key combination (`Cmd+K` on Mac, `Ctrl+K` on Windows/Linux)
- Make sure no other modal or dialog is open
- Try clicking in the main dashboard area first

### No Results Found

- Check your spelling
- Try a shorter, more general search term
- Verify that the item exists in your workspaces

### Search is Slow

- The Command Palette should be instant - if it's slow, try refreshing the page
- Clear browser cache if problems persist

## Related Features

- **Workspace Switching**: Click workspaces in sidebar
- **Resource Management**: Manage resources in the Resources tab
- **Task Management**: Create and complete tasks in Tasks tab
- **Notes**: Create and edit notes in Notes tab

## Future Enhancements

Planned improvements to the Command Palette:

- ~~Search history~~ ✅ **Implemented in Phase 2**
- ~~Type filters~~ ✅ **Implemented in Phase 2**
- Recent items section (show recently accessed items first)
- Search within specific workspace
- Custom keyboard shortcuts
- Fuzzy matching improvements
- Action commands (e.g., "create new workspace")
- Clear search history option
