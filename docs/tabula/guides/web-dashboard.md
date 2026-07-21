# Web Dashboard

## Overview

The Tabula Web Dashboard is a browser-based interface that provides a comprehensive view of your
workspaces, analytics, and data management capabilities. Built with Next.js 14, it offers a modern,
responsive experience for managing your Tabula data from any device.

## Features

- **Dashboard Overview**: View statistics for all workspaces at a glance
- **Workspace Browser**: Browse and search all your workspaces
- **Analytics**: Detailed insights into your workspace usage and productivity
- **Data Export**: Export your data in JSON or CSV format
- **Responsive Design**: Works seamlessly on desktop, tablet, and mobile devices
- **Real-time Data**: Automatically syncs with your browser extension data

## Accessing the Web Dashboard

### Development Mode

To run the web dashboard locally:

```bash
# From the repository root
npm run dev --workspace=@tabula/web

# Or using tabcli
tabcli dev start --web
```

The dashboard will be available at `http://localhost:3000`.

### Production Build

To build the web dashboard for production:

```bash
# From the repository root
npm run build --workspace=@tabula/web

# Start the production server
npm run start --workspace=@tabula/web
```

## Pages

### Home Dashboard

**URL**: `/`

The home page provides an at-a-glance view of your Tabula data:

- **Statistics Cards**: Quick metrics showing:
  - Total workspaces
  - Total open tabs
  - Total resources
  - Total notes
  - Task completion status
  - Completion rate percentage

- **Quick Actions**:
  - View Workspaces
  - Analytics
  - Export Data

- **Export Buttons**:
  - Export JSON: Download all workspace data as JSON
  - Export CSV: Download workspace summary as CSV

### Workspaces Page

**URL**: `/workspaces`

Browse and search all your workspaces:

- **Search Bar**: Filter workspaces by name or description
- **Workspace Cards**: Each card displays:
  - Workspace name and icon
  - Description (if available)
  - Tab count
  - Resource count
  - Note count
  - Task completion status
  - Recent tabs preview (first 3 tabs)

### Analytics Page

**URL**: `/analytics`

View detailed analytics and insights:

- **Summary Metrics**:
  - Total workspaces
  - Total tabs
  - Total resources
  - Task completion percentage

- **Workspace Distribution**:
  - Visual bars showing tab distribution across workspaces
  - Top 5 workspaces by tab count

- **Insights**:
  - Most active workspace (highest tab count)
  - Most resourced workspace (highest resource count)
  - Productivity score (task completion)

- **Content Breakdown**:
  - Total notes
  - Total resources
  - Active tabs

## Data Export

The web dashboard supports two export formats:

### JSON Export

Exports complete workspace data including:

- All workspaces with full details
- Tabs (URLs, titles)
- Resources (organized by sections)
- Notes (with content)
- Tasks (with completion status)

**Format**: Formatted JSON with 2-space indentation

**Filename**: `tabula-export-YYYY-MM-DD.json`

### CSV Export

Exports workspace summary data:

- Workspace name
- Description
- Tab count
- Resource count
- Note count
- Task count
- Completed task count

**Format**: Standard CSV with headers

**Filename**: `tabula-export-YYYY-MM-DD.csv`

## Data Source

The web dashboard reads data from:

1. **Chrome Storage** (when running as extension context)
   - Direct access to `tabula_workspaces` storage key
   - Real-time sync with extension data

2. **Local Storage** (fallback)
   - Used when Chrome Storage is not available
   - Useful for standalone web deployment

## Technical Stack

- **Framework**: Next.js 14 (App Router)
- **Language**: TypeScript
- **Styling**: Tailwind CSS 4
- **State Management**: React hooks (useState, useEffect)
- **Data Layer**: Custom DataService for storage abstraction

## Responsive Design

The dashboard is fully responsive and optimized for:

- **Desktop**: Full-width layout with multi-column grids
- **Tablet**: Responsive grid layout (2 columns)
- **Mobile**: Single-column layout with touch-friendly interactions

Breakpoints follow Tailwind CSS conventions:

- `sm`: 640px and up
- `lg`: 1024px and up

## Best Practices

### 1. Regular Data Export

Export your data regularly to maintain backups:

- Use JSON export for complete backup
- Use CSV export for analysis in spreadsheet tools

### 2. Monitor Analytics

Check the analytics page regularly to:

- Identify unused workspaces
- Track productivity trends
- Monitor resource distribution

### 3. Search Effectively

Use the workspace search to quickly find specific workspaces:

- Search by workspace name
- Search by description keywords

## Deployment

The web dashboard can be deployed to various platforms:

### Vercel (Recommended)

```bash
# Install Vercel CLI
npm install -g vercel

# Deploy from web directory
cd web
vercel
```

### Cloudflare Pages

```bash
# Build the application
npm run build --workspace=@tabula/web

# Deploy the .next/static folder to Cloudflare Pages
```

### Self-Hosted

```bash
# Build and start
npm run build --workspace=@tabula/web
npm run start --workspace=@tabula/web
```

## Environment Variables

Currently, the web dashboard does not require environment variables. Future versions may include:

- `NEXT_PUBLIC_API_URL`: API endpoint for backend integration
- `NEXT_PUBLIC_AUTH_DOMAIN`: Authentication provider domain

## Future Enhancements

Planned improvements for the web dashboard:

- **Authentication**: User login and account management
- **API Integration**: Sync with backend API for cross-device data
- **Real-time Collaboration**: Share workspaces with team members
- **Advanced Analytics**: Charts and graphs for trend analysis
- **Data Import**: Import workspaces from JSON/CSV
- **Workspace Editor**: Edit workspace details from the web
- **Dark Mode**: Theme switching support
- **PWA Support**: Install as Progressive Web App

## Troubleshooting

### Dashboard Shows No Data

**Problem**: Dashboard displays "No workspaces yet"

**Solutions**:

1. Ensure you have created workspaces in the browser extension
2. Check that the browser extension has saved data to storage
3. Try refreshing the page
4. Clear browser cache and reload

### Export Not Working

**Problem**: Export button doesn't download file

**Solutions**:

1. Check browser console for errors
2. Ensure browser allows downloads from localhost (dev mode)
3. Try a different browser
4. Check browser download settings

### Search Not Responding

**Problem**: Search bar doesn't filter workspaces

**Solutions**:

1. Clear the search box and try again
2. Refresh the page
3. Check browser console for errors

### Styling Issues

**Problem**: Layout looks broken or unstyled

**Solutions**:

1. Ensure Tailwind CSS is properly built
2. Run `npm install` in the web directory
3. Rebuild the application with `npm run build`
4. Clear browser cache

## Related Documentation

- [Command Palette](./command-palette.md): Global search in browser extension
- [Workspace Operations](./workspace-operations.md): Managing workspaces
- [Getting Started](../getting-started/development.md): Development setup

## Support

For issues or questions about the web dashboard:

1. Check the [GitHub Issues](https://github.com/VitruvianSoftware/vitruvian-core/issues)
2. Review the [Contributing Guide](../../../tabula/CONTRIBUTING.md)
3. Contact the maintainers
