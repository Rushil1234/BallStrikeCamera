# TrueCarry Coach — Golf Lessons Mode: Master Plan
_Approved 2026-07-14. Decisions: **Pro-only**, **iOS 17 pose-3D with 2D fallback**, **questionnaire-only intake**._

## Vision
A 4th Play mode: guided curriculum from "never held a club" → real Range-mode hitting, built on:
1. **Curriculum engine** — tracks → lessons → steps (explainer / video / model3D / check3D / swingCapture / quiz), personalized by intake, with mastery gates. Content = versioned JSON (`Resources/Lessons/curriculum.json`, folder-ref so file swap re-ships) + future backend overrides.
2. **Swing Studio** — NEW vertical capture stack (never touches CameraController): back camera high-fps guided mode w/ voice prompts + pose-driven auto-record; front camera mirror mode; face-on view first, DTL phase 3. Analysis AFTER capture: Vision 2D body pose per frame (+3D keyframes on iOS 17), One-Euro smoothing, phase segmentation (Address→Takeaway→Backswing→Top→Downswing→Impact→Follow→Finish), face-on metrics (tempo ratio, head sway, hip slide, spine tilt, lead-arm, finish balance), 0-100 skill-banded Swing Score, JSON fault library → drills/lessons/video recs.
3. **Coaching engine** — persistent PlayerSwingModel (metric trends, active faults, mastery), next-best-lesson, 1-win+1-focus feedback, weekly recap, guided-Range graduation gate (ShotContext.lessonContext).

## Curriculum tracks
A Foundations (grip 3D+check, setup, alignment, takeaway, L-to-L, full motion, first contact → guided Range graduation) · B Slice fix · C Hook fix · D Contact · E Tempo/sequencing · F Distance · G On-course.

## Integrations
History (.lesson + .swing timeline items, replay w/ skeleton overlay + drawing tools later), Insights swing section, Feed posts, WeeklyGoals credits, Range/ShotContext handoff, Drive dev-upload of swing clips (future training corpus), Entitlements: whole mode Pro (dev bypass).

## Backend (deferred to sync phase)
Migrations ~041+: lesson_profiles, lesson_progress, swing_recordings (+metrics JSONB), swing_videos bucket, lesson_content_overrides, coach_video_catalog (recommender queries from day 1; empty until filmed). Phase 1 persists local-first (AppStorageManager lessons/ + swings/ dirs).

## Phases
1. **Skeleton+Studio MVP (BUILT 2026-07-14)**: Lessons card, intake, curriculum engine (all 6 step types; model3D loads USDZ when present else diagram fallback), Swing Studio face-on auto-record, pose pipeline + score, replay w/ skeleton, local persistence, History integration, Track A-E content.
2. 3D USDZ assets (contractor/Blender), hand-pose grip verification hardening, full fault library, weakness chips, guided Range graduation, Feed/Goals wiring, drawing tools.
3. DTL view + plane/path metrics, pose↔ball-data fault confirmation, side-by-side compare, Insights section, video catalog + backend sync, cloud video backup.
4. Custom pose model (Drive corpus), club-shaft line detection, voiceover slow-mo export, coach marketplace.

## Honest limits
Pose can't see club face/true path (fusion with ball data is the answer + differentiator). Mid-downswing joints blur; score from reliable frames (address/top/impact/finish). Videos are catalog entries — film later, zero code change.
