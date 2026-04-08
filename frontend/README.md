# Frontend

React 18 single-page chatbot UI built with Vite and CSS Modules. Communicates with the backend over REST, manages per-tab session IDs, renders assistant replies as Markdown, and shows context-aware follow-up suggestion chips.

---

## Key files

| File | Role |
|---|---|
| `src/App.jsx` | Root component; composes all sub-components and handles top-level layout |
| `src/hooks/useChat.js` | All chat state and API logic: messages, session ID, system prompt, provider, suggestions |
| `src/components/ChatWindow.jsx` | Scrollable message list; auto-scrolls to the latest message |
| `src/components/MessageBubble.jsx` | Renders a single message; Markdown + GFM for assistant replies, plain text for user messages |
| `src/components/InputBar.jsx` | Textarea and send button; Enter sends, Shift+Enter inserts a newline |
| `src/components/SystemPromptPanel.jsx` | Collapsible editor for the system prompt; locked during an active conversation |
| `src/components/LLMProviderPanel.jsx` | Collapsible radio selector for `nim_api` vs `self_hosted`; locked during an active conversation |
| `src/components/SuggestionChips.jsx` | Pill buttons for follow-up questions; clicking a chip sends that text as a new message |
| `vite.config.js` | Vite config; defines the `/api` → `localhost:8000` dev-server proxy |

---

## Configuration

### Environment variables

The frontend uses `.env.local` for local environment-specific configuration (gitignored by the `*.local` pattern).

**Required variable:**

- `VITE_DYNATRACE_RUM_URL` — Full URL to your Dynatrace RUM JavaScript tag (injected into `index.html` at build time)

**Setup:**

```bash
# Copy the example file
cp .env.example .env.local

# Edit .env.local and replace the placeholder with your actual Dynatrace RUM URL
# Get your URL from: Dynatrace > Web Applications > Your App > ... > Edit > Setup
```

`.env.example` is committed to the repo as a template; `.env.local` contains your actual values and stays out of version control.

### Dev proxy

In development, all `/api/*` requests are proxied to the backend at `http://localhost:8000` by the Vite dev server. See `vite.config.js`:

```js
server: {
  proxy: {
    '/api': {
      target: 'http://localhost:8000',
      changeOrigin: true,
    },
  },
}
```

---

## Running locally

The backend must be running first (see [backend/README.md](../backend/README.md)).

```bash
cd frontend
npm install
npm run dev
```

Open `http://localhost:5173`.

Other scripts:

```bash
npm run build    # production build → dist/
npm run preview  # serve the production build locally
npm run lint     # run ESLint
```



---

## Key behaviours

### Session ID

- A UUID is generated via `crypto.randomUUID()` when the page loads and is stable for the lifetime of the tab.
- Reloading the page creates a new session — previous messages are lost from both the UI and the server.

### System prompt and provider

- The system prompt and LLM provider selector are **locked** while there are messages in the conversation.
- Changes only take effect after clearing the conversation history.
- The system prompt applies to the **next** message sent; it does not alter existing messages retroactively.

### Starter suggestions

- When the conversation is empty (on load, or after clearing history), the frontend calls `POST /api/chat/starters` using the current system prompt and displays the results as suggestion chips.
- Starter chips are also refreshed whenever the system prompt is changed while the conversation is empty.

### Follow-up suggestions

- After each assistant reply, the backend returns up to 3 follow-up question strings.
- These are displayed as chips below the reply.
- Clicking a chip sends that question as a new message and clears the chips.
- Chips are also cleared immediately when the user starts typing a new message.

### Markdown rendering

Assistant messages are rendered as Markdown using `react-markdown` with `remark-gfm`, supporting code blocks, tables, links, and lists.

---

## Styling

- Each component has a co-located `.module.css` file (e.g. `ChatWindow.module.css`).
- No external CSS framework is used — all styling is plain CSS with modern flexbox/grid.
- Global resets and fonts are in `src/index.css`.
