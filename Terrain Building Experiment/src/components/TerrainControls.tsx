import React from 'react';
import type { TerrainConfig, ViewSettings, ElevationGrid, InspectInfo } from '../types';

const PRESETS = [
  { name: 'Pinch Brook GC', lat: 40.793526, lng: -74.38804, size: 1200 },
  { name: 'Augusta National', lat: 33.5021, lng: -82.0206, size: 1800 },
  { name: 'Pebble Beach', lat: 36.5681, lng: -121.9503, size: 1600 },
  { name: 'St Andrews Old', lat: 56.3429, lng: -2.8022, size: 1800 },
];

interface Props {
  config: TerrainConfig;
  viewSettings: ViewSettings;
  elevGrid: ElevationGrid | null;
  inspectInfo: InspectInfo | null;
  loading: boolean;
  loadingMsg: string;
  error: string | null;
  onConfigChange: (c: TerrainConfig) => void;
  onViewChange: (v: ViewSettings) => void;
  onGenerate: () => void;
}

function Slider({
  label, value, min, max, step, onChange, unit = '',
}: {
  label: string; value: number; min: number; max: number;
  step: number; onChange: (v: number) => void; unit?: string;
}) {
  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
        <span style={{ color: '#aab8c8', fontSize: 12 }}>{label}</span>
        <span style={{ color: '#e0eaf5', fontSize: 12, fontWeight: 600 }}>
          {value}{unit}
        </span>
      </div>
      <input
        type="range"
        min={min} max={max} step={step} value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        style={{ width: '100%', accentColor: '#4a9eff' }}
      />
    </div>
  );
}

function Input({
  label, value, onChange, type = 'number', step,
}: {
  label: string; value: string | number; type?: string;
  step?: number; onChange: (v: string) => void;
}) {
  return (
    <div style={{ marginBottom: 10 }}>
      <div style={{ color: '#aab8c8', fontSize: 11, marginBottom: 3 }}>{label}</div>
      <input
        type={type}
        value={value}
        step={step}
        onChange={(e) => onChange(e.target.value)}
        style={{
          width: '100%', background: '#0f1923', border: '1px solid #2a3f5f',
          borderRadius: 4, color: '#e0eaf5', padding: '6px 8px',
          fontSize: 13, boxSizing: 'border-box',
        }}
      />
    </div>
  );
}

export default function TerrainControls({
  config, viewSettings, elevGrid, inspectInfo,
  loading, loadingMsg, error,
  onConfigChange, onViewChange, onGenerate,
}: Props) {
  const set = (k: keyof TerrainConfig, v: string | number) =>
    onConfigChange({ ...config, [k]: typeof v === 'string' ? parseFloat(v) || 0 : v });

  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, width: 300, height: '100%',
      background: 'rgba(10,18,30,0.92)', backdropFilter: 'blur(8px)',
      borderRight: '1px solid #1e2f45', overflowY: 'auto', zIndex: 10,
      padding: '20px 16px', boxSizing: 'border-box', display: 'flex',
      flexDirection: 'column', gap: 0,
    }}>
      <div style={{ color: '#4a9eff', fontSize: 11, letterSpacing: 2, marginBottom: 2 }}>
        TERRAIN BUILDER
      </div>
      <div style={{ color: '#e0eaf5', fontSize: 16, fontWeight: 700, marginBottom: 16 }}>
        Experiment v1
      </div>

      {/* Presets */}
      <div style={{ color: '#aab8c8', fontSize: 11, marginBottom: 6 }}>PRESETS</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 16 }}>
        {PRESETS.map((p) => (
          <button
            key={p.name}
            onClick={() =>
              onConfigChange({ ...config, lat: p.lat, lng: p.lng, widthMeters: p.size, heightMeters: p.size })
            }
            style={{
              background: '#0f1923', border: '1px solid #2a3f5f', borderRadius: 4,
              color: '#aab8c8', fontSize: 10, padding: '4px 8px', cursor: 'pointer',
            }}
          >
            {p.name}
          </button>
        ))}
      </div>

      <div style={{ borderTop: '1px solid #1e2f45', paddingTop: 14, marginBottom: 14 }}>
        <div style={{ color: '#aab8c8', fontSize: 11, marginBottom: 10 }}>COORDINATES</div>
        <Input label="Latitude" value={config.lat} step={0.0001} onChange={(v) => set('lat', v)} />
        <Input label="Longitude" value={config.lng} step={0.0001} onChange={(v) => set('lng', v)} />

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
          <Input label="Width (m)" value={config.widthMeters} step={100} onChange={(v) => set('widthMeters', v)} />
          <Input label="Height (m)" value={config.heightMeters} step={100} onChange={(v) => set('heightMeters', v)} />
        </div>

        <div style={{ marginBottom: 10 }}>
          <div style={{ color: '#aab8c8', fontSize: 11, marginBottom: 3 }}>Resolution</div>
          <select
            value={config.resolution}
            onChange={(e) => onConfigChange({ ...config, resolution: parseInt(e.target.value) as 128 | 256 | 512 })}
            style={{
              width: '100%', background: '#0f1923', border: '1px solid #2a3f5f',
              borderRadius: 4, color: '#e0eaf5', padding: '6px 8px', fontSize: 13,
            }}
          >
            <option value={128}>128 × 128 (fast)</option>
            <option value={256}>256 × 256 (default)</option>
            <option value={512}>512 × 512 (high detail)</option>
          </select>
        </div>

        <button
          onClick={onGenerate}
          disabled={loading}
          style={{
            width: '100%', padding: '10px 0', borderRadius: 6,
            background: loading ? '#1e2f45' : '#4a9eff',
            color: loading ? '#5a7080' : '#fff', border: 'none',
            fontWeight: 700, fontSize: 13, cursor: loading ? 'not-allowed' : 'pointer',
            transition: 'background 0.15s',
          }}
        >
          {loading ? '⟳ Loading…' : '⬡ Generate Terrain'}
        </button>

        {loadingMsg && (
          <div style={{ color: '#4a9eff', fontSize: 11, marginTop: 8, lineHeight: 1.5 }}>
            {loadingMsg}
          </div>
        )}
        {error && (
          <div style={{ color: '#ff6b6b', fontSize: 11, marginTop: 8, lineHeight: 1.5 }}>
            ⚠ {error}
          </div>
        )}
      </div>

      {/* View settings */}
      <div style={{ borderTop: '1px solid #1e2f45', paddingTop: 14, marginBottom: 14 }}>
        <div style={{ color: '#aab8c8', fontSize: 11, marginBottom: 12 }}>VIEW SETTINGS</div>

        <Slider
          label="Elevation Exaggeration"
          value={viewSettings.elevExaggeration}
          min={1} max={10} step={0.5}
          onChange={(v) => onViewChange({ ...viewSettings, elevExaggeration: v })}
          unit="×"
        />
        <Slider
          label="Terrain Smoothing"
          value={viewSettings.smoothingPasses}
          min={0} max={100} step={25}
          onChange={(v) => onViewChange({ ...viewSettings, smoothingPasses: v })}
          unit="%"
        />
        <Slider
          label="Sun Azimuth"
          value={viewSettings.sunAzimuth}
          min={0} max={360} step={5}
          onChange={(v) => onViewChange({ ...viewSettings, sunAzimuth: v })}
          unit="°"
        />

        <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', marginTop: 4 }}>
          <input
            type="checkbox"
            checked={viewSettings.showSatellite}
            onChange={(e) => onViewChange({ ...viewSettings, showSatellite: e.target.checked })}
            style={{ accentColor: '#4a9eff' }}
          />
          <span style={{ color: '#aab8c8', fontSize: 12 }}>Satellite texture</span>
        </label>
      </div>

      {/* Debug stats */}
      {elevGrid && (
        <div style={{ borderTop: '1px solid #1e2f45', paddingTop: 14, marginBottom: 14 }}>
          <div style={{ color: '#aab8c8', fontSize: 11, marginBottom: 10 }}>DEBUG INFO</div>
          {[
            ['Lat', config.lat.toFixed(6)],
            ['Lng', config.lng.toFixed(6)],
            ['Width', `${config.widthMeters} m`],
            ['Height', `${config.heightMeters} m`],
            ['Elev min', `${elevGrid.minElevation.toFixed(1)} m`],
            ['Elev max', `${elevGrid.maxElevation.toFixed(1)} m`],
            ['Elev range', `${(elevGrid.maxElevation - elevGrid.minElevation).toFixed(1)} m`],
            ['Vertices', (elevGrid.rows * elevGrid.cols).toLocaleString()],
            ['Resolution', `${elevGrid.rows} × ${elevGrid.cols}`],
          ].map(([k, v]) => (
            <div key={k} style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
              <span style={{ color: '#5a7080', fontSize: 11 }}>{k}</span>
              <span style={{ color: '#e0eaf5', fontSize: 11, fontFamily: 'monospace' }}>{v}</span>
            </div>
          ))}
        </div>
      )}

      {/* Inspector */}
      {inspectInfo && (
        <div style={{ borderTop: '1px solid #1e2f45', paddingTop: 14 }}>
          <div style={{ color: '#4a9eff', fontSize: 11, marginBottom: 10 }}>
            ✦ TERRAIN INSPECTOR
          </div>
          {[
            ['Latitude', inspectInfo.lat.toFixed(6)],
            ['Longitude', inspectInfo.lng.toFixed(6)],
            ['Elevation', `${inspectInfo.elevation.toFixed(1)} m`],
            ['World X', `${inspectInfo.worldX.toFixed(1)} m`],
            ['World Z', `${inspectInfo.worldZ.toFixed(1)} m`],
          ].map(([k, v]) => (
            <div key={k} style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 4 }}>
              <span style={{ color: '#5a7080', fontSize: 11 }}>{k}</span>
              <span style={{ color: '#7fd9a0', fontSize: 11, fontFamily: 'monospace' }}>{v}</span>
            </div>
          ))}
        </div>
      )}

      <div style={{ marginTop: 'auto', paddingTop: 16, color: '#2a3f5f', fontSize: 10 }}>
        Click terrain to inspect • Orbit + scroll to navigate
      </div>
    </div>
  );
}
