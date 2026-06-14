import { useEffect, useRef } from 'react';
import { useThree } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import type { OrbitControls as OrbitControlsImpl } from 'three-stdlib';

interface Props {
  terrainSize: number;   // max(width, height) in metres, for positioning
  resetKey: number;      // increment to fly back to default view
}

export default function CameraController({ terrainSize, resetKey }: Props) {
  const ref = useRef<OrbitControlsImpl>(null);
  const { camera } = useThree();

  useEffect(() => {
    const dist = terrainSize * 0.75;
    camera.position.set(0, dist * 0.6, dist);
    camera.lookAt(0, 0, 0);
    ref.current?.target.set(0, 0, 0);
    ref.current?.update();
  }, [resetKey, terrainSize, camera]);

  return (
    <OrbitControls
      ref={ref}
      enablePan
      enableZoom
      enableRotate
      minDistance={10}
      maxDistance={terrainSize * 3}
      panSpeed={1.2}
      zoomSpeed={1.2}
    />
  );
}
