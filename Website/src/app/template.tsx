// A template (unlike a layout) re-mounts on every navigation, so the wrapper's
// CSS animation replays each time — giving every route a smooth fade-in as you
// move from tab to tab. Styling lives in `.route-fade` (globals.css); this stays
// a server component so it adds no client JS.
export default function Template({ children }: { children: React.ReactNode }) {
  return <div className="route-fade">{children}</div>;
}
