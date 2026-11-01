// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

package localapi

// toolDef is one tool as tools/list shows it. Its name and input schema (property names, types, enums, formats,
// required) match the reference app's tool exactly, as protocol/mcp-tools.json records it
// (TestToolsMatchReferenceSchemas), so a client written against the reference app works unchanged. The
// descriptions are Courier's own.
type toolDef struct {
	name        string
	description string
	schema      string // the input schema, JSON
}

// SearchDocsText is search_docs's one answer.
const SearchDocsText = "Courier has no documentation search. Each tool's description is its documentation."

var toolDefs = []toolDef{
	{
		name: "get_accounts",
		description: "List the chat accounts signed in to Courier on this Mac: one entry per account, with its " +
			"accountID, its network, the name the network gives it and whether it is connected.",
		schema: `{"type":"object","properties":{},"required":[]}`,
	},
	{
		name: "search",
		description: "Search everything at once: chats whose name matches, people in group chats who match, and " +
			"messages that contain the words. Returns the first page of each. Use search_chats or " +
			"search_messages to narrow down or to page further.",
		schema: `{"type":"object","properties":{
  "query":{"type":"string","description":"Words to look for. Messages need at least 2 letters; chats and people match from the first letter."}
},"required":["query"]}`,
	},
	{
		name: "search_chats",
		description: "Find chats, newest activity first. Every argument narrows the list. Pages go by cursor: " +
			"pass a page's oldestCursor with direction \"before\" for older chats, or its newestCursor with " +
			"direction \"after\" for newer ones.",
		schema: `{"type":"object","properties":{
  "accountIDs":{"type":"array","items":{"type":"string"},"description":"Only chats on these accounts (from get_accounts)."},
  "cursor":{"type":"string","description":"A cursor from an earlier page."},
  "direction":{"type":"string","enum":["after","before"],"description":"Which way to page from cursor: before is older, after is newer. Defaults to before."},
  "inbox":{"type":"string","enum":["primary","low-priority","archive"],"description":"Only chats in this part of the inbox. Left out: all three."},
  "includeMuted":{"type":"boolean","description":"Include muted chats. Defaults to true."},
  "lastActivityAfter":{"type":"string","format":"date-time","description":"Only chats with a message after this time (RFC 3339)."},
  "lastActivityBefore":{"type":"string","format":"date-time","description":"Only chats whose latest message is before this time (RFC 3339)."},
  "limit":{"type":"integer","description":"How many chats, 1 to 200. Defaults to 50."},
  "query":{"type":"string","description":"Text the chat's name (or, with scope participants, a member's name) must contain."},
  "scope":{"type":"string","enum":["titles","participants"],"description":"What query matches: the chat's name (titles, the default) or its members' names (participants)."},
  "type":{"type":"string","enum":["single","group","any"],"description":"One-to-one chats, groups, or any (the default)."},
  "unreadOnly":{"type":"boolean","description":"Only chats with unread messages, or marked unread."}
},"required":[]}`,
	},
	{
		name: "search_messages",
		description: "Find messages that contain words, newest first, with the chats they are in. Every argument " +
			"narrows the results. Pages go by cursor, as in search_chats. To read a chat's latest messages " +
			"without searching, use list_messages.",
		schema: `{"type":"object","properties":{
  "accountIDs":{"type":"array","items":{"type":"string"},"description":"Only messages in chats on these accounts."},
  "chatIDs":{"type":"array","items":{"type":"string"},"description":"Only messages in these chats (1 to 100)."},
  "chatType":{"type":"string","enum":["group","single"],"description":"Only group chats, or only one-to-one chats."},
  "cursor":{"type":"string","description":"A cursor from an earlier page."},
  "dateAfter":{"type":"string","format":"date-time","description":"Only messages sent at or after this time (RFC 3339)."},
  "dateBefore":{"type":"string","format":"date-time","description":"Only messages sent before this time (RFC 3339)."},
  "direction":{"type":"string","enum":["after","before"],"description":"Which way to page from cursor: before is older, after is newer. Defaults to before."},
  "excludeLowPriority":{"type":"boolean","description":"Leave out chats marked low priority. Defaults to true."},
  "includeMuted":{"type":"boolean","description":"Include muted chats. Defaults to true."},
  "limit":{"type":"integer","description":"How many messages, 1 to 200. Defaults to 20."},
  "mediaTypes":{"type":"array","items":{"type":"string","enum":["any","video","image","link","file"]},"description":"Only messages carrying these: any attachment or link, videos, images, links or files."},
  "query":{"type":"string","description":"Words the message must contain: at least 2 letters. Quotes make a phrase."},
  "sender":{"anyOf":[{"type":"string","enum":["me","others"]},{"type":"string"}],"description":"me, others, or one person's senderID."}
},"required":[]}`,
	},
	{
		name:        "get_chat",
		description: "Get one chat: its name, network, account, unread count, state and members.",
		schema: `{"type":"object","properties":{
  "chatID":{"type":"string","description":"The chat's ID."},
  "maxParticipantCount":{"type":"integer","description":"How many members to list: 0 to 500, or -1 for all. Defaults to 20."}
},"required":["chatID"]}`,
	},
	{
		name: "list_messages",
		description: "Read a chat's messages, 20 at a time, newest first. Without a cursor it starts at the newest " +
			"message. Pass the page's oldestCursor with direction \"before\" for older messages, or its " +
			"newestCursor with direction \"after\" for newer ones. A cursor keeps working as new messages arrive.",
		schema: `{"type":"object","properties":{
  "chatID":{"type":"string","description":"The chat's ID."},
  "cursor":{"type":"string","description":"A cursor from an earlier page."},
  "direction":{"type":"string","enum":["after","before"],"description":"Which way to page from cursor: before is older, after is newer. Defaults to before."}
},"required":["chatID"]}`,
	},
	{
		name: "send_message",
		description: "Send a text message to a chat, through the chat's own account. Markdown (bold, italic, " +
			"strikethrough, code, links) is sent as formatting. Only works when this connection has been allowed " +
			"to send messages in Courier's settings.",
		schema: `{"type":"object","properties":{
  "chatID":{"type":"string","description":"The chat to send to."},
  "replyToMessageID":{"type":"string","description":"A message in the chat to reply to."},
  "text":{"type":"string","description":"The message, in Markdown."}
},"required":["chatID"]}`,
	},
	{
		name:        "archive_chat",
		description: "Archive a chat, or bring it back from the archive. A pinned chat can't be archived.",
		schema: `{"type":"object","properties":{
  "archived":{"type":"boolean","description":"true to archive (the default), false to unarchive."},
  "chatID":{"type":"string","description":"The chat."}
},"required":["chatID"]}`,
	},
	{
		name:        "set_chat_reminder",
		description: "Set a reminder on a chat: at the time given, the chat comes back to the top of the inbox, marked unread.",
		schema: `{"type":"object","properties":{
  "chatID":{"type":"string","description":"The chat."},
  "reminder":{"type":"object","properties":{
    "dismissOnIncomingMessage":{"type":"boolean","description":"When true, the reminder is dropped once the chat has a reply from you before it is due."},
    "remindAtMs":{"type":"number","description":"When to remind, in Unix milliseconds. Must be in the future."}
  },"required":["remindAtMs"],"description":"When, and on what condition."}
},"required":["chatID","reminder"]}`,
	},
	{
		name:        "clear_chat_reminder",
		description: "Remove a chat's reminder, whether or not it has gone off. A chat without one is not an error.",
		schema: `{"type":"object","properties":{
  "chatID":{"type":"string","description":"The chat."}
},"required":["chatID"]}`,
	},
	{
		name: "focus_app",
		description: "Bring Courier to the front, optionally opening a chat at a message, with a draft (text and " +
			"an attachment) put in its message box but not sent.",
		schema: `{"type":"object","properties":{
  "chatID":{"type":"string","description":"The chat to open."},
  "draftAttachmentPath":{"type":"string","description":"The path of a file on this Mac to attach to the draft. Needs chatID."},
  "draftText":{"type":"string","description":"Text to put in the chat's message box. Needs chatID."},
  "messageID":{"type":"string","description":"A message to scroll to."}
},"required":[]}`,
	},
	{
		name:        "search_docs",
		description: "Courier has no documentation to search: each tool's description is its documentation.",
		schema: `{"type":"object","properties":{
  "language":{"type":"string","enum":["http","python","go","typescript","terraform","ruby","java","kotlin"],"description":"Ignored."},
  "query":{"type":"string","description":"Ignored."}
},"required":["query","language"]}`,
	},
}
