// Sim demo: a looping gameplay video (recorded from the real sim) that links
// straight to the playable sim on click. The poster image covers browsers
// that can't decode the webm.
export default function SimDemo() {
  return (
    <a className="sim-demo" href="/play" aria-label="Play the True Carry Sim">
      <video
        className="sim-demo-video"
        autoPlay
        muted
        loop
        playsInline
        preload="metadata"
        poster="/sim-demo-poster.jpg"
        aria-hidden="true"
      >
        <source src="/sim-demo.webm" type="video/webm" />
      </video>
      <span className="sim-demo-badge">Live browser sim</span>
      <span className="sim-demo-play">
        <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
          <path d="M8 5v14l11-7z" fill="currentColor" />
        </svg>
        Tee off →
      </span>
    </a>
  );
}
