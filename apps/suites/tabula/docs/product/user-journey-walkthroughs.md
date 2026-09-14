# User Journey Walkthroughs

This document provides detailed walkthroughs for core user journeys in the Tabula application.

---

## 1. Creating a New Space

**Objective**: Create a new top-level workspace to organize project resources.

### Steps:

1. **Navigate to Dashboard**: Open the Tabula Dashboard.
2. **Access the Add Menu**: Click the '+' (Add) button next to "SPACES" in the sidebar.
3. **Select New Space**: Choose "New space" from the dropdown menu.
4. **Enter Space Name**: In the "New Workspace" modal, enter `User Journey Space`.
5. **Confirm**: Click the "Create" button.

### Screenshots:

![Initial Dashboard State](images/initial_dashboard_state_1766780594921.png) _Initial state of the
dashboard._

![Add Menu](images/add_menu_opened_1766780603811.png) _Dropdown menu with "New space" option._

![Naming Modal](images/naming_modal_opened_1766780613119.png) _Modal for naming the new Space._

![Final Dashboard with New Space](images/final_dashboard_with_new_space_1766780631669.png)
_Dashboard showing the newly created Space in the sidebar._

---

## 2. Adding a Resource

**Objective**: Add a link or document to a space for easy access.

### Steps:

1. **Navigate to the Space**: Select the target space (e.g., `User Journey Space`) from the sidebar.
2. **Open the Resource Menu**: Click the '+' (Add resource) button in the Resources section header.
3. **Select Add Resource**: Choose "Add resource" from the dropdown.
4. **Enter Resource Details**: Fill in the 'Title' (e.g., `Google`) and 'URL' (e.g.,
   `https://google.com`).
5. **Save**: Click the "Save" button.

### Screenshots:

![Empty Resources Tab](images/resources_tab_before_1766780665346.png) _Resources tab before adding
any resources._

![Add Resource Form](images/add_resource_form_modal_1766780690005.png) _Inline form for entering
resource title and URL._

![Success Screenshot](images/resources_tab_final_success_1766780756149.png) _The 'Google' resource
successfully added to the space._

---

## 3. Creating a Resource Section

**Objective**: Organize resources into logical groups within a space.

### Steps:

1. **Navigate to the Space**: Select the target space (e.g., `User Journey Space`) from the sidebar.
2. **Access the Add Section Button**: Locate and click the `+ RESOURCE SECTION` button at the bottom
   of the Resources list.
3. **Enter Section Name**: Type a name for your section (e.g., `Documentation`) into the 'Section
   Title' input field.
4. **Save**: Click the "Save" button to create the section.

### Screenshots:

![Add Section Button](images/add_section_menu_1766780845693.png) _The '+ RESOURCE SECTION' button at
the bottom of the list._

![Section Name Input](images/add_section_input_field_1766780864486.png) _Entering the section
title._

![New Section Added](images/final_added_section_1766780877310.png) _The new 'Documentation' section
successfully created._

---

## 4. Managing Tasks

**Objective**: Add and complete tasks to track progress within a space.

### Steps:

1. **Navigate to Tasks**: Select the target space and click the 'Tasks' tab.
2. **Add a Task**: Click in the "Add a new task..." field at the top.
3. **Save Task**: Enter your task title (e.g., `Write Documentation`) and press Enter.
4. **Complete Task**: Click the checkbox next to the task to mark it as complete.

### Screenshots:

![Empty Tasks Tab](images/empty_tasks_tab_1766780909903.png) _Initial empty state of the Tasks tab._

![Adding a Task](images/task_list_with_new_task_1766780930045.png) _The task list with a newly added
task._

![Task Completed](images/task_list_completed_task_1766780939463.png) _Marking a task as complete._

---

## 5. Creating Notes

**Objective**: Use the Notes tab for documentation and quick thoughts.

### Steps:

1. **Navigate to Notes**: Select the target space and click the 'Notes' tab.
2. **Create New Note**: Click the **+ New Note** button.
3. **Enter Details**: Type a title (e.g., `Project Overview`) and your note content.
4. **Save**: Click the **Save** button.

### Screenshots:

_Initial empty state of the Notes tab._

_Entering note title and content._

_The saved note displayed in the list._

---

## 6. Switching Between Spaces

**Objective**: Seamlessly navigate between different workspaces.

### Steps:

1. **Locate Sidebar**: Find the 'SPACES' list in the left sidebar.
2. **Select Another Space**: Click on a different space (e.g., `Space A`).
3. **Observe Change**: The main content area updates to show resources and notes for the selected
   space.
4. **Switch Back**: Click on your original space (e.g., `User Journey Space`) to return.

### Screenshots:

_Viewing content for Space A._

_Viewing
content for User Journey Space._

---

## 7. Organizing Spaces with Groups (Sections)

**Objective**: Organize your workspaces into groups (sections) for better navigation and management
using drag and drop or the context menu.

### Overview:

Tabula allows you to organize multiple workspaces into named groups (also called "sections") in the
sidebar. This helps you:

- **Categorize** workspaces by project, client, or workflow stage
- **Collapse/expand** groups to reduce visual clutter
- **Reorder** groups and workspaces within them
- **Move** workspaces between groups effortlessly

### Creating a Section:

1. **Access the Add Menu**: Click the '+' (Add) button next to "SPACES" in the sidebar.
2. **Select New Section**: Choose "New section" from the dropdown menu.
3. **Enter Section Name**: In the modal, enter a name (e.g., `Work Projects`, `Personal`,
   `Archive`).
4. **Confirm**: Click the "Create" button.

The new section appears in the sidebar as a collapsible group header.

### Moving Workspaces to Groups:

#### Method 1: Drag and Drop (Recommended)

1. **Select a Workspace**: Click and hold on any workspace in the sidebar.
2. **Drag to Group**: Drag the workspace over the target group header or drop zone.
   - The drop zone will highlight with a dashed outline when hovering.
3. **Release**: Release the mouse button to drop the workspace into the group.
4. **Verify**: The workspace now appears indented under the group.

**Use Cases:**

- **Drag ungrouped workspace to a group**: Moves a workspace from the top-level list into a group
- **Drag workspace between groups**: Moves a workspace from one group to another
- **Drag workspace from group to ungrouped area**: Drag onto another ungrouped workspace to remove
  it from its group
- **Reorder within group**: Drag workspaces up or down within the same group to reorder them

#### Method 2: Context Menu

1. **Open Workspace Menu**: Click the three-dot menu (⋮) next to the workspace name.
2. **Select Move to Section**: Click "Move to section" in the dropdown.
3. **Choose Target Group**: A submenu appears showing all available groups.
4. **Select Group**: Click the target group name (or "No section" to ungroup).
5. **Confirm**: The workspace immediately moves to the selected group.

### Collapsing/Expanding Groups:

- **Collapse**: Click the chevron (▼) icon next to a group name to hide its workspaces.
- **Expand**: Click the chevron (▶) icon to show the workspaces again.

Collapsed state is saved automatically.

### Managing Groups:

1. **Open Group Menu**: Click the three-dot menu (⋮) next to the group header.
2. **Rename**: Select "Rename" and enter a new name.
3. **Change Color**: Select "Change color" and pick a color to visually distinguish the group.
4. **Delete**: Select "Delete" to remove the group.
   - **Note**: Deleting a group does NOT delete the workspaces; they become ungrouped.

### Visual Color Accents:

Tabula uses colors to visually distinguish workspaces in the sidebar. When you select a workspace, a
colored accent bar appears on the left side of the active workspace item.

**Color Priority:**

| Priority | Source          | Description                               |
| -------- | --------------- | ----------------------------------------- |
| 1        | Workspace Color | Individual color set on the workspace     |
| 2        | Group Color     | Color from the workspace's parent group   |
| 3        | Default Blue    | Standard blue accent when no color is set |

**Setting Workspace Colors:**

1. Open the workspace context menu (three-dot icon next to workspace name).
2. Select "Change color" from the dropdown.
3. Choose a color from the palette, or select "None" to remove the color.

**Setting Group Colors:**

1. Open the group context menu (three-dot icon next to group header).
2. Select "Change color" from the dropdown.
3. Choose a color that all workspaces in this group will inherit.

> [!TIP] Use workspace-specific colors for your most important or frequently accessed workspaces.
> Use group colors as a fallback to categorize related workspaces (e.g., all "Work" workspaces in
> red, all "Personal" workspaces in green).

### Best Practices:

- Use groups to separate active projects from archived ones
- Create groups by client or team for work-related spaces
- Keep frequently accessed spaces ungrouped for quick access
- Use colors to visually distinguish different categories
- Collapse groups you rarely use to reduce sidebar clutter
- Assign unique colors to high-priority workspaces for quick identification

### Screenshots:

_Note: Screenshots will be added showing:_

1. **Creating a new section** via the Add menu
2. **Dragging a workspace into a group** with the drop zone highlighted
3. **Moving a workspace via context menu** with the "Move to section" submenu open
4. **Final organized sidebar** with multiple groups and workspaces properly organized
5. **Collapsed group** showing the chevron icon and hidden workspaces

---

## 8. Editing and Deleting Resources

**Objective**: Modify or remove resources when they are no longer needed.

### Steps:

1. **Locate Resource**: In the Resources tab, find the resource you wish to manage.
2. **Open Menu**: Hover over the resource to reveal the 'Edit' (pencil) and 'Remove' (trash) icons.
3. **Edit Resource**:
   - Click the 'Edit' icon.
   - Update the 'Title' or 'URL' in the modal.
   - Click 'Save'.
4. **Delete Resource**:
   - Click the 'Remove' icon.
   - The resource will be immediately removed from the list.

### Screenshots:

_Hovering over a resource to
reveal management icons._

_Updating resource details._

_The space after deleting the
resource._

---

## 9. Renaming a Space

**Objective**: Personalize the name of a workspace.

### Steps:

1. **Open Space Menu**: Click the 'Three dots' (Space options) icon next to the space name in the
   sidebar.
2. **Select Rename**: Choose "Rename" from the dropdown menu.
3. **Enter New Name**: In the modal, type the new name (e.g., `Final Workspace`).
4. **Save**: Click the "Save" button to apply the change.

### Screenshots:

_Selecting the Rename option
from the space menu._

_Entering the new workspace name._

_The sidebar showing the renamed
'Final Workspace'._

---

## 10. Sharing a Space

**Objective**: Access sharing features to collaborate with others.

### Steps:

1. **Locate Share Button**: Find the primary 'Share' button in the top right corner of the workspace
   header.
2. **Access via Menu**: Alternatively, open the 'Space options' (three dots) in the sidebar and
   select "Share".
3. **Collaborate**: Use the sharing options provided (e.g., invite via email or link sharing).

> [!NOTE] In the current version, the 'Share' feature may be a navigational placeholder or trigger a
> browser-native sharing interface.

### Screenshots:

_Location of the 'Share'
button in the workspace._

---

## 11. User Profile and Settings

**Objective**: Manage user account and application settings.

### Steps:

1. **Open User Menu**: Click the circular profile avatar in the top left header (next to the logo).
2. **Access Settings**: Click the 'Settings' option in the dropdown menu.
3. **Manage Account**: View your name, email, and subscription plan.
4. **Adjust Preferences**: Switch to the 'Preferences' tab to manage app-wide settings.

### Screenshots:

_The user menu showing name, email, and
navigation options._

_The settings modal with Account and
Preferences tabs._

---

## 12. Global Search with Command Palette

**Objective**: Quickly find and navigate to any workspace, resource, tab, note, or task using the
Command Palette.

### Steps:

1. **Open Command Palette**: Press `Cmd+K` (Mac) or `Ctrl+K` (Windows/Linux) from anywhere in the
   dashboard.
2. **Search**: Start typing to search across all your content (e.g., "documentation", "github",
   "meeting notes").
3. **Navigate Results**: Use arrow keys (`↓` / `↑`) to move through search results.
4. **Select**: Press `Enter` to select the highlighted result.
5. **Close**: Press `Escape` to close the Command Palette without selecting.

### Features:

- **Universal Search**: Searches across workspaces, resources, tabs, notes, and tasks
- **Instant Results**: See results as you type with intelligent ranking
- **Type Indicators**: Visual badges show the type of each result
- **Context Information**: Shows which workspace each item belongs to
- **Keyboard Navigation**: Fast, keyboard-first interface

### Use Cases:

- **Switch Workspaces**: Search for "Project Alpha" to quickly switch to that workspace
- **Open Resources**: Search for "API docs" to open resource links in new tabs
- **Find Tasks**: Search for "review PR" to jump to the workspace containing that task
- **Locate Notes**: Search note content to find specific information

### Keyboard Shortcuts:

| Shortcut           | Action               |
| ------------------ | -------------------- |
| `Cmd+K` / `Ctrl+K` | Open Command Palette |
| `↓`                | Move selection down  |
| `↑`                | Move selection up    |
| `Enter`            | Select result        |
| `Escape`           | Close                |

### Screenshots:

_Note: Screenshots will be added after feature is deployed to production._

**Command Palette Overview**: Shows the search interface with input field, results list, and
keyboard hints.

**Search Results**: Displays different types of results (workspaces, resources, tabs) with type
badges and context information.

**Empty State**: Shows "No results found" message when search query doesn't match any items.

---

## 13. Backup & Restore

**Objective**: Protect your workspaces with automatic and manual backups, and restore from any point
in time.

### Accessing Backups:

1. **Open User Menu**: Click the circular profile avatar in the top left header.
2. **Access Settings**: Click "Settings" in the dropdown menu.
3. **Select Backups Tab**: Click the "Backups" tab in the Settings modal sidebar.

### Creating a Manual Backup:

1. **Navigate to Backups Tab**: Open Settings → Backups.
2. **Click Create Backup**: Press the "Create Backup Now" button.
3. **Wait for Completion**: The backup is created and appears in the Recent Backups list.

### Automatic Backups:

Tabula automatically creates backups when you switch between workspaces:

- **Trigger**: Every workspace switch
- **Type**: Tagged as "auto" backup
- **Non-blocking**: Switch completes even if backup fails
- **Requirement**: User must be logged in

### Restoring from Backup:

1. **Find Backup**: Locate the backup in the Recent Backups list.
2. **Click Restore**: Press the "Restore" button next to the backup.
3. **Confirm**: The page reloads with your restored workspace data.

### Backup Stats:

The Backups tab displays:

- **Total Backups**: Number of backups in your account
- **Storage Used**: Total size of all backups

### Backup Retention (by Tier):

| Tier     | Retention Period |
| -------- | ---------------- |
| Free     | 30 days          |
| Pro      | 90 days          |
| Business | 365 days         |

### Screenshots:

_Note: Screenshots will be added showing:_

1. **Backups Tab**: The Settings modal with Backups tab selected
2. **Create Backup**: The "Create Backup Now" button and loading state
3. **Backup List**: Recent backups with Restore and Delete buttons
4. **Backup Stats**: Total backups and storage used display
