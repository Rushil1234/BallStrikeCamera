import { useState, useRef, useCallback } from 'react';
import * as THREE from 'three';
import TerrainViewer from '../components/TerrainViewer';
import TerrainControls from '../components/TerrainControls';
import { fetchElevationGrid } from '../services/ElevationService';
import { fetchSatelliteTexture } from '../services/SatelliteService';
import type { TerrainConfig, ElevationGrid, ViewSettings, InspectInfo } from '../types';

const DEFAULT_CONFIG: TerrainConfig = {
  lat: 40.793526,
  lng: -74.38804,
  widthMeters: 1200,
  heightMeters: 1200,
  resolution: 256,
};

const DEFAULT_VIEW: ViewSettings = {
  elevExaggeration: 2,
  smoothingPasses: 0,
  showSatellite: true,
  sunAzimuth: 225,
};

export default function TerrainExperiment() {
  const [config, setConfig] = useState<TerrainConfig>(DEFAULT_CONFIG);
  const [viewSettings, setViewSettings] = useState<ViewSettings>(DEFAULT_VIEW);

  const [elevGrid, setElevGrid] = useState<ElevationGrid | null>(null);
  const [satTexture, setSatTexture] = useState<THREE.CanvasTexture | null>(null);
  const [activeConfig, setActiveConfig] = useState<TerrainConfig>(DEFAULT_CONFIG);

  const [loading, setLoading] = useState(false);
  const [loadingMsg, setLoadingMsg] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [inspectInfo, setInspectInfo] = useState<InspectInfo | null>(null);
  const [resetKey, setResetKey] = useState(0);

  const prevTexture = useRef<THREE.CanvasTexture | null>(null);

  const handleGenerate = useCallback(async () => {
    if (loading) return;
    setLoading(true);
    setError(null);
    setInspectInfo(null);

    try {
      const elev = await fetchElevationGrid(
        config.lat, config.lng,
        config.widthMeters, config.heightMeters,
        config.resolution,
        setLoadingMsg
      );
      setElevGrid(elev);

      setLoadingMsg('Fetching satellite imagery…');
      const sat = await fetchSatelliteTexture(
        config.lat, config.lng,
        config.widthMeters, config.heightMeters,
        setLoadingMsg
      );

      // Dispose old satellite texture
      prevTexture.current?.dispose();
      prevTexture.current = sat;
      setSatTexture(sat);

      setActiveConfig(config);
      setResetKey((k) => k + 1);
      setLoadingMsg('');
    } catch (e) {
      setError((e as Error).message);
      setLoadingMsg('');
    } finally {
      setLoading(false);
    }
  }, [config, loading]);

  return (
    <div style={{ width: '100vw', height: '100vh', position: 'relative', overflow: 'hidden', background: '#0a1218' }}>
      <TerrainViewer
        elevGrid={elevGrid}
        satTexture={satTexture}
        widthMeters={activeConfig.widthMeters}
        heightMeters={activeConfig.heightMeters}
        originLat={activeConfig.lat}
        originLng={activeConfig.lng}
        viewSettings={viewSettings}
        resetKey={resetKey}
        onInspect={setInspectInfo}
      />
      <TerrainControls
        config={config}
        viewSettings={viewSettings}
        elevGrid={elevGrid}
        inspectInfo={inspectInfo}
        loading={loading}
        loadingMsg={loadingMsg}
        error={error}
        onConfigChange={setConfig}
        onViewChange={setViewSettings}
        onGenerate={handleGenerate}
      />
    </div>
  );
}
