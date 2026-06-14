import { useEffect, useMemo, useRef, Suspense } from 'react';
import { Canvas, ThreeEvent } from '@react-three/fiber';
import * as THREE from 'three';
import CameraController from './CameraController';
import { buildTerrainGeometry, sampleElevationAt } from '../services/TerrainBuilder';
import { metersPerDegreeLng, METERS_PER_DEG_LAT } from '../utils/CoordinateUtils';
import type { ElevationGrid, InspectInfo, ViewSettings } from '../types';

interface Props {
  elevGrid: ElevationGrid | null;
  satTexture: THREE.CanvasTexture | null;
  widthMeters: number;
  heightMeters: number;
  originLat: number;
  originLng: number;
  viewSettings: ViewSettings;
  resetKey: number;
  onInspect: (info: InspectInfo) => void;
}

function TerrainMesh({
  elevGrid,
  satTexture,
  widthMeters,
  heightMeters,
  originLat,
  originLng,
  viewSettings,
  onInspect,
}: Omit<Props, 'resetKey'>) {
  const geoRef = useRef<THREE.BufferGeometry | null>(null);

  const geometry = useMemo(() => {
    if (!elevGrid) return null;
    const geo = buildTerrainGeometry(elevGrid, {
      widthMeters,
      heightMeters,
      elevExaggeration: viewSettings.elevExaggeration,
      smoothingPct: viewSettings.smoothingPasses,
    });
    return geo;
  }, [elevGrid, widthMeters, heightMeters, viewSettings.elevExaggeration, viewSettings.smoothingPasses]);

  useEffect(() => {
    const prev = geoRef.current;
    geoRef.current = geometry;
    return () => { prev?.dispose(); };
  }, [geometry]);

  const handleClick = (e: ThreeEvent<MouseEvent>) => {
    if (!elevGrid) return;
    e.stopPropagation();
    const p = e.point;
    const lat = originLat + p.z / METERS_PER_DEG_LAT;
    const lng = originLng + p.x / metersPerDegreeLng(originLat);
    const elevation = sampleElevationAt(p.x, p.z, elevGrid, widthMeters, heightMeters);
    onInspect({ lat, lng, elevation, worldX: p.x, worldZ: p.z });
  };

  if (!geometry) return null;

  return (
    <mesh geometry={geometry} onClick={handleClick} receiveShadow castShadow>
      {viewSettings.showSatellite && satTexture ? (
        <meshStandardMaterial
          map={satTexture}
          roughness={0.9}
          metalness={0}
        />
      ) : (
        <meshStandardMaterial
          color="#5a7a4a"
          roughness={0.9}
          metalness={0}
          wireframe={false}
        />
      )}
    </mesh>
  );
}

function SunLight({ azimuthDeg }: { azimuthDeg: number }) {
  const az = (azimuthDeg * Math.PI) / 180;
  const dist = 800;
  return (
    <directionalLight
      position={[Math.sin(az) * dist, dist * 0.6, Math.cos(az) * dist]}
      intensity={1.6}
      castShadow
      shadow-mapSize-width={2048}
      shadow-mapSize-height={2048}
    />
  );
}

export default function TerrainViewer({
  elevGrid,
  satTexture,
  widthMeters,
  heightMeters,
  originLat,
  originLng,
  viewSettings,
  resetKey,
  onInspect,
}: Props) {
  const terrainSize = Math.max(widthMeters, heightMeters);

  return (
    <Canvas
      shadows
      camera={{ fov: 50, near: 1, far: 20000, position: [0, terrainSize * 0.5, terrainSize * 0.8] }}
      gl={{ outputColorSpace: THREE.SRGBColorSpace, antialias: true }}
      style={{ background: '#1a2535' }}
    >
      <fog attach="fog" args={['#1a2535', terrainSize * 2, terrainSize * 4]} />
      <ambientLight intensity={0.35} />
      <SunLight azimuthDeg={viewSettings.sunAzimuth} />

      <Suspense fallback={null}>
        <TerrainMesh
          elevGrid={elevGrid}
          satTexture={satTexture}
          widthMeters={widthMeters}
          heightMeters={heightMeters}
          originLat={originLat}
          originLng={originLng}
          viewSettings={viewSettings}
          onInspect={onInspect}
        />
      </Suspense>

      {/* Subtle horizon grid when no terrain is loaded */}
      {!elevGrid && (
        <gridHelper args={[2000, 40, '#2a3f5f', '#1e2f45']} position={[0, 0, 0]} />
      )}

      <CameraController terrainSize={terrainSize || 1200} resetKey={resetKey} />
    </Canvas>
  );
}
