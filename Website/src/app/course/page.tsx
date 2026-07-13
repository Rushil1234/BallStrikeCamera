"use client";

import { useState } from "react";
import SiteNav from "@/components/SiteNav";
import SimHost from "@/components/SimHost";
import { SIM_COURSES, simCoursePath, type SimCourse } from "@/lib/courses";
import Link from "next/link";

const COURSES = SIM_COURSES.filter((c) => c.hrefMode === "course");

export default function CoursePage() {
  const [launched, setLaunched] = useState<SimCourse | null>(null);

  if (launched) {
    return (
      <SimHost
        src={simCoursePath(launched)}
        title={launched.name}
        backLabel="← Courses"
        onBack={() => setLaunched(null)}
      />
    );
  }

  return (
    <>
      <SiteNav />
      <main className="course-landing">
        <div className="course-header">
          <div className="course-eyebrow">Course Simulator</div>
          <h1 className="course-title">Play real courses in True Carry</h1>
          <p className="course-desc">
            Full 18-hole courses mapped from real GPS, elevation, and satellite data.
            No launcher needed, just click and play.
          </p>
        </div>

        <div className="course-grid">
          {COURSES.map((c) => (
            <div key={c.id} className="course-card">
              <div
                className="course-card-img"
                style={{ backgroundImage: `url(${c.preview})` }}
              />
              <div className="course-card-body">
                <div className="course-card-name">{c.name}</div>
                <div className="course-card-meta">
                  {c.location} · {c.holes} holes · Par {c.par}
                </div>
                <button
                  className="course-card-btn"
                  onClick={() => setLaunched(c)}
                >
                  Play Now →
                </button>
              </div>
            </div>
          ))}

          {/* Coming soon placeholder */}
          <div className="course-card course-card-soon">
            <div className="course-card-img course-card-img-soon" />
            <div className="course-card-body">
              <div className="course-card-name" style={{ color: "var(--muted)" }}>
                More courses coming soon
              </div>
              <div className="course-card-meta">
                Request a course in-app or on Discord
              </div>
            </div>
          </div>
        </div>

        <div className="course-footer-note">
          <p>
            Courses are built from open geographic data (OSM + USGS elevation).
            Using True Carry with a launch monitor?{" "}
            <Link href="/play" className="course-link">Use Course Select</Link> instead.
          </p>
        </div>
      </main>

      <style>{`
        .course-landing {
          min-height: 100vh;
          padding: 100px 24px 60px;
          background: var(--bg);
          max-width: 960px;
          margin: 0 auto;
        }
        .course-header {
          text-align: center;
          margin-bottom: 56px;
        }
        .course-eyebrow {
          font-size: 11px;
          font-weight: 700;
          letter-spacing: 0.16em;
          text-transform: uppercase;
          color: var(--gold);
          margin-bottom: 14px;
        }
        .course-title {
          font-size: clamp(2rem, 5vw, 3rem);
          font-weight: 800;
          color: var(--cream);
          margin-bottom: 16px;
          line-height: 1.12;
        }
        .course-desc {
          font-size: 15px;
          color: var(--muted);
          line-height: 1.65;
          max-width: 520px;
          margin: 0 auto;
        }
        .course-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
          gap: 24px;
          margin-bottom: 48px;
        }
        .course-card {
          border-radius: 14px;
          overflow: hidden;
          border: 1px solid var(--border);
          background: var(--surface);
          transition: transform 0.18s, box-shadow 0.18s;
        }
        .course-card:hover {
          transform: translateY(-2px);
          box-shadow: 0 8px 32px rgba(0,0,0,0.35);
        }
        .course-card-soon { opacity: 0.45; pointer-events: none; }
        .course-card-img {
          height: 160px;
          background-size: cover;
          background-position: center;
          background-color: #0e1a10;
        }
        .course-card-img-soon {
          background: repeating-linear-gradient(
            45deg,
            #111 0px, #111 10px,
            #151b15 10px, #151b15 20px
          );
        }
        .course-card-body {
          padding: 16px 18px 20px;
        }
        .course-card-name {
          font-size: 1rem;
          font-weight: 700;
          color: var(--cream);
          margin-bottom: 4px;
        }
        .course-card-meta {
          font-size: 12px;
          color: var(--muted);
          margin-bottom: 14px;
        }
        .course-card-btn {
          width: 100%;
          padding: 10px 0;
          border-radius: 9px;
          border: none;
          background: linear-gradient(135deg, #8CA585 0%, #4d7a55 100%);
          color: #fff;
          font-size: 14px;
          font-weight: 700;
          letter-spacing: 0.04em;
          cursor: pointer;
          transition: opacity 0.15s;
        }
        .course-card-btn:hover { opacity: 0.88; }
        .course-footer-note {
          text-align: center;
          font-size: 13px;
          color: var(--faint);
          border-top: 1px solid var(--border);
          padding-top: 32px;
        }
        .course-link { color: var(--gold); text-decoration: none; }
        .course-link:hover { text-decoration: underline; }

        /* Fullscreen iframe */
        .course-fullscreen {
          position: fixed;
          inset: 0;
          background: #0a110c;
          z-index: 1000;
        }
        .course-iframe {
          width: 100%;
          height: 100%;
          border: none;
          display: block;
        }
        .course-back-btn {
          position: fixed;
          top: 14px;
          left: 14px;
          z-index: 1001;
          padding: 7px 16px;
          border-radius: 18px;
          border: 1px solid rgba(255,255,255,0.18);
          background: rgba(0,0,0,0.58);
          color: rgba(255,255,255,0.7);
          font-size: 12px;
          font-weight: 600;
          cursor: pointer;
          backdrop-filter: blur(8px);
          transition: color 0.15s;
        }
        .course-back-btn:hover { color: #fff; }
      `}</style>
    </>
  );
}
